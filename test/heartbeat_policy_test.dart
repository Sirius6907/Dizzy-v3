import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/heartbeat/heartbeat_policy.dart';
import 'package:dizzy/services/heartbeat/heartbeat_service.dart';

/// Phase L2 — heartbeat cadence, throttling and the consent degradation.
void main() {
  group('interval clamp', () {
    test('missing or nonsense falls back to the 5 minute default', () {
      expect(HeartbeatPolicy.clampInterval(null), 300);
      expect(HeartbeatPolicy.clampInterval(0), 300);
      expect(HeartbeatPolicy.clampInterval(-9), 300);
      expect(HeartbeatPolicy.clampInterval(30), 300,
          reason: 'faster than the 60s server window is pointless');
    });

    test('reasonable values pass through, silly ones are capped', () {
      expect(HeartbeatPolicy.clampInterval(60), 60);
      expect(HeartbeatPolicy.clampInterval(300), 300);
      expect(HeartbeatPolicy.clampInterval(999999), 3600);
    });
  });

  group('jitter', () {
    test('stays inside ±10% of the cadence', () {
      for (var sample = -100000; sample <= 100000; sample += 7919) {
        final ms = HeartbeatPolicy.nextDelayMs(300, jitterSample: sample);
        expect(ms, greaterThanOrEqualTo(300000 - 30000));
        expect(ms, lessThanOrEqualTo(300000 + 30000));
      }
    });

    test('different samples really do produce different delays', () {
      final a = HeartbeatPolicy.nextDelayMs(300, jitterSample: 1);
      final b = HeartbeatPolicy.nextDelayMs(300, jitterSample: 2);
      expect(a, isNot(b),
          reason: 'a fleet must not beat in lockstep after one release');
    });

    test('never returns a non-positive delay (a zero would spin the timer)',
        () {
      for (var i = 0; i < 50; i++) {
        expect(
          HeartbeatPolicy.nextDelayMs(60, jitterSample: i * 31),
          greaterThan(0),
        );
      }
    });
  });

  group('when a beat is due', () {
    test('same activity is held back for the no-op window', () {
      expect(
        HeartbeatPolicy.beatDue(
          current: Activity.idle,
          lastSent: Activity.idle,
          lastSentMs: 100000,
          nowMs: 100000 + 1000,
        ),
        isFalse,
      );
      expect(
        HeartbeatPolicy.beatDue(
          current: Activity.idle,
          lastSent: Activity.idle,
          lastSentMs: 100000,
          nowMs: 100000 + HeartbeatPolicy.sameActivityCooldownMs,
        ),
        isTrue,
      );
    });

    test('a real activity change goes out almost immediately', () {
      expect(
        HeartbeatPolicy.beatDue(
          current: Activity.watching,
          lastSent: Activity.idle,
          lastSentMs: 100000,
          nowMs: 100005,
        ),
        isFalse,
        reason: 'still too fast — 5s floor stops button-mashing spam',
      );
      expect(
        HeartbeatPolicy.beatDue(
          current: Activity.watching,
          lastSent: Activity.idle,
          lastSentMs: 100000,
          nowMs: 100000 + HeartbeatPolicy.changedActivityCooldownMs,
        ),
        isTrue,
        reason: 'opened a video → the dashboard must see it now',
      );
    });

    test('force bypasses every cooldown', () {
      expect(
        HeartbeatPolicy.beatDue(
          current: Activity.idle,
          lastSent: Activity.idle,
          lastSentMs: 100000,
          nowMs: 100001,
          force: true,
        ),
        isTrue,
      );
    });
  });

  group('resume contract (Phase P)', () {
    test('resume forces a beat: due even 1ms after the last send', () {
      expect(
        HeartbeatPolicy.beatDue(
          current: Activity.idle,
          lastSent: Activity.idle,
          lastSentMs: 100000,
          nowMs: 100001,
          force: true,
        ),
        isTrue,
        reason: 'Active now must flip the moment the app opens',
      );
    });

    test('pause path never forces: an unforced same-activity beat is held back',
        () {
      expect(
        HeartbeatPolicy.beatDue(
          current: Activity.idle,
          lastSent: Activity.idle,
          lastSentMs: 100000,
          nowMs: 100001,
        ),
        isFalse,
        reason:
            'paused → no forced beat; an OS-killed app ageing out of the 10-min window is the correct semantics',
      );
    });
  });

  group('offline flush', () {
    test('only when pending, online and past the cooldown', () {
      expect(
        HeartbeatPolicy.shouldFlush(
          pending: true,
          online: true,
          lastSentMs: 0,
          nowMs: HeartbeatPolicy.sameActivityCooldownMs + 1,
        ),
        isTrue,
      );
      expect(
        HeartbeatPolicy.shouldFlush(
          pending: false,
          online: true,
          lastSentMs: 0,
          nowMs: 999999999,
        ),
        isFalse,
        reason: 'nothing pending → nothing to flush',
      );
      expect(
        HeartbeatPolicy.shouldFlush(
          pending: true,
          online: false,
          lastSentMs: 0,
          nowMs: 999999999,
        ),
        isFalse,
      );
      expect(
        HeartbeatPolicy.shouldFlush(
          pending: true,
          online: true,
          lastSentMs: 1000,
          nowMs: 2000,
        ),
        isFalse,
        reason: 'still inside the server window',
      );
    });
  });

  group('activity vocabulary', () {
    test('every key matches the server CHECK constraint exactly', () {
      const allowed = {
        'idle',
        'watching',
        'listening',
        'reading',
        'downloading',
        'in_room',
        'in_voice',
      };
      expect(
        Activity.values.map((a) => a.rpcKey).toSet(),
        allowed,
        reason: 'a key the DB rejects would silently drop the beat',
      );
    });

    test('unknown keys normalise instead of throwing', () {
      expect(Activity.fromKey('watching'), Activity.watching);
      expect(Activity.fromKey('something_new'), Activity.idle);
      expect(Activity.fromKey(null), Activity.idle);
      expect(Activity.fromKey(''), Activity.idle);
    });
  });

  group('reply parsing', () {
    test('only an explicit ok counts as success', () {
      expect(HeartbeatPolicy.replyOk({'ok': true}), isTrue);
      expect(HeartbeatPolicy.replyOk({'ok': false}), isFalse);
      expect(HeartbeatPolicy.replyOk({'ok': true, 'throttled': true}), isTrue);
      expect(HeartbeatPolicy.replyOk(null), isFalse);
      expect(HeartbeatPolicy.replyOk('ok'), isFalse);
      expect(HeartbeatPolicy.replyOk([1, 2]), isFalse);
    });
  });

  group('consent degradation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      HeartbeatService.instance.resetForTest();
    });

    tearDown(() {
      HeartbeatService.instance.resetForTest();
    });

    test('default is consent ON (the switch starts enabled)', () async {
      await HeartbeatService.instance.start();
      expect(HeartbeatService.instance.consent, isTrue);
      expect(HeartbeatService.instance.consentNotifier.value, isTrue);
    });

    test('stored OFF is honoured and no beat is ever produced', () async {
      SharedPreferences.setMockInitialValues({'heartbeat_consent': false});

      await HeartbeatService.instance.start();
      expect(HeartbeatService.instance.consent, isFalse);
      expect(HeartbeatService.instance.consentNotifier.value, isFalse);

      // Consent off → no beat, no offline backlog, no exception.
      await HeartbeatService.instance.beat(force: true);
      expect(HeartbeatService.instance.hasPendingBeat, isFalse);
      expect(HeartbeatService.instance.started, isTrue,
          reason: 'still "started" so the switch can be flipped back on');
    });

    test('turning consent OFF mid-session stops and forgets pending work',
        () async {
      await HeartbeatService.instance.start();
      expect(HeartbeatService.instance.consent, isTrue);

      await HeartbeatService.instance.setConsent(false);

      expect(HeartbeatService.instance.consent, isFalse);
      expect(HeartbeatService.instance.consentNotifier.value, isFalse);
      expect(HeartbeatService.instance.hasPendingBeat, isFalse);
      await HeartbeatService.instance.beat(force: true);
      expect(HeartbeatService.instance.hasPendingBeat, isFalse,
          reason: 'OFF means OFF — nothing waits to be sent later');
    });

    test('the consent choice survives a restart', () async {
      await HeartbeatService.instance.setConsent(false);

      HeartbeatService.instance.resetForTest();
      await HeartbeatService.instance.start();

      expect(HeartbeatService.instance.consent, isFalse);
    });
  });
}
