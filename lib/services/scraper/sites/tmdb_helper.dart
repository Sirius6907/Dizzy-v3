import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/env_service.dart';

class TmdbHelper {
  /// TMDB API key resolution order:
  ///   1. Compile-time `--dart-define=TMDB_API_KEY=...`
  ///      (CI: injected via --dart-define-from-file=.env from secrets.ENV_FILE)
  ///   2. Runtime `.env` via [EnvService] (desktop .env file / bundled asset)
  /// Empty key = official TMDB calls skipped, Speedrace proxy path used.
  /// NEVER hardcode the key here (was leaked in git history pre-v1.1.9).
  static const _compileKey = String.fromEnvironment('TMDB_API_KEY', defaultValue: '');
  static String get _apiKey =>
      _compileKey.isNotEmpty ? _compileKey : EnvService.get('TMDB_API_KEY');
  static bool get hasKey => _apiKey.isNotEmpty;
  static const _tmdbDirect = 'https://api.themoviedb.org/3';
  static const _tmdbProxy = 'https://db.speedracelight.com/3';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  static final Map<String, int> _cache = {};

  static String _cleanString(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// v1.2.0-P3: tmdb id → imdb id (guest auto-open needs it for Cinemeta).
  /// Proxy first (keyless), official API as backup. Null = unknown, fail-soft.
  static Future<String?> fetchImdbId({
    required String endpoint, // 'movie' or 'tv'
    required int tmdbId,
  }) async {
    final paths = <String>[
      '$_tmdbProxy/$endpoint/$tmdbId/external_ids',
    ];
    if (hasKey) {
      paths.add('$_tmdbDirect/$endpoint/$tmdbId/external_ids?api_key=$_apiKey');
    }
    for (final url in paths) {
      try {
        final res = await http
            .get(Uri.parse(url), headers: _headers)
            .timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        final imdb = data?['imdb_id']?.toString();
        if (imdb != null && imdb.startsWith('tt')) return imdb;
      } catch (_) {}
    }
    return null;
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

    if (cleanId.isNotEmpty) {
      // 1. Direct numeric ID
      if (RegExp(r'^\d+$').hasMatch(cleanId)) {
        final id = int.parse(cleanId);
        _cache[cacheKey] = id;
        return id;
      }

      // 2. Query TMDB Find API for tt IMDB IDs (skipped without API key)
      if (cleanId.startsWith('tt') && hasKey) {
        try {
          final uri = Uri.parse('$_tmdbDirect/find/$cleanId?api_key=$_apiKey&external_source=imdb_id');
          final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 7));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final results = isTv ? (data['tv_results'] as List?) : (data['movie_results'] as List?);
            if (results != null && results.isNotEmpty) {
              final id = results.first['id'] as int?;
              if (id != null) {
                _cache[cacheKey] = id;
                return id;
              }
            }
          }
        } catch (_) {}

        // Backup find query via Speedrace proxy
        try {
          final uri = Uri.parse('$_tmdbProxy/find/$cleanId?external_source=imdb_id');
          final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final results = isTv ? (data['tv_results'] as List?) : (data['movie_results'] as List?);
            if (results != null && results.isNotEmpty) {
              final id = results.first['id'] as int?;
              if (id != null) {
                _cache[cacheKey] = id;
                return id;
              }
            }
          }
        } catch (_) {}
      }
    }

    // 3. Search by title, type, and year matching
    if (title.isNotEmpty) {
      final targetCleanTitle = _cleanString(title);

      // Search via official TMDB API with user's key (skipped without API key)
      if (hasKey) {
      try {
        final uri = Uri.parse('$_tmdbDirect/search/$endpoint?api_key=$_apiKey&query=${Uri.encodeComponent(title)}');
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            int? bestMatchId;

            for (final item in results) {
              final itemTitle = (item['title'] ?? item['name'] ?? item['original_title'] ?? item['original_name'] ?? '').toString();
              final itemCleanTitle = _cleanString(itemTitle);
              final dateStr = (item['release_date'] ?? item['first_air_date'] ?? '').toString();
              final itemYear = dateStr.length >= 4 ? int.tryParse(dateStr.substring(0, 4)) : null;

              final titleMatch = itemCleanTitle == targetCleanTitle ||
                  itemCleanTitle.contains(targetCleanTitle) ||
                  targetCleanTitle.contains(itemCleanTitle);

              if (titleMatch) {
                if (year != null && itemYear != null) {
                  if (itemYear == year || (itemYear - year).abs() <= 1) {
                    final id = item['id'] as int?;
                    if (id != null) {
                      _cache[cacheKey] = id;
                      return id;
                    }
                  }
                } else {
                  bestMatchId ??= item['id'] as int?;
                }
              }
            }

            if (bestMatchId != null) {
              _cache[cacheKey] = bestMatchId;
              return bestMatchId;
            }

            // Fallback to first result if available
            final fallbackId = results.first['id'] as int?;
            if (fallbackId != null) {
              _cache[cacheKey] = fallbackId;
              return fallbackId;
            }
          }
        }
      } catch (_) {}
      } // end if (hasKey) — without key, fall through to proxy search below

      // Backup search via Speedrace Proxy
      try {
        final uri = Uri.parse('$_tmdbProxy/search/$endpoint?query=${Uri.encodeComponent(title)}');
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            for (final item in results) {
              final itemTitle = (item['title'] ?? item['name'] ?? item['original_title'] ?? item['original_name'] ?? '').toString();
              final itemCleanTitle = _cleanString(itemTitle);
              final dateStr = (item['release_date'] ?? item['first_air_date'] ?? '').toString();
              final itemYear = dateStr.length >= 4 ? int.tryParse(dateStr.substring(0, 4)) : null;

              if (itemCleanTitle == targetCleanTitle || itemCleanTitle.contains(targetCleanTitle)) {
                if (year == null || itemYear == null || itemYear == year || (itemYear - year).abs() <= 1) {
                  final id = item['id'] as int?;
                  if (id != null) {
                    _cache[cacheKey] = id;
                    return id;
                  }
                }
              }
            }

            final fallbackId = results.first['id'] as int?;
            if (fallbackId != null) {
              _cache[cacheKey] = fallbackId;
              return fallbackId;
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }
}
