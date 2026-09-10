import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_client.dart';

/// v1.2.0-ADMIN: remote config pulled from Supabase `remote_config` table.
///
/// Keys (server-seeded, dashboard-editable):
///   min_app_version        e.g. "1.2.0" — below => force-update banner
///   scraper_kill           JSON map {"vidfast": "reason"} — app skips these
///   scraper_cooldown_days  e.g. "7"
///   features               JSON map {"watch_party": true, "voice": true}
///   notice                 JSON map {"text": "...", "until": "2026-10-01"}
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
      final rows = await CloudClient.db
          .from('remote_config')
          .select('key,value')
          .limit(50);
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
      debugPrint('[RemoteConfig] refresh failed (soft): $e');
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
