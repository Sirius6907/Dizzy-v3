import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/env_service.dart';
import '../../cloud/cloud_client.dart';
import '../../errors/app_error_log.dart';

/// P14 — keyless-first TMDB chain:
///
///   1. OWN edge proxy (`tmdb-proxy` fn) — no key on device at all.
///   2. Official API with `--dart-define=TMDB_API_KEY` (CI/release opt-in).
///   3. Official API with runtime `.env` [EnvService] key (desktop dev).
///   4. Third-party keyless proxy — cloud-off survival only, never first.
///
/// No key anywhere → official calls skipped, proxy serves all; proxy also
/// down → null (guest auto-open falls back to title search).
/// NEVER hardcode a key here (was leaked in git history pre-v1.1.9).
/// APK key check: release builds inject no dart-define + ship no .env, so
/// [hasKey] is false and only the keyless proxy path can fire.
class TmdbHelper {
  static const _compileKey =
      String.fromEnvironment('TMDB_API_KEY', defaultValue: '');
  static String get _apiKey =>
      _compileKey.isNotEmpty ? _compileKey : EnvService.get('TMDB_API_KEY');
  static bool get hasKey => _apiKey.isNotEmpty;
  static const _tmdbDirect = 'https://api.themoviedb.org/3';

  /// Last-resort keyless proxy (third-party): only reached when OUR edge is
  /// unconfigured AND no key exists (cloud-off devices, CI). Never first.
  static const _speedrace = 'https://db.speedracelight.com/3';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  static final Map<String, int> _cache = {};

  static String _cleanString(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Pure: ordered strategies for this device. Edge is ALWAYS first;
  /// direct entries exist only when a key exists; keyless third-party
  /// fallback is ALWAYS last (cloud-off survival, never preferred).
  /// Unit-tested (chain order is the P14 success metric).
  static List<String> resolveChain(
      {required bool edgeReady, required bool key}) {
    final chain = <String>[];
    if (edgeReady) chain.add('edge');
    if (key) chain.add('direct');
    chain.add('keyless');
    return chain;
  }

  static bool get _edgeReady =>
      CloudClient.isReady && CloudClient.functionUrl('tmdb-proxy').isNotEmpty;

  /// GET the edge proxy: `?path=/movie/550&...` (allowlisted server-side).
  static Future<Map<String, dynamic>?> _edgeGet(
      String path, Map<String, String> query) async {
    final base = CloudClient.functionUrl('tmdb-proxy');
    if (base.isEmpty) return null;
    try {
      final uri = Uri.parse(base).replace(queryParameters: {
        'path': path,
        ...query,
      });
      final res = await http.get(uri, headers: {
        ..._headers,
        'apikey': CloudClient.anonKey,
      }).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>?;
    } catch (_) {
      // P15: silent-but-logged network (throttled 24h/code server-side).
      unawaited(AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb', detail: 'edge'));
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _directGet(Uri uri,
      {int seconds = 7}) async {
    try {
      final res = await http
          .get(uri, headers: _headers)
          .timeout(Duration(seconds: seconds));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>?;
    } catch (_) {
      unawaited(AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb', detail: 'direct'));
      return null;
    }
  }

  /// v1.2.0-P3: tmdb id → imdb id (guest auto-open needs it for Cinemeta).
  /// Edge detail carries `imdb_id`; official external_ids is the backup.
  static Future<String?> fetchImdbId({
    required String endpoint, // 'movie' or 'tv'
    required int tmdbId,
  }) async {
    String? pick(Map<String, dynamic>? data) {
      final imdb = data?['imdb_id']?.toString();
      return (imdb != null && imdb.startsWith('tt')) ? imdb : null;
    }

    if (_edgeReady) {
      final got = pick(await _edgeGet('/$endpoint/$tmdbId', {}));
      if (got != null) return got;
    }
    if (hasKey) {
      final got = pick(await _directGet(Uri.parse(
          '$_tmdbDirect/$endpoint/$tmdbId/external_ids?api_key=$_apiKey'),
          seconds: 6));
      if (got != null) return got;
    }
    // Last resort: third-party keyless proxy (cloud-off devices).
    final got = pick(await _directGet(
        Uri.parse('$_speedrace/$endpoint/$tmdbId/external_ids'),
        seconds: 6));
    return got;
  }

  static Future<int?> resolveTmdbId({
    String? imdbId,
    required String title,
    required String type,
    int? year,
  }) async {
    final cacheKey = '${imdbId ?? ""}|$title|$type|${year ?? ""}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    String cleanId = (imdbId ?? '').trim();
    cleanId = cleanId.replaceAll(RegExp(r'^(tmdb|movie|tv|imdb):', caseSensitive: false), '');
    if (cleanId.contains(':')) {
      cleanId = cleanId.split(':')[0];
    }

    final isTv = (type == 'tv' || type == 'series');
    final endpoint = isTv ? 'tv' : 'movie';
    final edge = _edgeReady;

    List<int>? idsFromFind(Map<String, dynamic>? data) {
      final results =
          isTv ? (data?['tv_results'] as List?) : (data?['movie_results'] as List?);
      if (results == null || results.isEmpty) return null;
      return [for (final r in results) (r as Map)['id'] as int?]
          .whereType<int>()
          .toList();
    }

    int? pickTitle(List? results) {
      if (results == null || results.isEmpty) return null;
      final targetCleanTitle = _cleanString(title);
      int? bestMatchId;
      for (final item in results) {
        final m = item as Map;
        final itemTitle = (m['title'] ??
                m['name'] ??
                m['original_title'] ??
                m['original_name'] ??
                '')
            .toString();
        final itemCleanTitle = _cleanString(itemTitle);
        final dateStr =
            (m['release_date'] ?? m['first_air_date'] ?? '').toString();
        final itemYear = dateStr.length >= 4
            ? int.tryParse(dateStr.substring(0, 4))
            : null;
        final titleMatch = itemCleanTitle == targetCleanTitle ||
            itemCleanTitle.contains(targetCleanTitle) ||
            targetCleanTitle.contains(itemCleanTitle);
        if (!titleMatch) continue;
        if (year != null && itemYear != null) {
          if (itemYear == year || (itemYear - year).abs() <= 1) {
            final id = m['id'] as int?;
            if (id != null) {
              _cache[cacheKey] = id;
              return id;
            }
          }
        } else {
          bestMatchId ??= m['id'] as int?;
        }
      }
      if (bestMatchId != null) {
        _cache[cacheKey] = bestMatchId;
        return bestMatchId;
      }
      final fallbackId = (results.first as Map)['id'] as int?;
      if (fallbackId != null) {
        _cache[cacheKey] = fallbackId;
        return fallbackId;
      }
      return null;
    }

    if (cleanId.isNotEmpty) {
      // 1. Direct numeric ID
      if (RegExp(r'^\d+$').hasMatch(cleanId)) {
        final id = int.parse(cleanId);
        _cache[cacheKey] = id;
        return id;
      }

      // 2. Find API for tt IMDB IDs — edge, keyed direct, keyless last.
      if (cleanId.startsWith('tt')) {
        if (edge) {
          final ids = idsFromFind(await _edgeGet(
              '/find/$cleanId', {'external_source': 'imdb_id'}));
          if (ids != null && ids.isNotEmpty) {
            _cache[cacheKey] = ids.first;
            return ids.first;
          }
        }
        if (hasKey) {
          final ids = idsFromFind(await _directGet(Uri.parse(
              '$_tmdbDirect/find/$cleanId?api_key=$_apiKey&external_source=imdb_id')));
          if (ids != null && ids.isNotEmpty) {
            _cache[cacheKey] = ids.first;
            return ids.first;
          }
        }
        final ids = idsFromFind(await _directGet(Uri.parse(
            '$_speedrace/find/$cleanId?external_source=imdb_id'),
            seconds: 6));
        if (ids != null && ids.isNotEmpty) {
          _cache[cacheKey] = ids.first;
          return ids.first;
        }
      }
    }

    // 3. Search by title — edge, keyed direct, keyless last.
    if (title.isNotEmpty) {
      if (edge) {
        final data = await _edgeGet(
            '/search/$endpoint', {'query': title});
        final hit = pickTitle(data?['results'] as List?);
        if (hit != null) return hit;
      }
      if (hasKey) {
        final data = await _directGet(Uri.parse(
            '$_tmdbDirect/search/$endpoint?api_key=$_apiKey&query=${Uri.encodeComponent(title)}'));
        final hit = pickTitle(data?['results'] as List?);
        if (hit != null) return hit;
      }
      final data = await _directGet(Uri.parse(
          '$_speedrace/search/$endpoint?query=${Uri.encodeComponent(title)}'),
          seconds: 6);
      final hit = pickTitle(data?['results'] as List?);
      if (hit != null) return hit;
    }

    return null;
  }
}
