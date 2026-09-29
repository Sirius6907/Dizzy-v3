import 'package:shared_preferences/shared_preferences.dart';

/// P7 — skipable first-time guides, Easy English only.
/// One flag per feature: `guide_seen_<key>`. Skip/Finish sets it forever.
/// Settings → Help → "Show guides again" calls [resetAll] to replay them.
///
/// P7 rules:
///  * every guide is at most [maxSteps] cards — short and skimmable;
///  * a retired key never re-nags its replacement (see [legacyAliases]);
///  * a key that fails to persist is treated as "already seen" so a broken
///    storage layer can never trap the user in an endless card loop.
class GuideService {
  GuideService._();

  static const String _prefix = 'guide_seen_';

  /// Longest intro a user is ever asked to sit through.
  static const int maxSteps = 3;

  /// The 30-second welcome tour. Lives here so "Show guides again" can
  /// replay it together with the feature cards.
  static const String onboardingKey = 'onboarding';

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

  /// New key → retired key(s) that already mean "this user has seen it".
  /// A user who dismissed the old card must never be shown the new one.
  static const Map<String, List<String>> legacyAliases = {
    'party_v2': ['watch_party'],
  };

  /// The very first welcome tour used its own pref key outside this scheme.
  static const String _legacyOnboardingPref = 'has_seen_superpower_onboarding_v1_2';

  /// Every guide key (for Settings → Help → "Show guides again").
  static const List<String> allKeys = <String>[
    'home',
    'spotlight',
    'movie',
    'anime',
    'manga',
    'music_studio',
    'eq',
    'books',
    'audiobooks',
    'downloads',
    'offline',
    'my_list',
    'profiles_pin',
    'debrid',
    'iptv',
    'calendar',
    'stats',
    'subtitles',
    'sources_health',
    'cloud_sync',
    'party_v2',
    'dms',
    'social_hub',
    'accent_studio',
    'appearance',
  ];

  /// P7 one-shot migration, run before the first `maybeShow` of the session.
  ///
  /// Copies every retired flag onto its replacement so upgrading never
  /// re-nags, and carries the v1 welcome-tour flag onto the v2 one.
  static Future<void> migrateLegacyKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (final entry in legacyAliases.entries) {
        final alreadySeen = prefs.getBool('$_prefix${entry.key}') ?? false;
        if (alreadySeen) continue;
        final retiredSeen =
            entry.value.any((old) => prefs.getBool('$_prefix$old') ?? false);
        if (retiredSeen) {
          await prefs.setBool('$_prefix${entry.key}', true);
        }
      }

      final tourSeen = prefs.getBool('$_prefix$onboardingKey') ?? false;
      final legacyTourSeen = prefs.getBool(_legacyOnboardingPref) ?? false;
      if (legacyTourSeen && !tourSeen) {
        await prefs.setBool('$_prefix$onboardingKey', true);
      }
    } catch (_) {}
  }

  /// P13 one-line migration kept for callers that only care about the party
  /// card. Runs the full pass so behaviour stays identical.
  static Future<void> migrateLegacyPartyKey() => migrateLegacyKeys();
}
