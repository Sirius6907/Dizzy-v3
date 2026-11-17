import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// TMDB id resolution seam. Production uses [TmdbHelper.resolveTmdbId];
/// tests inject a stub so the embed URL shape is verified without network.
typedef TmdbResolver = Future<int?> Function({
  String? imdbId,
  required String title,
  required String type,
  int? year,
});

/// VidFast — the site's OWN documented embed, played in-app.
///
/// The old scraper chased VidFast's internal `enc-dec.app` chain, and that
/// chain died: the site is now a Next.js RSC page behind a VF1 protection VM
/// and a TLS-fingerprint gate, so a Dart HTTP client gets a token-less page
/// (root-cause captures in `artifacts/audit-dsh/vidfast/`). Chasing it again
/// is explicitly out of scope.
///
/// Instead this yields exactly one EMBED source. The player opens the embed in
/// an ad-blocked webview (see `EmbedWebviewPlayer`) and hands the captured
/// m3u8 to mpv. The site accepts both TMDB and IMDb ids, so a failed TMDB
/// resolution degrades to the IMDb id instead of yielding nothing.
class VidFastScraper extends StreamScraper {
  VidFastScraper({TmdbResolver? resolveTmdbId})
    : _resolve = resolveTmdbId ?? TmdbHelper.resolveTmdbId;

  final TmdbResolver _resolve;

  static const domain = 'https://vidfast.vc';

  @override
  String get name => 'vidfast';

  /// The embed answers any id instantly, so this source is valid for titles
  /// that released today — the case slow archival scrapers miss.
  @override
  bool get indexesNewReleases => true;

  /// Pure: embed URL for a resolved id. Kept out of [scrape] so the shape is
  /// testable without a resolver.
  static String embedUrl({
    required String id,
    required bool isTv,
    int? season,
    int? episode,
  }) => isTv
      ? '$domain/tv/$id/${season ?? 1}/${episode ?? 1}?autoPlay=true'
      : '$domain/movie/$id?autoPlay=true';

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    final isTv = type == 'tv' || type == 'series';
    final imdb = (imdbId ?? '').trim();

    String? id;
    try {
      final tmdbId = await _resolve(
        imdbId: imdb.isEmpty ? null : imdb,
        title: title,
        type: isTv ? 'tv' : 'movie',
        year: year,
      );
      if (tmdbId != null) id = '$tmdbId';
    } catch (_) {
      // Resolution is best-effort; the IMDb id below is the safety net.
    }
    id ??= imdb.startsWith('tt') ? imdb : null;
    if (id == null || id.isEmpty) return const [];

    return [
      StreamSource(
        name: 'VidFast',
        addonName: name,
        title: 'VidFast · Embed',
        description: 'VidFast embed player',
        url: null,
        externalUrl: embedUrl(
          id: id,
          isTv: isTv,
          season: season,
          episode: episode,
        ),
        behaviorHints: const {'dizzyEmbed': true},
      ),
    ];
  }
}
