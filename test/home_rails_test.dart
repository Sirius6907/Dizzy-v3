import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/addon/addon.dart';
import 'package:dizzy/models/movie/movie_section.dart';
import 'package:dizzy/models/movie/movie.dart';
import 'package:dizzy/services/catalog/catalog_service.dart';
import 'package:dizzy/pages/home/home_rails.dart';

MovieSection _section(String title, List<String> names, {String type = 'movie', String subtitle = 'sub'}) {
  return MovieSection(
    title: title,
    subtitle: subtitle,
    contentType: type,
    addonBaseUrl: '',
    catalog: AddonCatalog(
      type: type,
      id: title.toLowerCase().replaceAll(' ', '-'),
      genres: const [],
      supportsSearch: false,
      supportsSkip: false,
    ),
    movies: [
      for (final n in names)
        Movie(
          id: 'tmdb:$n',
          name: n,
          poster: null,
          type: type,
          addonBaseUrl: '',
        ),
    ],
  );
}

CatalogCard _card(int id, String title, {String lang = 'hi', String mediaType = 'movie'}) {
  return CatalogCard(
    id: id,
    title: title,
    poster: 'https://img/p$id.jpg',
    year: '2026',
    rating: 7.5,
    mediaType: mediaType,
    lang: lang,
  );
}

void main() {
  group('buildRailSection', () {
    test('maps cards to tmdb: movies with type mapping', () {
      final section = buildRailSection(
        [_card(1, 'Kalki', mediaType: 'movie'), _card(2, 'Panchayat', mediaType: 'tv')],
        title: 'India Trending',
        subtitle: 'What India is watching',
        catalogId: 'india_trending',
      );
      expect(section, isNotNull);
      expect(section!.title, 'India Trending');
      expect(section.catalog.id, 'india_trending');
      expect(section.movies[0].id, 'tmdb:1');
      expect(section.movies[0].type, 'movie');
      expect(section.movies[1].type, 'series');
      expect(section.movies[0].imdbRating, '7.5');
    });

    test('empty cards → null (no empty rail)', () {
      expect(
        buildRailSection([], title: 'x', subtitle: 'y', catalogId: 'z'),
        isNull,
      );
    });
  });

  group('railsForChip', () {
    final india = _section('India Trending', ['a']);
    final hindi = _section('Hindi New', ['b']);
    final south = _section('South Blockbusters', ['c']);

    test('all → the three rails in order', () {
      final rails = railsForChip('all', india: india, hindi: hindi, south: south);
      expect(rails.map((s) => s.title), ['India Trending', 'Hindi New', 'South Blockbusters']);
    });

    test('hindi chip → Hindi New only', () {
      final rails = railsForChip('hi', india: india, hindi: hindi, south: south);
      expect(rails.map((s) => s.title), ['Hindi New']);
    });

    test('tamil chip → south rail retitled to language', () {
      final rails = railsForChip('ta', india: india, hindi: hindi, south: south);
      expect(rails.length, 1);
      expect(rails.first.title, 'Tamil Blockbusters');
    });

    test('unknown chip → all rails (fail-open)', () {
      final rails = railsForChip('xx', india: india, hindi: hindi, south: south);
      expect(rails.length, 3);
    });

    test('null rails dropped', () {
      final rails = railsForChip('all', india: null, hindi: hindi, south: null);
      expect(rails.map((s) => s.title), ['Hindi New']);
    });
  });

  group('insertHomeSection', () {
    test('anime sections go to the top', () {
      final list = [_section('Catalog A', ['x']), _section('Catalog B', ['y'])];
      insertHomeSection(list, _section('AcuAnime Popular', ['z'], type: 'anime'));
      expect(list.first.title, 'AcuAnime Popular');
      expect(list.length, 3);
    });

    test('non-anime sections append in order', () {
      final list = [_section('Catalog A', ['x'])];
      insertHomeSection(list, _section('Catalog B', ['y']));
      expect(list.map((s) => s.title), ['Catalog A', 'Catalog B']);
    });
  });

  group('orderForFeatured', () {
    test('rails come first so the hero picks India titles', () {
      final rails = [_section('India Trending', ['Kalki']), _section('Hindi New', ['Stree'])];
      final rest = [_section('Catalog A', ['Other'])];
      final ordered = orderForFeatured(rails, rest);
      expect(ordered.first.title, 'India Trending');
      expect(ordered[1].title, 'Hindi New');
      expect(ordered.last.title, 'Catalog A');
    });

    test('no rails → unchanged order', () {
      final rest = [_section('Catalog A', ['Other'])];
      expect(orderForFeatured([], rest).first.title, 'Catalog A');
    });
  });

  group('home decluttering', () {
    test('last-videos and calendar-videos sections are hidden', () {
      final last = _section('Last videos', ['a']);
      final cal = _section('Calendar videos', ['b']);
      final pop = _section('Popular Movies', ['c']);
      expect(isHiddenHomeSection(last), isTrue);
      expect(isHiddenHomeSection(cal), isTrue);
      expect(isHiddenHomeSection(pop), isFalse);
    });

    test('provider catalog sections group into brand tiles, rest untouched', () {
      final netflix = _section('Netflix', ['n1'], subtitle: 'Streaming Catalogs');
      final hbo = _section('HBO Max', ['h1'], subtitle: 'Streaming Catalogs');
      final prime = _section('Prime Video', ['p1'], subtitle: 'Streaming Catalogs');
      final pop = _section('Popular Movies', ['c1']);
      final (brands, rest) = splitProviderBrands([netflix, pop, hbo, prime]);
      expect(brands.map((s) => s.title), ['Netflix', 'HBO Max', 'Prime Video']);
      expect(rest.map((s) => s.title), ['Popular Movies']);
    });

    test('every known provider brand has a bundled logo asset', () {
      for (final name in ['Netflix', 'HBO Max', 'Prime Video', 'Apple TV', 'Disney+']) {
        expect(
          providerBrandAsset(name),
          startsWith('assets/brands/'),
          reason: '$name must map to a bundled logo',
        );
      }
      expect(providerBrandAsset('Netflix'), 'assets/brands/netflix.png');
      expect(providerBrandAsset('Unknown Provider'), isNull);
    });
  });
}
