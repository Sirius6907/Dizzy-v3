import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/messaging/dm_outbox.dart';
import 'package:dizzy/services/messaging/oem_kill_detector.dart';

/// Phase K4 — DM outbox (never lose on kill) + OEM kill detector.
void main() {
  // Every test starts from a genuinely cold app: empty store, no in-memory
  // queue left over from the previous test's simulated "run".
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DmOutbox.resetMemory();
  });

  group('backoff', () {
    test('starts at ~1s and grows with attempts', () {
      final zero = DmOutbox.backoffMs(0, jitterSample: 5000);
      final two = DmOutbox.backoffMs(2, jitterSample: 5000);
      final four = DmOutbox.backoffMs(4, jitterSample: 5000);

      expect(zero, greaterThanOrEqualTo(800));
      expect(zero, lessThanOrEqualTo(1200));
      expect(two, greaterThan(zero));
      expect(four, greaterThan(two));
    });

    test(
      'is capped so a dead endpoint still gets retried every few minutes',
      () {
        for (final attempts in [5, 10, 30, 100, 100000]) {
          final ms = DmOutbox.backoffMs(attempts, jitterSample: 9999);
          expect(
            ms,
            lessThanOrEqualTo((DmOutbox.maxBackoffMs * 1.2).round()),
            reason: 'attempts=$attempts must not grow without bound',
          );
        }
      },
    );

    test('shift-overflow attempts do not become negative', () {
      final ms = DmOutbox.backoffMs(1000, jitterSample: 5000);
      expect(ms, greaterThan(0));
    });

    test('jitter stays inside +/-20%', () {
      final lo = DmOutbox.backoffMs(3, jitterSample: 0);
      final hi = DmOutbox.backoffMs(3, jitterSample: 9999);
      expect(lo, closeTo(6400, 1)); // 8000 * 0.8
      expect(hi, closeTo(9600, 1)); // 8000 * 1.2
      expect(hi / lo, closeTo(1.5, 0.05));
    });
  });

  group('due / exhausted', () {
    OutboxEntry entry({int attempts = 0, int lastAttemptMs = 0}) => OutboxEntry(
      id: 'id',
      recipientUid: 'u1',
      recipientUsername: 'friend',
      body: 'hi',
      createdAtMs: 1000,
      attempts: attempts,
      lastAttemptMs: lastAttemptMs,
    );

    test('never-attempted entries are immediately due', () {
      expect(DmOutbox.isDue(entry(), 999999999), isTrue);
    });

    test('a fresh failure must wait out its backoff', () {
      final e = entry(attempts: 1, lastAttemptMs: 10000);
      expect(DmOutbox.isDue(e, 10500), isFalse);
      expect(DmOutbox.isDue(e, 60000), isTrue);
    });

    test('exhausted entries stop being due instead of spinning forever', () {
      final e = entry(attempts: DmOutbox.maxAttempts, lastAttemptMs: 10000);
      expect(DmOutbox.isExhausted(e), isTrue);
      expect(DmOutbox.isDue(e, 999999999), isFalse);
    });

    test('dueNow keeps only what the clock says is due', () {
      const now = 1000000;
      final list = [
        entry(attempts: 0, lastAttemptMs: 0), // never tried → due
        entry(attempts: 1, lastAttemptMs: now - 60000), // backoff expired → due
        entry(attempts: 1, lastAttemptMs: now - 1), // still backing off → not
        entry(attempts: DmOutbox.maxAttempts, lastAttemptMs: 0), // spent → not
      ];
      final due = DmOutbox.dueNow(list, now);
      expect(due.length, 2);
      expect(due.any(DmOutbox.isExhausted), isFalse);
      expect(due.any((e) => e.lastAttemptMs == now - 1), isFalse);
    });
  });

  group('per-conversation ordering', () {
    test('stays oldest-first and ignores other recipients', () {
      OutboxEntry mk(String uid, String id, int ts) => OutboxEntry(
        id: id,
        recipientUid: uid,
        recipientUsername: 'x',
        body: 'b',
        createdAtMs: ts,
      );
      final list = [
        mk('u2', 'c', 30),
        mk('u1', 'b', 20),
        mk('u1', 'a', 10),
        mk('u1', 'd', 40),
      ];
      final mine = DmOutbox.forRecipient(list, 'u1');
      expect(mine.map((e) => e.id).toList(), ['a', 'b', 'd']);
    });
  });

  group('persistence', () {
    test('encode/decode round-trips attempts', () {
      final list = [
        const OutboxEntry(
          id: 'id',
          recipientUid: 'u1',
          recipientUsername: 'friend',
          body: 'hello',
          createdAtMs: 123,
          attempts: 4,
          lastAttemptMs: 456,
        ),
      ];
      final back = DmOutbox.decode(DmOutbox.encode(list));
      expect(back.length, 1);
      expect(back.first.attempts, 4);
      expect(back.first.lastAttemptMs, 456);
      expect(back.first.recipientUid, 'u1');
    });

    test('decode is fail-soft for junk and for dropped-field rows', () {
      expect(DmOutbox.decode(null), isEmpty);
      expect(DmOutbox.decode(''), isEmpty);
      expect(DmOutbox.decode('{{{'), isEmpty);
      expect(DmOutbox.decode('"a string"'), isEmpty);
      expect(
        DmOutbox.decode('[{"id":"","body":""}]'),
        isEmpty,
        reason: 'rows without a body are discarded, not queued',
      );
    });

    test(
      'a queued message survives a "kill": persist, reload, still there',
      () async {
        SharedPreferences.setMockInitialValues({});

        final e = await DmOutbox.enqueue(
          recipientUid: 'u1',
          recipientUsername: 'friend',
          body: 'survives a process death',
        );
        expect(e.body, isNotEmpty);

        // Simulate the kill: throw away all in-memory state, keep the store.
        DmOutbox.resetMemory();
        await DmOutbox.load();

        expect(DmOutbox.entries.value.length, 1);
        expect(DmOutbox.entries.value.first.body, 'survives a process death');
        expect(DmOutbox.entries.value.first.id, e.id);
      },
    );
  });

  group('flush', () {
    test('sends what succeeds, keeps what fails, counts both', () async {
      SharedPreferences.setMockInitialValues({});

      await DmOutbox.enqueue(
        recipientUid: 'ok',
        recipientUsername: 'a',
        body: 'first',
      );
      final bad = await DmOutbox.enqueue(
        recipientUid: 'bad',
        recipientUsername: 'b',
        body: 'second',
      );

      final sent = await DmOutbox.flush(
        send: (e) async => e.recipientUid == 'ok',
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );

      expect(sent, 1);
      expect(DmOutbox.entries.value.map((e) => e.id), [bad.id]);
      expect(
        DmOutbox.entries.value.single.attempts,
        1,
        reason: 'the failure is counted so backoff can grow',
      );
    });

    test(
      'a throwing send is treated as a failure, never an exception',
      () async {
        SharedPreferences.setMockInitialValues({});
        await DmOutbox.enqueue(
          recipientUid: 'u',
          recipientUsername: 'x',
          body: 'boom',
        );

        final sent = await DmOutbox.flush(
          send: (_) async => throw StateError('network'),
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );

        expect(sent, 0);
        expect(DmOutbox.entries.value.length, 1);
        expect(DmOutbox.entries.value.single.attempts, 1);
      },
    );

    test('an exhausted entry is left alone so the spinner stops', () async {
      SharedPreferences.setMockInitialValues({});
      final e = await DmOutbox.enqueue(
        recipientUid: 'u',
        recipientUsername: 'x',
        body: 'gave up',
      );
      for (var i = 0; i < DmOutbox.maxAttempts; i++) {
        await DmOutbox.recordFailure(e.id);
      }
      expect(DmOutbox.entries.value.single.attempts, DmOutbox.maxAttempts);

      final sent = await DmOutbox.flush(
        send: (_) async => false,
        nowMs: DateTime.now().millisecondsSinceEpoch + 99999999,
      );
      expect(sent, 0);
      expect(
        DmOutbox.entries.value.single.attempts,
        DmOutbox.maxAttempts,
        reason: 'no further attempts once the budget is spent',
      );
    });
  });

  group('OEM kill detector', () {
    test('suggests only for a recent kill with messages still pending', () {
      expect(
        OemKillDetector.shouldSuggest(gapMs: 5 * 60 * 1000, pendingCount: 2),
        isTrue,
      );
    });

    test('never for an ordinary session the user ended hours ago', () {
      expect(
        OemKillDetector.shouldSuggest(
          gapMs: 6 * 60 * 60 * 1000,
          pendingCount: 2,
        ),
        isFalse,
      );
    });

    test('never when nothing was in flight', () {
      expect(
        OemKillDetector.shouldSuggest(gapMs: 5 * 60 * 1000, pendingCount: 0),
        isFalse,
      );
    });

    test('never for a too-fresh boot (still inside the kill window)', () {
      expect(
        OemKillDetector.shouldSuggest(
          gapMs: OemKillDetector.minGapMs - 1,
          pendingCount: 1,
        ),
        isFalse,
      );
    });

    test('boundary: exactly at the max gap is the last eligible frame', () {
      expect(
        OemKillDetector.shouldSuggest(
          gapMs: OemKillDetector.maxGapMs,
          pendingCount: 1,
        ),
        isTrue,
      );
      expect(
        OemKillDetector.shouldSuggest(
          gapMs: OemKillDetector.maxGapMs + 1,
          pendingCount: 1,
        ),
        isFalse,
      );
    });

    test('the guide is offered once, never nagged again', () async {
      SharedPreferences.setMockInitialValues({
        OemKillDetector.kLastAliveKey:
            DateTime.now().millisecondsSinceEpoch - 5 * 60 * 1000,
      });
      await OemKillDetector.resetShown();

      expect(await OemKillDetector.considerBoot(pendingCount: 1), isTrue);
      expect(
        await OemKillDetector.considerBoot(pendingCount: 1),
        isFalse,
        reason: 'the latch must hold for the rest of this install',
      );
    });

    test('no recorded liveness means no claim', () async {
      SharedPreferences.setMockInitialValues({});
      await OemKillDetector.resetShown();
      expect(await OemKillDetector.considerBoot(pendingCount: 5), isFalse);
    });
  });
}
