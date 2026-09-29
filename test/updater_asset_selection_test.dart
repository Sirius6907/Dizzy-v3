import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/updater/app_updater_service.dart';

/// Asset-selection contract for the dual-signing update channels:
/// - normal channel -> release-key installs (v1.1.7+) fetch Dizzy-v3-*.apk
/// - legacy channel -> debug-key installs (v1.1.3/v1.1.4) fetch
///                     Dizzy-v3-legacy-*.apk so the update carries the SAME
///                     key and Android accepts it IN PLACE (no uninstall).
///
/// Legacy names deliberately drop the arch-vendor token (arm64-v8a, armeabi-v7a,
/// x86_64) — see the pre-1.4.0 picker tests at the bottom for why that matters.
void main() {
  final assets = [
    {
      'name': 'Dizzy-v3-arm64-v8a.apk',
      'browser_download_url': 'https://x/Dizzy-v3-arm64-v8a.apk',
      'digest': 'sha256:aaa',
    },
    {
      'name': 'Dizzy-v3-armeabi-v7a.apk',
      'browser_download_url': 'https://x/Dizzy-v3-armeabi-v7a.apk',
      'digest': 'sha256:bbb',
    },
    {
      'name': 'Dizzy-v3-x86_64.apk',
      'browser_download_url': 'https://x/Dizzy-v3-x86_64.apk',
      'digest': 'sha256:ccc',
    },
    {
      'name': 'Dizzy-v3-Universal.apk',
      'browser_download_url': 'https://x/Dizzy-v3-Universal.apk',
      'digest': 'sha256:ddd',
    },
    {
      'name': 'Dizzy-v3-legacy-arm64.apk',
      'browser_download_url': 'https://x/Dizzy-v3-legacy-arm64.apk',
      'digest': 'sha256:eee',
    },
    {
      'name': 'Dizzy-v3-legacy-armeabi.apk',
      'browser_download_url': 'https://x/Dizzy-v3-legacy-armeabi.apk',
      'digest': 'sha256:fff',
    },
    {
      'name': 'Dizzy-v3-legacy-x64.apk',
      'browser_download_url': 'https://x/Dizzy-v3-legacy-x64.apk',
      'digest': 'sha256:111',
    },
    {
      'name': 'Dizzy-v3-legacy-Universal.apk',
      'browser_download_url': 'https://x/Dizzy-v3-legacy-Universal.apk',
      'digest': 'sha256:222',
    },
    {
      'name': 'Dizzy-macOS-arm64.dmg',
      'browser_download_url': 'https://x/Dizzy-macOS-arm64.dmg',
    },
  ];
  const arm64Keywords = ['arm64-v8a', 'arm64_v8a', 'arm64', 'v8a', 'aarch64'];

  group('pickAndroidAsset', () {
    test('normal channel picks the release APK and never a legacy one', () {
      final picked = AppUpdaterService.pickAndroidAsset(
        assets,
        archKeywords: arm64Keywords,
        legacyChannel: false,
      );
      expect(picked?['name'], 'Dizzy-v3-arm64-v8a.apk');
    });

    test('legacy channel picks the legacy-signed APK for the same ABI', () {
      final picked = AppUpdaterService.pickAndroidAsset(
        assets,
        archKeywords: arm64Keywords,
        legacyChannel: true,
      );
      expect(picked?['name'], 'Dizzy-v3-legacy-arm64.apk');
    });

    test('legacy channel matches armeabi installs on their 3rd keyword', () {
      final picked = AppUpdaterService.pickAndroidAsset(
        assets,
        archKeywords: const ['armeabi-v7a', 'armeabi_v7a', 'armeabi', 'v7a'],
        legacyChannel: true,
      );
      expect(picked?['name'], 'Dizzy-v3-legacy-armeabi.apk');
    });

    test('legacy channel falls back to normal assets while none exist', () {
      final withoutLegacy = assets
          .where((a) => !(a['name'] as String).contains('legacy'))
          .toList();
      final picked = AppUpdaterService.pickAndroidAsset(
        withoutLegacy,
        archKeywords: arm64Keywords,
        legacyChannel: true,
      );
      expect(picked?['name'], 'Dizzy-v3-arm64-v8a.apk');
    });

    test('unknown ABI keyword falls back to universal (legacy excluded)', () {
      final picked = AppUpdaterService.pickAndroidAsset(
        assets,
        archKeywords: const ['some-unknown-abi'],
        legacyChannel: false,
      );
      expect(picked?['name'], 'Dizzy-v3-Universal.apk');
    });

    test('returns null when no APK assets exist', () {
      expect(
        AppUpdaterService.pickAndroidAsset(
          const [],
          archKeywords: arm64Keywords,
          legacyChannel: false,
        ),
        isNull,
      );
    });

    test('legacy channel falls back to universal when only legacy-universal exists', () {
      final legacyOnly = assets
          .where((a) => (a['name'] as String).contains('legacy'))
          .toList();
      final picked = AppUpdaterService.pickAndroidAsset(
        legacyOnly,
        archKeywords: const ['some-unknown-abi'],
        legacyChannel: true,
      );
      expect(picked?['name'], 'Dizzy-v3-legacy-Universal.apk');
    });
  });

  // ─── Pre-1.4.0 apps (v1.1.3–v1.3.0) ship the OLD picker: an unfiltered
  // keyword loop over every .apk asset. Those installs must keep landing on the
  // NORMAL (release-key) APK deterministically — otherwise a release-key phone
  // could be handed a legacy APK and the install would be rejected. Legacy
  // names therefore avoid keyword #1 of every ABI (arm64-v8a, armeabi-v7a,
  // x86_64) so the first matching file is always the normal one, regardless of
  // GitHub asset ordering.
  group('pre-1.4.0 picker determinism (regression guard)', () {
    String? oldPickerUrl(List<dynamic> list, List<String> archKeywords) {
      final apks = list
          .where((a) => ((a['name'] as String?) ?? '').toLowerCase().endsWith('.apk'))
          .toList();
      if (apks.isEmpty) return null;
      for (final keyword in archKeywords) {
        final match = apks
            .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
            .firstOrNull;
        if (match != null) return match['browser_download_url'] as String;
      }
      final universal = apks
          .where((a) => (a['name'] as String).toLowerCase().contains('universal'))
          .firstOrNull;
      return universal?['browser_download_url'] as String?;
    }

    const abiKeywords = {
      'arm64': ['arm64-v8a', 'arm64_v8a', 'arm64', 'v8a', 'aarch64'],
      'armeabi-v7a': ['armeabi-v7a', 'armeabi_v7a', 'armeabi', 'v7a', 'armv7'],
      'x86_64': ['x86_64', 'x86-64', 'x64'],
      'x86': ['x86', 'x86_32', 'ia32'],
      'unknown-defaults-to-arm64': ['arm64-v8a', 'arm64', 'v8a'],
    };

    for (final entry in abiKeywords.entries) {
      test('old app on ${entry.key} never receives a legacy APK', () {
        final url = oldPickerUrl(assets, entry.value);
        expect(url, isNotNull);
        expect(url, isNot(contains('legacy')));
        expect(url, contains('.apk'));
      });
    }

    test('still holds when legacy assets are listed FIRST (order-proof)', () {
      final legacyFirst = [
        for (final a in assets)
          if ((a['name'] as String).contains('legacy')) a,
        for (final a in assets)
          if (!(a['name'] as String).contains('legacy')) a,
      ];
      for (final entry in abiKeywords.entries) {
        final url = oldPickerUrl(legacyFirst, entry.value);
        expect(
          url,
          isNot(contains('legacy')),
          reason: 'legacy-first ordering must not leak legacy APKs to ${entry.key}',
        );
      }
    });
  });
}
