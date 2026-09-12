import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../errors/app_log.dart';

/// F0 (v1.1.9): Dead Scraper Quarantine.
///
/// Scrapers documented down in `docs/scraper-status-v1.1.9.md` are auto-skipped
/// so users don't wait on spinning dead endpoints. Every 7 days, each
/// quarantined scraper gets one retry attempt. If it succeeds, it unquarantines.
class ScraperQuarantineService {
  static const _key = 'scraper_quarantine_v1';
  static const _cooldown = Duration(days: 7);

  /// Baseline known-dead scrapers triaged in docs/scraper-status-v1.1.9.md.
  /// Matched against `scraper.name.toLowerCase()` — these MUST equal the
  /// unique per-site keys (v1.2.0-P1: no more shared 'DizzyHTTP' label).
  static const Set<String> _baselineDead = {
    'flaxmovies',
    'peestream',
    'vidfast',
    'vidgod',
    'vidup',
    'bcine',
  };

  /// User-visible brand per scraper key, for the Sources health dashboard
  /// (Settings → Sources). Keys not listed here fall back to Title Case.
  static const Map<String, String> displayNames = {
    'a111477': '111477',
    'bcine': 'BCine',
    'cinejoy': 'CineJoy',
    'cinesrc': 'CineSrc',
    'cinesu': 'CineSu',
    'downdaily': 'DownloadEverything',
    'dulo': 'Dulo',
    'flaxmovies': 'FlaxMovies',
    'flystream': 'FlyStream',
    'fourkhdhub': '4KHDHub',
    'frame': 'Frame',
    'fshare': 'FShareTV',
    'fsonic': 'FSonic',
    'fsonline': 'FSOnline',
    'hexa': 'Hexa',
    'hindmoviez': 'HindMoviez',
    'kisskh': 'KissKH',
    'knaben': 'Knaben',
    'lmscript': 'LMScript',
    'lookmovie': 'LookMovie',
    'mapple': 'Mapple',
    'megasource': 'MegaSource',
    'meowtv': 'MeowTV',
    'movienight': 'MovieNight',
    'movy': 'Movy',
    'multiembed': 'MultiEmbed',
    'nova': 'Nova',
    'peestream': 'PeeStream',
    'purstream': 'PurStream',
    'rivestream': 'RiveStream',
    'torrentgalaxy': 'TorrentGalaxy',
    'vadapav': 'Vadapav',
    'vidapi': 'VidAPI',
    'vidcore': 'VidCore',
    'videasy': 'Videasy',
    'vidfast': 'VidFast',
    'vidgod': 'VidGod',
    'vidlink': 'VidLink',
    'vidrock': 'VidRock',
    'vidsrc': 'VidSrc',
    'vidup': 'VidUp',
    'vidvault': 'VidVault',
    'vidzee': 'VidZee',
    'vixsrc': 'VixSrc',
    'vuflix': 'VuFlix',
    'xdownloader': 'XDownloader',
    'xpass': 'XPass',
    'zxcstream': 'ZxcStream',
  };

  /// Pretty label for a scraper key ('flystream' → 'FlyStream').
  static String displayNameFor(String scraperName) {
    final key = scraperName.trim().toLowerCase();
    final mapped = displayNames[key];
    if (mapped != null) return mapped;
    if (key.isEmpty) return 'Unknown';
    return key[0].toUpperCase() + key.substring(1);
  }

  static Map<String, DateTime> _quarantineMap = {};
  static bool _loaded = false;

  static Future<void> initialize() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _quarantineMap = decoded.map(
          (k, v) => MapEntry(k, DateTime.tryParse(v.toString()) ?? DateTime.now()),
        );
      }
    } catch (_) {}

    // Seed baseline dead if not already tracked.
    final now = DateTime.now();
    var changed = false;
    for (final name in _baselineDead) {
      if (!_quarantineMap.containsKey(name)) {
        _quarantineMap[name] = now;
        changed = true;
      }
    }
    if (changed) _persist();
  }

  /// Returns true if [scraperName] should be skipped on this scrape run.
  static bool isQuarantined(String scraperName) {
    final key = scraperName.trim().toLowerCase();
    final quarantinedAt = _quarantineMap[key];
    if (quarantinedAt == null) return false;

    // Has the 7-day cooldown elapsed? If so, allow retry.
    if (DateTime.now().difference(quarantinedAt) >= _cooldown) {
      return false;
    }
    return true;
  }

  /// Called when a scraper successfully returns sources — unquarantines it.
  static void markSuccess(String scraperName) {
    final key = scraperName.trim().toLowerCase();
    if (_quarantineMap.remove(key) != null) {
      _persist();
      AppLog.d('[Quarantine] $scraperName recovered! Unquarantined.');
    }
  }

  /// Called after persistent failures to reset the 7-day retry clock.
  static void markFailed(String scraperName) {
    final key = scraperName.trim().toLowerCase();
    _quarantineMap[key] = DateTime.now();
    _persist();
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _quarantineMap.map((k, v) => MapEntry(k, v.toIso8601String()));
      await prefs.setString(_key, jsonEncode(map));
    } catch (_) {}
  }

  /// Pure helper for unit testing.
  static bool shouldSkip({
    required String name,
    required Map<String, DateTime> map,
    required DateTime now,
    Duration cooldown = const Duration(days: 7),
  }) {
    final key = name.trim().toLowerCase();
    final at = map[key];
    if (at == null) return false;
    return now.difference(at) < cooldown;
  }
}
