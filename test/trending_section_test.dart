import 'package:dizzy/pages/home/home_page.dart';
import 'package:dizzy/services/catalog/catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Home "Trending Now" row — pure mapping contract.
void main() {
  group('Trending section', () {
    test('empty → null (row hidden, never an error)', () {
      expect(buildTrendingSection([]), isNull);
    });

    test('cards map to tmdb: ids Cinemeta can title-resolve', () {
      final section = buildTrendingSection([
        const CatalogCard(
          id: 550,
          title: 'Fight Club',
          year: '1999',
          rating: 8.8,
        ),
        const CatalogCard(
          id: 1396,
          title: 'Breaking Bad',
          year: '2008',
          rating: 9.5,
          mediaType: 'tv',
        ),
      ])!;
      expect(section.title, 'Trending Now');
      expect(section.movies, hasLength(2));

      final movie = section.movies[0];
      expect(movie.id, 'tmdb:550');
      expect(movie.name, 'Fight Club');
      expect(movie.type, 'movie');

      final show = section.movies[1];
      expect(show.id, 'tmdb:1396');
      expect(
        show.type,
        'series',
        reason: 'tv cards must resolve as series, not movie',
      );
    });
  });
}
