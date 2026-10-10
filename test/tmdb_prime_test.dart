import 'package:dizzy/services/scraper/sites/tmdb_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// ID-first regression (user's design): the catalogue/meta layer already
/// carries the VERIFIED tmdb id (Cinemeta `moviedb_id`). DetailsPage +
/// WatchScreen prime it via [TmdbHelper.primeTmdbId] so scrapers resolve by
/// id and never title-search for known content. Title gates stay as the
/// last-resort path only.
void main() {
  group('TmdbHelper.primeTmdbId — ID-first (no title search)', () {
    test('primed id resolves without any network', () async {
      TmdbHelper.primeTmdbId(
        imdbId: 'tt1375666',
        tmdbId: 27205,
        title: 'Inception',
        type: 'movie',
        year: 2010,
      );
      expect(
        await TmdbHelper.resolveTmdbId(
          imdbId: 'tt1375666',
          title: 'Inception',
          type: 'movie',
          year: 2010,
        ),
        27205,
      );
    });

    test('prime key normalizes type spelling (series vs tv)', () async {
      TmdbHelper.primeTmdbId(
        imdbId: 'tt0903747',
        tmdbId: 1396,
        title: 'Breaking Bad',
        type: 'series',
        year: 2008,
      );
      // WatchScreen passes widget.type which may be 'tv'.
      expect(
        await TmdbHelper.resolveTmdbId(
          imdbId: 'tt0903747',
          title: 'Breaking Bad',
          type: 'tv',
          year: 2008,
        ),
        1396,
      );
    });

    test('prime key normalizes episode-suffixed ids (tt123:1:2)', () async {
      TmdbHelper.primeTmdbId(
        imdbId: 'tt0903747',
        tmdbId: 1396,
        title: 'Breaking Bad',
        type: 'series',
        year: 2008,
      );
      expect(
        await TmdbHelper.resolveTmdbId(
          imdbId: 'tt0903747:1:2',
          title: 'Breaking Bad',
          type: 'series',
          year: 2008,
        ),
        1396,
      );
    });

    test('unprimed unknown title still resolves null offline (fail-soft)',
        () async {
      expect(
        await TmdbHelper.resolveTmdbId(
          title: 'Some ObSkUr3 Title 9zq',
          type: 'movie',
        ),
        isNull,
      );
    });
  });
}
