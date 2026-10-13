import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_client.dart';
import '../errors/app_log.dart';
import '../updater/update_policy.dart';

/// v1.2.0-ADMIN: remote config pulled from Supabase `remote_config` table.
///
/// Keys (server-seeded, dashboard-editable):
///   min_app_version        e.g. "1.2.0" — below => force-update banner
///   scraper_kill           JSON map {"vidfast": "reason"} — app skips these
///   scraper_cooldown_days  e.g. "7"
///   features               JSON map {"watch_party": true, "voice": true}
///   notice                 JSON map {"text": "...", "until": "2026-10-01"}
///
/// v1.3.3-T5 typed keys (hot-fix channel — values only, never code):
///   scraper_urls.* / scraper_regex.* / ranking_weights.* / feature_flags.*
///   music_endpoints.* (JSON: endpoint map) / music_shelves_layout (JSON)
///   support_faq_bundle_version / min_supported_build / announcements_feed
///
/// Fail-closed: a missing/unparseable key keeps the last-known value,
/// never grants. Fetches run at boot + every 6h heartbeat pull.
///
/// Cached 1h client-side. Everything fails soft — offline keeps last cache.
class RemoteConfigService {
  static const _cacheKey = 'remote_config_v1';
  static const _cacheAtKey = 'remote_config_at_v1';
  static const _cacheTtl = Duration(hours: 1);

  static Map<String, String> _cfg = {};
  static bool _loaded = false;

  /// Bumped on every successful refresh so UI can listen.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String get minAppVersion => _cfg['min_app_version'] ?? '';

  /// Phase E1: ISO deadline after which min_app_version becomes blocking.
  /// Phase L2: fleet heartbeat cadence in seconds. Clamped so a typo'd
  /// config can neither spam the server (60 = server floor) nor freeze
  /// presence (3600 = staleness ceiling); missing key = 5 minutes.
  static int get heartbeatIntervalSeconds {
    final raw = int.tryParse(_cfg['heartbeat_interval_s'] ?? '');
    if (raw == null || raw < 60) return 300;
    return raw > 3600 ? 3600 : raw;
  }

  static String get forceAfter => _cfg['force_after'] ?? '';

  /// Phase I1: staged-rollout percent (0..100). Missing key → 100 (offer to
  /// everyone) so a bad config can never hide updates.
  static int get rolloutPercent =>
      UpdatePolicy.parseRolloutPercent(_cfg[UpdatePolicy.keyRolloutPercent]);

  /// Phase I1: 'stable' (default) or 'beta'.
  static String get updateChannel =>
      UpdatePolicy.normalizeChannel(_cfg[UpdatePolicy.keyUpdateChannel]);

  static int get scraperCooldownDays =>
      int.tryParse(_cfg['scraper_cooldown_days'] ?? '') ?? 7;

  /// Scrapers the admin killed remotely. Matched lowercase.
  static Set<String> get killedScrapers {
    try {
      final raw = jsonDecode(_cfg['scraper_kill'] ?? '{}');
      if (raw is Map) {
        return raw.keys.map((k) => k.toString().trim().toLowerCase()).toSet();
      }
    } catch (_) {}
    return const {};
  }

  static bool isKilled(String scraperName) =>
      killedScrapers.contains(scraperName.trim().toLowerCase());

  static Map<String, dynamic> get features {
    try {
      final raw = jsonDecode(_cfg['features'] ?? '{}');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return const {};
  }

  static bool featureEnabled(String name, {bool fallback = true}) {
    final v = features[name];
    if (v is bool) return v;
    return fallback;
  }

  // ── v1.3.3-T5 typed hot-fix accessors (fail-closed) ──
  // Every getter falls back to the shipped default when the server key is
  // missing or unparseable: config can tweak behaviour, never grant it.

  /// v1.3.3-T5: dotted key read (e.g. scraper override values).
  static String typedValue(String key, {String fallback = ''}) {
    final v = _cfg[key];
    if (v == null || v.isEmpty) return fallback;
    return v;
  }

  /// v1.3.3-T5: namespaced map read (keys starting "ns."), e.g.
  /// scraper_urls.vidfast → {"vidfast": url}.
  static Map<String, String> typedNamespace(String ns) {
    final out = <String, String>{};
    final prefix = '$ns.';
    for (final e in _cfg.entries) {
      if (e.key.startsWith(prefix) && e.value.isNotEmpty) {
        out[e.key.substring(prefix.length)] = e.value;
      }
    }
    return out;
  }

  /// v1.3.3-T5: JSON map read with fail-closed fallback.
  static Map<String, dynamic> typedJson(String key) {
    try {
      final raw = jsonDecode(_cfg[key] ?? '{}');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return const {};
  }

  /// v1.3.3-T5: music shelves layout (server-driven order/visibility).
  /// Empty = app default layout.
  static Map<String, dynamic> get musicShelvesLayout => typedJson('music_shelves_layout');

  /// v1.3.3-T5: music endpoint overrides (Edge proxy URLs per source).
  static Map<String, String> get musicEndpoints => typedNamespace('music_endpoints');

  /// v1.3.3-T5: minimum supported build (below => force-update path).
  static String get minSupportedBuild => typedValue('min_supported_build');

  /// v1.3.3-T5: offline FAQ bundle version the app should carry.
  static String get faqBundleVersion => typedValue('support_faq_bundle_version');

  /// v1.3.3-T5: scoped snapshot for a single subsystem (music/scraper/etc).
  /// Keys outside the prefix never leak in.
  static Map<String, String> scopedSnapshot(String prefix) =>
      typedNamespace(prefix);

  /// Test-only: seed the in-memory map without touching prefs.
  static void debugSeed(Map<String, String> values) {
    _cfg = Map<String, String>.from(values);
    revision.value++;
  }

  static Map<String, dynamic> get notice {
    try {
      final raw = jsonDecode(_cfg['notice'] ?? '{}');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return const {};
  }

  /// Active global notice text, or empty when none / expired.
  static String get activeNotice {
    final n = notice;
    final text = (n['text'] ?? '').toString().trim();
    if (text.isEmpty) return '';
    final until = DateTime.tryParse((n['until'] ?? '').toString());
    if (until != null && DateTime.now().isAfter(until)) return '';
    return text;
  }

  static Future<void> initialize() async {
    if (_loaded) return;
    _loaded = true;
    await _loadCache();
    // ignore: unawaited_futures
    refresh();
  }

  static Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _cfg = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {}
  }

  static Future<void> refresh({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        final at = prefs.getInt(_cacheAtKey) ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - at < _cacheTtl.inMilliseconds &&
            _cfg.isNotEmpty) {
          return;
        }
      }
      if (!CloudClient.isReady) return;
      // v1.3.3-T5: typed keys grow the keyspace — 50 would truncate.
      final rows = await CloudClient.db
          .from('remote_config')
          .select('key,value')
          .limit(200);
      final next = <String, String>{};
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        next[(m['key'] ?? '').toString()] = (m['value'] ?? '').toString();
      }
      if (next.isEmpty) return;
      _cfg = next;
      await prefs.setString(_cacheKey, jsonEncode(next));
      await prefs.setInt(
          _cacheAtKey, DateTime.now().millisecondsSinceEpoch);
      revision.value++;
    } catch (e) {
      AppLog.d('[RemoteConfig] refresh failed (soft): $e');
    }
  }

  /// Pure helper for unit testing.
  static Set<String> parseKillMap(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is Map) {
        return raw.keys.map((k) => k.toString().trim().toLowerCase()).toSet();
      }
    } catch (_) {}
    return const {};
  }
}
