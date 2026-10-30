import 'package:dizzy/pages/home/home_page.dart';
import 'package:dizzy/services/catalog/catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Home "For You" row — pure mapping contract.
void main() {
  group('For You section', () {
    test('empty → null (rail hides for cold-start users)', () {
      expect(buildForYouSection([]), isNull);
    });

    test('cards map to tmdb: ids and keep the reason in the subtitle', () {
      final section = buildForYouSection([
        const CatalogCard(
          id: 155,
          title: 'The Dark Knight',
          year: '2008',
          rating: 8.5,
          reason: 'genre:Action',
        ),
        const CatalogCard(
          id: 27205,
          title: 'Inception',
          year: '2010',
          rating: 8.4,
          reason: 'genre:Action',
        ),
      ])!;

      expect(section.title, 'For You');
      expect(section.subtitle, 'More Action for you');
      expect(section.movies, hasLength(2));
      expect(section.movies.first.id, 'tmdb:155');
    });

    test('non-genre reasons fall back to a neutral subtitle', () {
      final section = buildForYouSection([
        const CatalogCard(
          id: 1,
          title: 'Something',
          year: '2026',
          reason: 'lang:hi',
        ),
      ])!;
      expect(section.subtitle, 'Picked from what you watch');
    });
  });
}
