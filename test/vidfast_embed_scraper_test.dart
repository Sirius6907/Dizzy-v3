import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/scraper/sites/vidfast.dart';

void main() {
  test('yields one embed source from the resolved TMDB id', () async {
    final scraper = VidFastScraper(
      resolveTmdbId:
          ({String? imdbId, required String title, required String type, int? year}) async =>
              550,
    );

    final out = await scraper.scrape(
      type: 'movie',
      title: 'Fight Club',
      year: 1999,
      imdbId: 'tt0137523',
    );

    expect(out, hasLength(1));
    expect(out.single.externalUrl, 'https://vidfast.vc/movie/550?autoPlay=true');
    expect(out.single.behaviorHints?['dizzyEmbed'], isTrue);
    expect(out.single.url, isNull);
    expect(out.single.addonName, 'vidfast');
    expect(out.single.name, 'VidFast');
  });

  test('tv embed carries season and episode', () async {
    final scraper = VidFastScraper(
      resolveTmdbId:
          ({String? imdbId, required String title, required String type, int? year}) async {
            expect(type, 'tv');
            return 1399;
          },
    );

    final out = await scraper.scrape(
      type: 'series',
      title: 'Game of Thrones',
      imdbId: 'tt0944947',
      season: 1,
      episode: 3,
    );

    expect(
      out.single.externalUrl,
      contains('/tv/1399/1/3?autoPlay=true'),
    );
  });

  test('falls back to the IMDb id when TMDB resolution fails', () async {
    final scraper = VidFastScraper(
      resolveTmdbId:
          ({String? imdbId, required String title, required String type, int? year}) async =>
              null,
    );

    final out = await scraper.scrape(
      type: 'movie',
      title: 'Fight Club',
      imdbId: 'tt0137523',
    );

    expect(out.single.externalUrl, contains('/movie/tt0137523?autoPlay=true'));
  });

  test('a throwing resolver still yields the IMDb embedding', () async {
    final scraper = VidFastScraper(
      resolveTmdbId:
          ({String? imdbId, required String title, required String type, int? year}) async =>
              throw StateError('offline'),
    );

    final out = await scraper.scrape(
      type: 'movie',
      title: 'Fight Club',
      imdbId: 'tt0137523',
    );

    expect(out, hasLength(1));
  });

  test('no id at all yields nothing', () async {
    final scraper = VidFastScraper(
      resolveTmdbId:
          ({String? imdbId, required String title, required String type, int? year}) async =>
              null,
    );

    final out = await scraper.scrape(type: 'movie', title: 'Unknown Title');
    expect(out, isEmpty);
  });
}
