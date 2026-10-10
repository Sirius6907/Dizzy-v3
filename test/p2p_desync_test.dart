import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/addon/addon_manager.dart';
import 'package:dizzy/services/p2p/p2p_settings_service.dart';

/// Regression test for the P2P desync bug (2026-10-10):
/// the Settings switch wrote only `dizzy_p2p_source_enabled` while the
/// engine read the builtin addon entry (`isDizzyActive`), so "P2P enabled"
/// could show ON while torrent scrapers never registered (and vice versa).
/// Single source of truth = the builtin addon entry; everything routes
/// through AddonManager.toggleAddon.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Fresh manager state per test (singleton in production).
    AddonManager.instance.resetForTest();
    await P2pSettingsService.initialize();
    await AddonManager.instance.initialize();
  });

  group('P2P single source of truth', () {
    test('fresh install: switch and engine agree (both ON)', () {
      expect(P2pSettingsService.isP2pEnabled.value, isTrue);
      expect(AddonManager.instance.isDizzyActive, isTrue);
    });

    test('toggle OFF via addon: switch mirrors engine', () async {
      await AddonManager.instance.toggleAddon('builtin.dizzy', false);
      expect(AddonManager.instance.isDizzyActive, isFalse);
      expect(P2pSettingsService.isP2pEnabled.value, isFalse);
    });

    test('toggle ON via addon: switch mirrors engine', () async {
      await AddonManager.instance.toggleAddon('builtin.dizzy', false);
      await AddonManager.instance.toggleAddon('builtin.dizzy', true);
      expect(AddonManager.instance.isDizzyActive, isTrue);
      expect(P2pSettingsService.isP2pEnabled.value, isTrue);
    });

    test('feature-flag path (streams) stays in lockstep', () async {
      await AddonManager.instance.updateAddonFeature(
        addonId: 'builtin.dizzy',
        enableStreams: false,
      );
      expect(AddonManager.instance.isDizzyActive, isFalse);
      expect(P2pSettingsService.isP2pEnabled.value, isFalse);
    });

    test('stale persisted choice wins once on startup', () async {
      // Simulate an old build that wrote the switch without the addon.
      await P2pSettingsService.setP2pEnabled(false);
      AddonManager.instance.resetForTest();
      await AddonManager.instance.initialize();
      expect(AddonManager.instance.isDizzyActive, isFalse);
      expect(P2pSettingsService.isP2pEnabled.value, isFalse);
    });
  });
}
