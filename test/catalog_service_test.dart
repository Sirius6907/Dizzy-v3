import 'package:dizzy/services/catalog/catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// P22: warm-rows-first feeds — parse leniency + offline fail-soft.
/// (Live edge calls need Supabase + deploy; unit tests pin the guards.)
void main() {
  group('P22: catalog cards', () {
    test('good card parses; bad cards skipped, never throw', () {
      final good = CatalogCard.tryParse({
        'id': 550,
        'title': 'Fight Club',
        'poster': 'https://img/p.jpg',
        'year': '1999',
        'rating': 8.8,
        'media_type': 'movie',
      })!;
      expect(good.id, 550);
      expect(good.title, 'Fight Club');
      expect(good.rating, 8.8);

      expect(CatalogCard.tryParse({'id': 1}), isNull);
      expect(CatalogCard.tryParse({'title': 'No id'}), isNull);
      expect(CatalogCard.tryParse({'id': 'abc', 'title': 'x'}), isNull);
      expect(CatalogCard.tryParse({}), isNull);
    });

    test('offline + no snapshot → null (no spinner of death)', () async {
      // Test env: no Supabase URL, no snapshot seeded → null.
      expect(
        await CatalogService.fetchFeed(
          feed: 'trending-test-feed-xyz',
          type: 'all',
          page: 999,
        ),
        isNull,
      );
    });
  });

  group('tmdb→imdb lookup parse', () {
    test('extracts imdb_id from a well-formed edge response', () {
      expect(
        CatalogService.parseImdbLookup({
          'items': [
            {'id': 526848, 'imdb_id': 'tt27988879', 'title': 'Ramayana'},
          ],
        }),
        'tt27988879',
      );
    });

    test('missing/blank/invalid imdb_id → null, never throws', () {
      expect(
        CatalogService.parseImdbLookup({
          'items': [
            {'id': 1, 'imdb_id': ''},
          ],
        }),
        isNull,
      );
      expect(
        CatalogService.parseImdbLookup({
          'items': [
            {'id': 1},
          ],
        }),
        isNull,
      );
      expect(CatalogService.parseImdbLookup({'items': []}), isNull);
      expect(CatalogService.parseImdbLookup(null), isNull);
    });

    test('non-tt value is rejected (id safety)', () {
      expect(
        CatalogService.parseImdbLookup({
          'items': [
            {'id': 1, 'imdb_id': '526848'},
          ],
        }),
        isNull,
      );
    });
  });
}
