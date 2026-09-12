import 'package:shared_preferences/shared_preferences.dart';

/// v1.2.0-T2.6: skipable first-time guides (non-tech, Easy English).
/// One flag per feature: `guide_seen_<key>`. Skip/Finish sets it forever.
/// Settings → Help can call [resetAll] to show guides again.
class GuideService {
  static const _prefix = 'guide_seen_';

  static Future<bool> shouldShow(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool('$_prefix$key') ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix$key', true);
    } catch (_) {}
  }

  static Future<void> resetAll(List<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in keys) {
        await prefs.remove('$_prefix$k');
      }
    } catch (_) {}
  }

  /// All guide keys (for Settings → Help → Show guides again).
  static const allKeys = <String>[
    'party_v2',
    'downloads',
    'cloud_sync',
    'sources_health',
    'subtitles',
  ];

  /// P13 one-line migration: users who saw the old party guide don't get
  /// re-nagged by the new one. Old key left in prefs (harmless).
  static Future<void> migrateLegacyPartyKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getBool('${_prefix}watch_party') ?? false) &&
          !(prefs.getBool('${_prefix}party_v2') ?? false)) {
        await prefs.setBool('${_prefix}party_v2', true);
      }
    } catch (_) {}
  }
}
