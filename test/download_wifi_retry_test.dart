import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/download/download_prefs.dart';
import 'package:dizzy/services/download/download_resume_policy.dart';
import 'package:dizzy/services/download/download_retry_ledger.dart';

/// Phase K2 — Wi-Fi-only gating, retry backoff, and the retry ledger.
/// (.part resume itself is covered by download_resume_test.dart.)
void main() {
  group('Wi-Fi-only gate', () {
    test('wifi is a green light', () {
      expect(
        DownloadResumePolicy.blockOn(
          wifiOnly: true,
          results: [ConnectivityResult.wifi],
        ),
        isFalse,
      );
      expect(
        DownloadResumePolicy.blockOn(
          wifiOnly: true,
          results: [ConnectivityResult.ethernet],
        ),
        isFalse,
      );
    });

    test('cellular is held back when the toggle is on', () {
      expect(
        DownloadResumePolicy.blockOn(
          wifiOnly: true,
          results: [ConnectivityResult.mobile],
        ),
        isTrue,
      );
    });

    test('the toggle off lets mobile data through', () {
      expect(
        DownloadResumePolicy.blockOn(
          wifiOnly: false,
          results: [ConnectivityResult.mobile],
        ),
        isFalse,
      );
    });

    test(
      'offline is never "blocked" — that path already pauses separately',
      () {
        expect(
          DownloadResumePolicy.blockOn(wifiOnly: true, results: []),
          isFalse,
        );
        expect(
          DownloadResumePolicy.blockOn(
            wifiOnly: true,
            results: [ConnectivityResult.none],
          ),
          isFalse,
        );
      },
    );

    test('wifi+cellular together counts as wifi', () {
      expect(
        DownloadResumePolicy.blockOn(
          wifiOnly: true,
          results: [ConnectivityResult.wifi, ConnectivityResult.mobile],
        ),
        isFalse,
      );
    });

    test('an unknown/other link type fails towards the data plan', () {
      expect(
        DownloadResumePolicy.blockOn(
          wifiOnly: true,
          results: [ConnectivityResult.bluetooth],
        ),
        isTrue,
      );
    });
  });

  group('retry backoff', () {
    test('grows and then caps', () {
      expect(DownloadResumePolicy.backoffMs(0), 10000);
      expect(
        DownloadResumePolicy.backoffMs(2),
        greaterThan(DownloadResumePolicy.backoffMs(1)),
      );
      expect(
        DownloadResumePolicy.backoffMs(50, jitterSample: 9999),
        lessThanOrEqualTo((DownloadResumePolicy.maxBackoffMs * 1.1).round()),
      );
      expect(
        DownloadResumePolicy.backoffMs(500000),
        greaterThan(0),
        reason: 'shift overflow must never go negative',
      );
    });

    test('exhausted after the attempt budget', () {
      expect(DownloadResumePolicy.isExhausted(0), isFalse);
      expect(
        DownloadResumePolicy.isExhausted(DownloadResumePolicy.maxAttempts - 1),
        isFalse,
      );
      expect(
        DownloadResumePolicy.isExhausted(DownloadResumePolicy.maxAttempts),
        isTrue,
      );
    });

    test('attemptDue respects the window', () {
      expect(
        DownloadResumePolicy.attemptDue(
          attempts: 1,
          lastAttemptMs: 0,
          nowMs: 1,
        ),
        isTrue,
        reason: 'never tried',
      );
      expect(
        DownloadResumePolicy.attemptDue(
          attempts: 1,
          lastAttemptMs: 100000,
          nowMs: 101000,
        ),
        isFalse,
      );
      expect(
        DownloadResumePolicy.attemptDue(
          attempts: 1,
          lastAttemptMs: 100000,
          nowMs: 100000 + DownloadResumePolicy.backoffMs(1) + 1,
        ),
        isTrue,
      );
      expect(
        DownloadResumePolicy.attemptDue(
          attempts: DownloadResumePolicy.maxAttempts,
          lastAttemptMs: 0,
          nowMs: 100000,
        ),
        isFalse,
      );
    });
  });

  group('retry on reconnect', () {
    test('a first reconnect retries a never-tried task immediately', () {
      expect(
        DownloadResumePolicy.retryOnReconnect(
          justCameBackOnline: true,
          hadConnectivity: true,
          attempts: 0,
          lastAttemptMs: 0,
          nowMs: 1000,
        ),
        isTrue,
      );
    });

    test('no retry if we never dropped in the first place', () {
      expect(
        DownloadResumePolicy.retryOnReconnect(
          justCameBackOnline: false,
          hadConnectivity: true,
          attempts: 0,
          lastAttemptMs: 0,
          nowMs: 1000,
        ),
        isFalse,
      );
      expect(
        DownloadResumePolicy.retryOnReconnect(
          justCameBackOnline: true,
          hadConnectivity: false,
          attempts: 0,
          lastAttemptMs: 0,
          nowMs: 1000,
        ),
        isFalse,
        reason: 'the initial connectivity probe is not a reconnect',
      );
    });

    test('a task that just failed must wait out its backoff', () {
      expect(
        DownloadResumePolicy.retryOnReconnect(
          justCameBackOnline: true,
          hadConnectivity: true,
          attempts: 1,
          lastAttemptMs: 1000000,
          nowMs: 1000100,
        ),
        isFalse,
      );
    });

    test('gives up after the budget', () {
      expect(
        DownloadResumePolicy.retryOnReconnect(
          justCameBackOnline: true,
          hadConnectivity: true,
          attempts: DownloadResumePolicy.maxAttempts,
          lastAttemptMs: 0,
          nowMs: 9999999,
        ),
        isFalse,
      );
    });
  });

  group('retry ledger', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DownloadRetryLedger.resetMemory();
    });

    test('counts attempts per task and forgets on clear', () async {
      await DownloadRetryLedger.recordFailure('t1', nowMs: 1000);
      await DownloadRetryLedger.recordFailure('t1', nowMs: 2000);
      await DownloadRetryLedger.recordFailure('t2', nowMs: 1500);

      expect(DownloadRetryLedger.attemptsFor('t1'), 2);
      expect(DownloadRetryLedger.attemptsFor('t2'), 1);
      expect(DownloadRetryLedger.lastAttemptFor('t1'), 2000);

      await DownloadRetryLedger.clear('t1');
      expect(DownloadRetryLedger.attemptsFor('t1'), 0);
      expect(DownloadRetryLedger.attemptsFor('t2'), 1);
    });

    test('survives a process restart', () async {
      await DownloadRetryLedger.recordFailure('t1', nowMs: 1000);
      DownloadRetryLedger.resetMemory();
      await DownloadRetryLedger.load();

      expect(DownloadRetryLedger.attemptsFor('t1'), 1);
      expect(DownloadRetryLedger.lastAttemptFor('t1'), 1000);
    });

    test('decode is fail-soft', () {
      expect(DownloadRetryLedger.decode(null), isEmpty);
      expect(DownloadRetryLedger.decode(''), isEmpty);
      expect(DownloadRetryLedger.decode('{{{'), isEmpty);
      expect(DownloadRetryLedger.decode('"scalar"'), isEmpty);
      expect(
        DownloadRetryLedger.decode('{"a": 5}'),
        isEmpty,
        reason: 'non-object values are dropped, not thrown on',
      );
      expect(
        DownloadRetryLedger.decode('{"a": {"x": 1}}'),
        isEmpty,
        reason: 'rows missing attempts/timestamp are dropped',
      );
    });

    test('eligible() returns ready tasks in a stable order', () async {
      await DownloadRetryLedger.recordFailure('zz', nowMs: 1000);
      await DownloadRetryLedger.recordFailure('aa', nowMs: 1000);
      await DownloadRetryLedger.recordFailure('mm', nowMs: 1000);

      final ids = DownloadRetryLedger.eligible(
        nowMs: 1000 + DownloadResumePolicy.backoffMs(1) + 5,
      );
      expect(ids, ['aa', 'mm', 'zz']);
    });

    test('exhausted tasks stay recorded but never come back', () async {
      for (var i = 0; i < DownloadResumePolicy.maxAttempts; i++) {
        await DownloadRetryLedger.recordFailure('t1', nowMs: 1000 + i);
      }
      expect(DownloadRetryLedger.exhaustedCount, 1);
      expect(
        DownloadRetryLedger.eligible(
          nowMs: 1000 + DownloadResumePolicy.maxBackoffMs * 10,
        ),
        isEmpty,
      );
      expect(
        DownloadRetryLedger.attemptsFor('t1'),
        DownloadResumePolicy.maxAttempts,
        reason: 'the history is kept so the UI can say it gave up',
      );
    });
  });

  group('DownloadPrefs', () {
    test('defaults to Wi-Fi only, and remembers a change', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DownloadPrefs.wifiOnly, isTrue);

      await DownloadPrefs.setWifiOnly(false);
      expect(await DownloadPrefs.wifiOnly, isFalse);

      await DownloadPrefs.setWifiOnly(true);
      expect(await DownloadPrefs.wifiOnly, isTrue);
    });
  });
}
