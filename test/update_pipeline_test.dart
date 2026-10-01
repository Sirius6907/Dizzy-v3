import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/updater/update_policy.dart';
import 'package:dizzy/services/updater/update_state_machine.dart';
import 'package:dizzy/services/updater/app_updater_service.dart';

/// Phase I4 — rollout bucket determinism, channel gating, staged-update
/// state machine, and the legacy signing-cert asset channel (which must
/// keep working: v1.1.3/v1.1.4 installs can only update in place).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdatePolicy bucket (I1)', () {
    test('deterministic — same stable hwid always same bucket', () {
      final a = UpdatePolicy.hashBucket('device-abc-123');
      final b = UpdatePolicy.hashBucket('device-abc-123');
      expect(a, b);
      expect(a, inInclusiveRange(0, 99));
    });

    test('different devices spread across buckets', () {
      final buckets = <int>{
        for (var i = 0; i < 200; i++) UpdatePolicy.hashBucket('hwid-$i'),
      };
      // A healthy hash should touch a wide band of the 0..99 space.
      expect(buckets.length, greaterThan(50));
    });

    test('rollout 0 blocks everyone, 100 admits everyone', () {
      for (var i = 0; i < 50; i++) {
        final id = 'hwid-$i';
        expect(
          UpdatePolicy.inRollout(stableHwid: id, rolloutPercent: 0),
          isFalse,
          reason: '$id must be held back at 0%',
        );
        expect(
          UpdatePolicy.inRollout(stableHwid: id, rolloutPercent: 100),
          isTrue,
        );
      }
    });

    test(
      'rollout 50 admits a strict subset (staged rollout actually stages)',
      () {
        final ids = [for (var i = 0; i < 300; i++) 'hwid-$i'];
        final admitted = ids
            .where(
              (id) =>
                  UpdatePolicy.inRollout(stableHwid: id, rolloutPercent: 50),
            )
            .length;
        expect(admitted, greaterThan(60));
        expect(admitted, lessThan(260));
      },
    );

    test('parseRolloutPercent fails safe to 100 (never hides updates)', () {
      expect(UpdatePolicy.parseRolloutPercent(null), 100);
      expect(UpdatePolicy.parseRolloutPercent('50'), 50);
      expect(UpdatePolicy.parseRolloutPercent(' 25 '), 25);
      expect(UpdatePolicy.parseRolloutPercent('not-a-number'), 100);
      expect(UpdatePolicy.parseRolloutPercent('150'), 100);
      expect(UpdatePolicy.parseRolloutPercent('-5'), 0);
      expect(UpdatePolicy.parseRolloutPercent(0), 0);
    });
  });

  group('UpdatePolicy channel (I1)', () {
    test('stable channel never sees a prerelease', () {
      expect(
        UpdatePolicy.channelAllows(channel: 'stable', isPrerelease: true),
        isFalse,
      );
      expect(
        UpdatePolicy.channelAllows(channel: 'stable', isPrerelease: false),
        isTrue,
      );
    });

    test('beta channel sees prereleases', () {
      expect(
        UpdatePolicy.channelAllows(channel: 'beta', isPrerelease: true),
        isTrue,
      );
    });

    test('unknown channel degrades to stable', () {
      expect(UpdatePolicy.normalizeChannel('nightly'), 'stable');
      expect(UpdatePolicy.normalizeChannel(null), 'stable');
      expect(UpdatePolicy.normalizeChannel('  BETA '), 'beta');
    });

    test('shouldOffer needs BOTH rollout and channel', () {
      const hwid = 'any-device';
      expect(
        UpdatePolicy.shouldOffer(
          stableHwid: hwid,
          rolloutPercent: 100,
          channel: 'stable',
          isPrerelease: false,
        ),
        isTrue,
      );
      expect(
        UpdatePolicy.shouldOffer(
          stableHwid: hwid,
          rolloutPercent: 0,
          channel: 'beta',
          isPrerelease: false,
        ),
        isFalse,
        reason: 'rollout gate alone must be able to hold it back',
      );
      expect(
        UpdatePolicy.shouldOffer(
          stableHwid: hwid,
          rolloutPercent: 100,
          channel: 'stable',
          isPrerelease: true,
        ),
        isFalse,
        reason: 'channel gate alone must be able to hold it back',
      );
    });
  });

  group('UpdateStateMachine (I3)', () {
    test('happy path: idle → downloading → ready → installing → done', () {
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.idle,
          UpdateRunState.downloading,
        ),
        isTrue,
      );
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.downloading,
          UpdateRunState.ready,
        ),
        isTrue,
      );
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.ready,
          UpdateRunState.installing,
        ),
        isTrue,
      );
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.installing,
          UpdateRunState.done,
        ),
        isTrue,
      );
    });

    test('illegal jumps are rejected', () {
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.downloading,
          UpdateRunState.installing,
        ),
        isFalse,
        reason: 'never install a file that has not finished downloading',
      );
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.idle,
          UpdateRunState.ready,
        ),
        isFalse,
        reason: 'nothing staged from idle',
      );
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.failed,
          UpdateRunState.ready,
        ),
        isFalse,
        reason: 'a failure must retry through a fresh download',
      );
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.done,
          UpdateRunState.downloading,
        ),
        isFalse,
        reason: 'done only resets to idle',
      );
    });

    test('failed can retry or reset', () {
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.failed,
          UpdateRunState.downloading,
        ),
        isTrue,
      );
      expect(
        UpdateStateMachine.canTransition(
          UpdateRunState.failed,
          UpdateRunState.idle,
        ),
        isTrue,
      );
    });

    test(
      'set() refuses an illegal transition and keeps the current state',
      () async {
        SharedPreferences.setMockInitialValues({});
        UpdateStateMachine.resetForTest();
        await UpdateStateMachine.set(
          UpdateRunState.downloading,
          version: '9.9.9',
        );
        expect(UpdateStateMachine.state.value, UpdateRunState.downloading);

        await UpdateStateMachine.set(
          UpdateRunState.installing,
          failReason: UpdateFailReason.installAbort,
        );
        // Blocked — still downloading, no failure reason recorded.
        expect(UpdateStateMachine.state.value, UpdateRunState.downloading);
        expect(UpdateStateMachine.reason, UpdateFailReason.none);

        UpdateStateMachine.resetForTest();
      },
    );

    test(
      'a persisted "downloading" survives as failed, not as a lie',
      () async {
        SharedPreferences.setMockInitialValues({
          UpdateStateMachine.kStateKey: 'downloading',
          UpdateStateMachine.kMetaKey: '{"version":"1.9.0","progress":0.4}',
        });
        UpdateStateMachine.resetForTest();

        await UpdateStateMachine.restore();

        expect(UpdateStateMachine.state.value, UpdateRunState.failed);
        expect(UpdateStateMachine.reason, UpdateFailReason.downloadFail);
        expect(UpdateStateMachine.targetVersion, '1.9.0');

        UpdateStateMachine.resetForTest();
      },
    );

    test(
      'a persisted "installing" restores as done (handed to system)',
      () async {
        SharedPreferences.setMockInitialValues({
          UpdateStateMachine.kStateKey: 'installing',
          UpdateStateMachine.kMetaKey: '{"version":"1.9.0","progress":1}',
        });
        UpdateStateMachine.resetForTest();

        await UpdateStateMachine.restore();

        expect(UpdateStateMachine.state.value, UpdateRunState.done);
        expect(UpdateStateMachine.reason, UpdateFailReason.none);

        UpdateStateMachine.resetForTest();
      },
    );

    test('a persisted "ready" is restored as ready', () async {
      SharedPreferences.setMockInitialValues({
        UpdateStateMachine.kStateKey: 'ready',
        UpdateStateMachine.kMetaKey: '{"version":"1.9.0","progress":1}',
      });
      UpdateStateMachine.resetForTest();

      await UpdateStateMachine.restore();

      expect(UpdateStateMachine.state.value, UpdateRunState.ready);
      expect(UpdateStateMachine.targetVersion, '1.9.0');

      UpdateStateMachine.resetForTest();
    });
  });

  group('legacy signing-cert channel (must stay intact)', () {
    final assets = [
      {
        'name': 'Dizzy-v1.2.0-arm64-v8a.apk',
        'browser_download_url': 'https://example.com/normal.apk',
      },
      {
        'name': 'Dizzy-v1.2.0-arm64-v8a-legacy.apk',
        'browser_download_url': 'https://example.com/legacy.apk',
      },
      {
        'name': 'Dizzy-v1.2.0-universal.apk',
        'browser_download_url': 'https://example.com/universal.apk',
      },
    ];

    test(
      'release-key install picks the normal asset (never the legacy one)',
      () {
        final picked = AppUpdaterService.pickAndroidAsset(
          assets,
          archKeywords: ['arm64'],
          legacyChannel: false,
        );
        expect(picked?['name'], 'Dizzy-v1.2.0-arm64-v8a.apk');
      },
    );

    test('legacy install keeps picking the legacy asset in place', () {
      final picked = AppUpdaterService.pickAndroidAsset(
        assets,
        archKeywords: ['arm64'],
        legacyChannel: true,
      );
      expect(picked?['name'], 'Dizzy-v1.2.0-arm64-v8a-legacy.apk');
    });

    test(
      'legacy install falls back gracefully when a release has no legacy asset',
      () {
        final withoutLegacy = [assets.first, assets.last];
        final picked = AppUpdaterService.pickAndroidAsset(
          withoutLegacy,
          archKeywords: ['arm64'],
          legacyChannel: true,
        );
        expect(picked?['name'], 'Dizzy-v1.2.0-arm64-v8a.apk');
      },
    );
  });
}
