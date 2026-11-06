import 'dart:convert';

import 'package:http/http.dart' as http;

/// One Kitsu search hit, reduced to the fields the matcher needs.
class KitsuCandidate {
  final int id;
  final String title;
  final int? year;
  final int? episodes;

  const KitsuCandidate({
    required this.id,
    required this.title,
    this.year,
    this.episodes,
  });
}

/// Maps an AniList anime to a Kitsu id, so Stremio addons (Torrentio,
/// AcuAnime) can answer `/stream/anime/kitsu:<id>:<episode>`.
class KitsuResolver {
  KitsuResolver._();
  static final KitsuResolver instance = KitsuResolver._();

  static const String _base = 'https://kitsu.io/api/edge/anime';

  final Map<int, String?> _cache = {};

  void resetForTest() => _cache.clear();

  Future<String?> kitsuIdFor({
    int? anilistId,
    required List<String> titles,
    int? year,
  }) async {
    final cacheKey = anilistId ?? -1;
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
    for (final title in titles) {
      final trimmed = title.trim();
      if (trimmed.isEmpty) continue;
      final id = await _search(trimmed, year);
      if (id != null) {
        _cache[cacheKey] = id;
        return id;
      }
    }
    _cache[cacheKey] = null;
    return null;
  }

  Future<String?> _search(String title, int? year) async {
    try {
      final uri = Uri.parse(_base).replace(
        queryParameters: {
          'filter[text]': title,
          'page[limit]': '5',
        },
      );
      final res = await http
          .get(uri, headers: {'Accept': 'application/vnd.api+json'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is! Map) return null;
      final data = json['data'];
      if (data is! List) return null;

      final candidates = <KitsuCandidate>[];
      for (final raw in data) {
        if (raw is! Map) continue;
        final attrs = raw['attributes'];
        if (attrs is! Map) continue;
        final id = int.tryParse(raw['id']?.toString() ?? '');
        if (id == null) continue;
        final titles = attrs['titles'];
        final canonical = attrs['canonicalTitle']?.toString() ??
            (titles is Map ? titles['en']?.toString() : null) ??
            '';
        final start = attrs['startDate']?.toString() ?? '';
        candidates.add(
          KitsuCandidate(
            id: id,
            title: canonical,
            year: int.tryParse(start.length >= 4 ? start.substring(0, 4) : ''),
            episodes: int.tryParse(attrs['episodeCount']?.toString() ?? ''),
          ),
        );
      }
      return pickCandidateId(candidates, title: title, year: year)?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Pure matcher: exact title beats token overlap; a conflicting year
  /// disqualifies; a multi-episode TV entry beats a special with the same
  /// name.
  static int? pickCandidateId(
    List<KitsuCandidate> candidates, {
    required String title,
    int? year,
  }) {
    final wanted = _tokens(title);
    if (wanted.isEmpty) return null;

    KitsuCandidate? best;
    var bestScore = 0;
    for (final c in candidates) {
      if (year != null && c.year != null && (c.year! - year).abs() > 2) {
        continue;
      }
      final have = _tokens(c.title);
      if (have.isEmpty) continue;

      final overlap = wanted.intersection(have).length;
      if (overlap == 0) continue;

      var score = overlap * 10;
      if (wanted.length == have.length && overlap == wanted.length) {
        score += 30;
      }
      if (year != null && c.year != null && c.year == year) score += 15;
      if ((c.episodes ?? 0) > 1) score += 10;

      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best?.id;
  }

  static Set<String> _tokens(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 1 && !_stop.contains(t))
      .toSet();

  static const Set<String> _stop = {'the', 'a', 'an', 'of', 'and', 'to'};
}
