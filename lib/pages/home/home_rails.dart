import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../services/catalog/catalog_service.dart';

/// India-first home rails (2026-11-09 slice).
///
/// All data flows through the existing `catalog` edge function (server-side
/// TMDB key) — no device-side key, no hardcoded ids. Rails are appended
/// below the existing home content; the hero picks its featured titles from
/// rails first via [orderForFeatured].
MovieSection? buildRailSection(
  List<CatalogCard> cards, {
  required String title,
  required String subtitle,
  required String catalogId,
}) {
  if (cards.isEmpty) return null;
  return MovieSection(
    title: title,
    subtitle: subtitle,
    contentType: 'mixed',
    addonBaseUrl: '',
    catalog: AddonCatalog(
      type: 'mixed',
      id: catalogId,
      genres: const [],
      supportsSearch: false,
      supportsSkip: false,
    ),
    movies: [
      for (final c in cards)
        Movie(
          id: 'tmdb:${c.id}',
          name: c.title,
          poster: c.poster,
          year: c.year.isEmpty ? null : c.year,
          type: c.mediaType == 'tv' ? 'series' : 'movie',
          addonBaseUrl: '',
          imdbRating: c.rating > 0 ? c.rating.toStringAsFixed(1) : null,
        ),
    ],
  );
}

/// Rail titles shown per language chip. Pure; unit-tested.
const southRailLanguages = <String, String>{
  'ta': 'Tamil',
  'te': 'Telugu',
  'ml': 'Malayalam',
};

/// Which rails are visible for the selected chip. Unknown/empty chip and
/// missing fetches fail open — the row only ever hides what doesn't exist.
/// Pure; unit-tested.
List<MovieSection> railsForChip(
  String chip, {
  required MovieSection? india,
  required MovieSection? hindi,
  required MovieSection? south,
}) {
  switch (chip) {
    case 'hi':
      return [if (hindi != null) hindi];
    case 'ta':
    case 'te':
    case 'ml':
      if (south == null) return const [];
      return [
        MovieSection(
          title: '${southRailLanguages[chip]} Blockbusters',
          subtitle: southRailLanguages[chip] ?? '',
          contentType: south.contentType,
          addonBaseUrl: south.addonBaseUrl,
          catalog: AddonCatalog(
            type: south.catalog.type,
            id: 'south_${chip}_blockbusters',
            genres: south.catalog.genres,
            supportsSearch: south.catalog.supportsSearch,
            supportsSkip: south.catalog.supportsSkip,
          ),
          movies: south.movies,
        ),
      ];
    default:
      return [
        if (india != null) india,
        if (hindi != null) hindi,
        if (south != null) south,
      ];
  }
}

/// Home ordering rule: anime addon catalogs float to the top of the addon
/// sections; everything else keeps its arrival order. Mutates [list].
/// Unit-tested.
void insertHomeSection(List<MovieSection> list, MovieSection section) {
  if (section.contentType == 'anime') {
    list.insert(0, section);
  } else {
    list.add(section);
  }
}

/// Hero picking order: rails first (India titles lead the hero), then the
/// regular sections in their display order. Pure; unit-tested.
List<MovieSection> orderForFeatured(
  List<MovieSection> rails,
  List<MovieSection> sections,
) {
  return [...rails, ...sections];
}

/// Cinemeta catalogs that never belong on home (2026-11-09 decluttering):
/// the trailing "Last videos" and "Calendar videos" rows. Pure; unit-tested.
const hiddenHomeCatalogIds = <String>{'last-videos', 'calendar-videos'};

bool isHiddenHomeSection(MovieSection section) =>
    hiddenHomeCatalogIds.contains(section.catalog.id);

/// Movie-level home decluttering (user-requested 2026-11-10): the pirated
/// 'IT: Welcome to Derry' re-cut ('A Story of Derry') saturated every hero
/// rotation slot. Titles are matched by lowercase substring against the
/// cleaned display name; the rail stays visible — only the hero skips it.
/// Pure; unit-tested.
const hiddenHeroMovieTitles = <String>{'story of derry', 'welcome to derry'};

bool isHiddenHeroMovie(Movie movie) {
  final name = movie.name.toLowerCase();
  return hiddenHeroMovieTitles.any(name.contains);
}

/// The per-provider catalog addon groups its sections under this manifest
/// name; home renders them as one brand rail instead of five rows.
const providerAddonName = 'Streaming Catalogs';

/// Netflix / HBO Max / Prime Video / Apple TV / Disney+ — bundled logo per
/// provider, matched leniently so small manifest naming differences still
/// resolve. Unknown providers get no logo (text tile). Pure; unit-tested.
const _providerBrandAssets = <String, String>{
  'netflix': 'assets/brands/netflix.png',
  'hbo': 'assets/brands/hbomax.png',
  'prime': 'assets/brands/primevideo.png',
  'apple': 'assets/brands/appletv.png',
  'disney': 'assets/brands/disneyplus.png',
};

String? providerBrandAsset(String title) {
  final key = title.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  for (final entry in _providerBrandAssets.entries) {
    if (key.startsWith(entry.key)) return entry.value;
  }
  return null;
}

/// Canonical brand key for a provider section title ('Netflix — Movies' →
/// 'netflix', 'HBO Max' → 'hbo' …) so every catalog of the same brand shares
/// one tile. Null when the provider has no bundled logo and must stay its own
/// tile. Pure; unit-tested.
String? brandKeyFor(String title) {
  final key = title.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  for (final entry in _providerBrandAssets.entries) {
    if (key.startsWith(entry.key)) return entry.key;
  }
  return null;
}

/// Collapses provider-addon sections that belong to the same streaming brand
/// (Netflix movies Netflix series, HBO Max movies/series …) into single
/// groups, preserving first-seen order; each group renders as ONE round
/// brand tile whose catalog page switches between the brand's content types.
/// Sections without a known brand stay singleton groups. Pure; unit-tested.
List<List<MovieSection>> groupBrandSections(List<MovieSection> sections) {
  final buckets = <String, List<MovieSection>>{};
  final order = <String>[];
  for (final s in sections) {
    final key = brandKeyFor(s.title) ?? 'solo:${s.catalog.id}:${s.contentType}';
    (buckets[key] ??= []).add(s);
    if (!order.contains(key)) order.add(key);
  }
  return [for (final k in order) buckets[k]!];
}

/// Splits the addon sections into provider-brand sections (rendered as the
/// round brand rail) and everything else. Pure; unit-tested.
(List<MovieSection>, List<MovieSection>) splitProviderBrands(
  List<MovieSection> sections,
) {
  final brands = <MovieSection>[];
  final rest = <MovieSection>[];
  for (final s in sections) {
    if (s.subtitle == providerAddonName) {
      brands.add(s);
    } else {
      rest.add(s);
    }
  }
  return (brands, rest);
}

/// Selected language chip, persisted so the home looks the same next launch.
class LanguageChipState extends ChangeNotifier {
  LanguageChipState._();

  static final LanguageChipState instance = LanguageChipState._();

  static const _prefKey = 'home_language_chip';

  /// null = no chip row state loaded yet; 'all' = no filter.
  String _value = 'all';

  String get value => _value;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefKey);
      if (stored != null && stored.isNotEmpty) _value = stored;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> set(String chip) async {
    if (chip == _value) return;
    _value = chip;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, chip);
    } catch (_) {}
  }
}
