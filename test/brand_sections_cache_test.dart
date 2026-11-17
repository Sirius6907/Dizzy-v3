import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/models/addon/addon.dart';
import 'package:dizzy/models/movie/movie.dart';
import 'package:dizzy/models/movie/movie_section.dart';
import 'package:dizzy/services/addon/addon_manager.dart';
import 'package:dizzy/services/home/brand_sections_cache.dart';

MovieSection _section({
  String baseUrl = 'https://provider.example',
  String type = 'movie',
  String catalogId = 'nfx',
  int movieCount = 3,
}) {
  return MovieSection(
    title: 'Netflix',
    subtitle: 'Streaming Catalogs',
    contentType: type,
    addonBaseUrl: baseUrl,
    catalog: AddonCatalog(
      type: type,
      id: catalogId,
      genres: const ['Drama'],
      supportsSearch: false,
      supportsSkip: true,
    ),
    movies: List.generate(
      movieCount,
      (i) => Movie(
        id: 'tt${1000 + i}',
        name: 'Movie $i',
        poster: 'https://img.example/$i.jpg',
        year: '2024',
        type: type,
        addonBaseUrl: baseUrl,
        imdbRating: '7.$i',
      ),
    ),
  );
}

void main() {
  group('BrandSectionsCache section serialization', () {
    test('round-trips a section and re-stamps movies with the addon baseUrl',
        () {
      final s = _section();
      final restored = BrandSectionsCache.sectionFromJson(
        BrandSectionsCache.sectionToJson(s),
      );

      expect(restored, isNotNull);
      expect(restored!.title, 'Netflix');
      expect(restored.subtitle, 'Streaming Catalogs');
      expect(restored.contentType, 'movie');
      expect(restored.addonBaseUrl, 'https://provider.example');
      expect(restored.catalog.id, 'nfx');
      expect(restored.catalog.type, 'movie');
      expect(restored.catalog.genres, ['Drama']);
      expect(restored.catalog.supportsSkip, isTrue);
      expect(restored.movies.length, 3);
      // Movies must carry the section's addonBaseUrl — details navigation
      // reads it from the movie.
      for (final m in restored.movies) {
        expect(m.addonBaseUrl, 'https://provider.example');
      }
      expect(restored.movies.first.id, 'tt1000');
      expect(restored.movies.first.name, 'Movie 0');
      expect(restored.movies.first.imdbRating, '7.0');
    });

    test('trims movies to the per-section cap', () {
      final s = _section(movieCount: 50);
      final json = BrandSectionsCache.sectionToJson(s);
      expect((json['movies'] as List).length,
          BrandSectionsCache.maxMoviesPerSection);
    });

    test('returns null for a malformed entry instead of throwing', () {
      expect(
        BrandSectionsCache.sectionFromJson({
          'title': 'broken',
          'subtitle': 'Streaming Catalogs',
          'contentType': 'movie',
          'addonBaseUrl': 'https://x.example',
          'catalog': 'not-a-map',
          'movies': [],
        }),
        isNull,
      );
      expect(
        BrandSectionsCache.sectionFromJson({
          'title': 'no-movies',
          'subtitle': 'Streaming Catalogs',
          'contentType': 'movie',
          'addonBaseUrl': 'https://x.example',
          'catalog': {
            'type': 'movie',
            'id': 'nfx',
            'genres': <String>[],
            'supportsSearch': false,
            'supportsSkip': false,
          },
          'movies': <Map<String, dynamic>>[],
        }),
        isNull,
      );
    });

    test('identityKey separates sections by addon+catalog', () {
      final a = _section(baseUrl: 'https://a.example', catalogId: 'nfx');
      final b = _section(baseUrl: 'https://b.example', catalogId: 'nfx');
      final c = _section(baseUrl: 'https://a.example', catalogId: 'hbm');
      expect(BrandSectionsCache.identityKey(a),
          isNot(BrandSectionsCache.identityKey(b)));
      expect(BrandSectionsCache.identityKey(a),
          isNot(BrandSectionsCache.identityKey(c)));
      expect(
        BrandSectionsCache.identityKey(
          _section(baseUrl: 'https://a.example', catalogId: 'nfx'),
        ),
        BrandSectionsCache.identityKey(a),
      );
    });
  });

  group('BrandSectionsCache persistence', () {
    test('save + load round-trip through mocked prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final sections = [_section(), _section(type: 'series', catalogId: 'hbm')];
      await BrandSectionsCache.save(sections);

      final loaded = await BrandSectionsCache.load();
      expect(loaded.length, 2);
      expect(loaded[0].title, 'Netflix');
      expect(loaded[1].catalog.id, 'hbm');
      expect(loaded[1].movies.first.addonBaseUrl, 'https://provider.example');
    });

    test('load returns empty on missing/corrupt payload', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.home_brand_sections_v1': 'not json at all',
      });
      expect(await BrandSectionsCache.load(), isEmpty);

      SharedPreferences.setMockInitialValues({});
      expect(await BrandSectionsCache.load(), isEmpty);
    });

    test('clear removes the payload', () async {
      SharedPreferences.setMockInitialValues({});
      await BrandSectionsCache.save([_section()]);
      expect(await BrandSectionsCache.load(), isNotEmpty);
      await BrandSectionsCache.clear();
      expect(await BrandSectionsCache.load(), isEmpty);
    });
  });

  group('AddonManager.fetchCatalogResilient', () {
    test('returns the first successful result without retrying', () async {
      var calls = 0;
      final delays = <Duration>[];
      final movies = await AddonManager.fetchCatalogResilient(
        baseUrl: 'https://x.example',
        type: 'movie',
        catalogId: 'nfx',
        fetch: ({required baseUrl, required type, required catalogId}) async {
          calls++;
          return [Movie(id: 'tt1', name: 'A', type: 'movie', addonBaseUrl: baseUrl)];
        },
        delay: (d) async => delays.add(d),
      );

      expect(calls, 1);
      expect(delays, isEmpty);
      expect(movies, isNotNull);
      expect(movies!.first.id, 'tt1');
    });

    test('retries once after a failure and succeeds', () async {
      var calls = 0;
      final delays = <Duration>[];
      final movies = await AddonManager.fetchCatalogResilient(
        baseUrl: 'https://x.example',
        type: 'movie',
        catalogId: 'nfx',
        fetch: ({required baseUrl, required type, required catalogId}) async {
          calls++;
          if (calls == 1) throw Exception('transport blip');
          return [Movie(id: 'tt1', name: 'A', type: 'movie', addonBaseUrl: baseUrl)];
        },
        delay: (d) async => delays.add(d),
      );

      expect(calls, 2);
      expect(delays, [const Duration(milliseconds: 600)]);
      expect(movies, isNotNull);
      expect(movies!.first.id, 'tt1');
    });

    test('retries an empty result (healthy catalogs never return empty)',
        () async {
      var calls = 0;
      final movies = await AddonManager.fetchCatalogResilient(
        baseUrl: 'https://x.example',
        type: 'movie',
        catalogId: 'nfx',
        fetch: ({required baseUrl, required type, required catalogId}) async {
          calls++;
          if (calls == 1) return const [];
          return [Movie(id: 'tt1', name: 'A', type: 'movie', addonBaseUrl: baseUrl)];
        },
        delay: (d) async {},
      );

      expect(calls, 2);
      expect(movies, isNotNull);
      expect(movies!.first.id, 'tt1');
    });

    test('returns null after exhausting attempts on persistent failure',
        () async {
      var calls = 0;
      final movies = await AddonManager.fetchCatalogResilient(
        baseUrl: 'https://x.example',
        type: 'movie',
        catalogId: 'nfx',
        attempts: 2,
        fetch: ({required baseUrl, required type, required catalogId}) async {
          calls++;
          throw Exception('down');
        },
        delay: (d) async {},
      );

      expect(calls, 2);
      expect(movies, isNull);
    });

    test('no retry when attempts == 1', () async {
      var calls = 0;
      final movies = await AddonManager.fetchCatalogResilient(
        baseUrl: 'https://x.example',
        type: 'movie',
        catalogId: 'nfx',
        attempts: 1,
        fetch: ({required baseUrl, required type, required catalogId}) async {
          calls++;
          throw Exception('down');
        },
        delay: (d) async {},
      );

      expect(calls, 1);
      expect(movies, isNull);
    });

    test('returns the empty list (not null) when empty persists', () async {
      final movies = await AddonManager.fetchCatalogResilient(
        baseUrl: 'https://x.example',
        type: 'movie',
        catalogId: 'nfx',
        attempts: 2,
        fetch: ({required baseUrl, required type, required catalogId}) async =>
            const [],
        delay: (d) async {},
      );

      expect(movies, isNotNull);
      expect(movies, isEmpty);
    });
  });
}
