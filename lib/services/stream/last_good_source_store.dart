import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/stream/stream_model.dart';
import 'source_ranker.dart';

/// Persists the last source that played successfully (30s+ of playback)
/// for a title and, for series, per episode slot.
///
/// - Key: `imdb:tt123` (title) or `imdb:tt123:S2E7` (episode slot)
/// - Value: JSON {addonName, fingerprint, name}
/// - Bounded LRU: 200 entries max, oldest-accessed evicted first.
///
/// Used by:
/// - [SourceRanker] (history bonus for addons that worked before)
/// - One-tap Continue (probe last-good source first → <1.5s resume)
class LastGoodSourceStore {
  static const _prefsKey = 'last_good_sources_v1';
  static const _maxEntries = 200;

  /// Loads the full map. Safe on corrupt JSON (returns empty).
  static Future<Map<String, Map<String, String>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) {
        final inner = (v is Map) ? v : const {};
        return MapEntry(
          k.toString(),
          {
            'addonName': inner['addonName']?.toString() ?? '',
            'fingerprint': inner['fingerprint']?.toString() ?? '',
            'name': inner['name']?.toString() ?? '',
          },
        );
      });
    } catch (e) {
      debugPrint('[LastGoodSourceStore] load failed: $e');
      return {};
    }
  }

  /// Records a successful source for [titleKey] (and optional episode slot).
  /// Safe fire-and-forget; callers need not await.
  static Future<void> record({
    required String titleKey,
    String? episodeKey,
    required StreamSource source,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = await load();
      final entry = {
        'addonName': source.addonName,
        'fingerprint': SourceRanker.fingerprint(source),
        'name': source.name ?? source.title ?? '',
        't': DateTime.now().millisecondsSinceEpoch.toString(), // LRU clock
      };
      map[titleKey] = entry;
      if (episodeKey != null && episodeKey.isNotEmpty) map[episodeKey] = entry;

      // Evict oldest beyond cap.
      _evictBeyondCap(map);

      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (e) {
      debugPrint('[LastGoodSourceStore] record failed: $e');
    }
  }

  /// addonName → fingerprint map for the ranker (from both title + episode).
  static Future<Map<String, String>> addonHistoryFor({
    required String titleKey,
    String? episodeKey,
  }) async {
    final map = await load();
    final out = <String, String>{};
    for (final key in [titleKey, if (episodeKey != null) episodeKey]) {
      final e = map[key];
      if (e != null && e['addonName']?.isNotEmpty == true) {
        out[e['addonName']!] = e['fingerprint'] ?? '';
      }
    }
    return out;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  // ── helpers ─────────────────────────────────────────────────────────

  static void _evictBeyondCap(Map<String, Map<String, String>> map) {
    while (map.length > _maxEntries) {
      String? oldestKey;
      int? oldestT;
      for (final e in map.entries) {
        final t = int.tryParse(e.value['t'] ?? '') ?? 0;
        if (oldestT == null || t < oldestT) {
          oldestT = t;
          oldestKey = e.key;
        }
      }
      if (oldestKey == null) break;
      map.remove(oldestKey);
    }
  }
}
