import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_client.dart';

/// P21 — Cloud resolve API client (`resolve` edge function).
///
/// The server holds the TMDB key; the app never sees it. Given a title
/// (+optional year/type/imdbId) the edge returns `{tmdbId, imdbId, year,
/// title}` with year-pinned matching — smarter than raw proxy passthrough,
/// so scrapers call this FIRST when cloud is ready.
///
/// Cost per fresh title: **2 reads, 1 write** —
///   read 1: local prefs cache (`resolve:<type>:<key>`, 30-day TTL),
///   read 2: the edge fetch itself,
///   write:   caching the answer back to prefs.
/// Everything fail-soft: null = "fall through to the next chain rung".
/// No addon changes — scrapers consume plain IDs.
class CloudResolveService {
  const CloudResolveService._();

  static const _ttlDays = 30;

  static String _cacheKey(
      {required String type, String? imdbId, required String title, String? year}) {
    final raw = '${imdbId ?? ''}|$title|${year ?? ''}'.toLowerCase().trim();
    return 'resolve:$type:${raw.hashCode}';
  }

  /// title/year/type/imdbId → `{tmdbId, imdbId, year, title}` or null.
  static Future<Map<String, dynamic>?> resolveIds({
    required String title,
    String? year,
    String type = 'movie',
    String? imdbId,
  }) async {
    final t = title.trim();
    final imdb = (imdbId ?? '').trim();
    if (t.isEmpty && imdb.isEmpty) return null;
    if (!CloudClient.isReady) return null;

    final key = _cacheKey(type: type, imdbId: imdb, title: t, year: year);
    try {
      // Read 1: local cache.
      final prefs = await SharedPreferences.getInstance();
      final hit = prefs.getString(key);
      if (hit != null) {
        final decoded = jsonDecode(hit) as Map<String, dynamic>?;
        final at = (decoded?['_at'] as int?) ?? 0;
        final ageDays =
            (DateTime.now().millisecondsSinceEpoch - at) ~/ 86400000;
        if (ageDays <= _ttlDays) return decoded;
      }

      // Read 2: the edge function (server key inside, app keyless).
      final base = CloudClient.functionUrl('resolve');
      if (base.isEmpty) return null;
      final uri = Uri.parse(base).replace(queryParameters: {
        if (t.isNotEmpty) 'title': t,
        if ((year ?? '').trim().isNotEmpty) 'year': year!.trim(),
        'type': type == 'tv' ? 'tv' : 'movie',
        if (imdb.isNotEmpty) 'imdbId': imdb,
      });
      final res = await http.get(uri, headers: {
        'apikey': CloudClient.anonKey,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      if (data == null || data['tmdbId'] == null) return null;

      // Write: cache for 30 days (titles don't change IDs).
      data['_at'] = DateTime.now().millisecondsSinceEpoch;
      // ignore: unawaited_futures
      prefs.setString(key, jsonEncode(data));
      return data;
    } catch (_) {
      return null;
    }
  }
}
