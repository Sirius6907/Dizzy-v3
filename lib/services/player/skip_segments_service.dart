import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/player/skip_segment_model.dart';
import '../scraper/sites/tmdb_helper.dart';
import '../errors/app_log.dart';

/// Service to fetch movie and TV intro/recap/credits/preview skip timestamps from IntroDB.
class SkipSegmentsService {
  static final SkipSegmentsService instance = SkipSegmentsService._internal();
  SkipSegmentsService._internal();

  static const String _baseUrl = 'https://api.theintrodb.org/v3/media';
  final Map<String, MediaSkipData> _cache = {};

  /// Fetches skip timestamps for a media item.
  Future<MediaSkipData?> fetchSkipSegments({
    String? tmdbId,
    String? imdbId,
    String? title,
    int? year,
    String? type,
    int? season,
    int? episode,
    int? durationMs,
  }) async {
    final mediaType = (type == 'series' || type == 'tv' || season != null) ? 'tv' : 'movie';
    final isTv = mediaType == 'tv';

    // 1. Resolve TMDB ID if missing
    int? numericTmdbId = int.tryParse(tmdbId ?? '');
    if (numericTmdbId == null && ((title != null && title.isNotEmpty) || (imdbId != null && imdbId.isNotEmpty))) {
      try {
        numericTmdbId = await TmdbHelper.resolveTmdbId(
          imdbId: imdbId,
          title: title ?? (imdbId ?? ''),
          type: mediaType,
          year: year,
        );
      } catch (e) {
        AppLog.d('[SkipSegmentsService] Failed to resolve TMDB ID: $e');
      }
    }

    final cacheKey = '${numericTmdbId ?? imdbId ?? title}:$mediaType:$season:$episode';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // 2. Build query parameters
    final params = <String, String>{};
    if (numericTmdbId != null && numericTmdbId > 0) {
      params['tmdb_id'] = numericTmdbId.toString();
    } else if (imdbId != null && imdbId.isNotEmpty) {
      params['imdb_id'] = imdbId;
    } else {
      AppLog.d('[SkipSegmentsService] No TMDB ID or IMDb ID available to query IntroDB');
      return null;
    }

    if (isTv && season != null && episode != null) {
      params['season'] = season.toString();
      params['episode'] = episode.toString();
    }

    if (durationMs != null && durationMs > 0) {
      params['duration_ms'] = durationMs.toString();
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
    AppLog.d('[SkipSegmentsService] Querying IntroDB: $uri');

    try {
      final res = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Dizzy/3.0.0 (VideoPlayer SkipEngine)',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic>) {
          final skipData = MediaSkipData.fromJson(data);
          _cache[cacheKey] = skipData;
          AppLog.d(
              '[SkipSegmentsService] Successfully loaded ${skipData.segments.length} skip segments (${skipData.segments.map((s) => s.type).join(", ")})');
          return skipData;
        }
      } else if (res.statusCode == 404) {
        AppLog.d('[SkipSegmentsService] No skip segments available for $uri (404)');
      } else {
        AppLog.d('[SkipSegmentsService] IntroDB returned status ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      AppLog.d('[SkipSegmentsService] Error fetching skip timestamps: $e');
    }

    // ── Heuristic fallback (Phase 4.1) ────────────────────────────────────
    // IntroDB miss/network-fail → conservatively synthesize an intro window.
    // Users can skip manually; never fabricate credits data.
    return _heuristicIntro(mediaType, season, episode, durationMs);
  }

  /// Conservative intro-window heuristic when no API data exists.
  /// Ep 1: 15–110s (cold open + title card). Later eps: 0–90s (recap/OP).
  /// TV without episode info: standard 60–90s. Movies: no guess (too risky).
  MediaSkipData? _heuristicIntro(
      String mediaType, int? season, int? episode, int? durationMs) {
    // Heuristic only for episodic content; skip movies entirely.
    if (mediaType != 'tv') return null;

    final int startMs;
    final int endMs;
    if (season != null || episode != null) {
      final ep = episode ?? 1;
      if (ep <= 1) {
        startMs = 15000;
        endMs = 110000;
      } else {
        startMs = 0;
        endMs = 90000;
      }
    } else {
      startMs = 60000;
      endMs = 90000;
    }

    AppLog.d('[SkipSegmentsService] Using heuristic intro window '
        '${startMs ~/ 1000}s–${endMs ~/ 1000}s');
    return MediaSkipData(segments: [
      MediaSkipSegment(type: 'intro', startMs: startMs, endMs: endMs),
    ]);
  }
}
