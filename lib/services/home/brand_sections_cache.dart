import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';

/// Last-good cache for the Streaming Catalogs brand rail (Part A, 2026-11-12).
///
/// The provider addon (e.g. the baby-beamup.club deployment) is healthy when
/// probed directly, but on a cold session the emulator's flaky DNS often
/// kills the first fetch burst. Before this cache existed, `_loadHome`
/// cleared `_brandSections` on every load, so one transient failure meant
/// the rail was gone for the entire session ("comes and goes").
///
/// Fresh sections are saved whenever they stream in; on the next cold start
/// `_loadHome` seeds the rail from here before the network answers, so the
/// rail always shows. Fresh data then replaces cached sections one by one
/// (keyed by `addonBaseUrl|type|catalogId`), never mixing stale rows in.
///
/// Storage budget: movies are trimmed to [_maxMoviesPerSection] per section
/// and descriptions are not stored — the rail only needs tiles, and the
/// catalog page re-fetches the full list when opened.
class BrandSectionsCache {
  BrandSectionsCache._();

  static const String _storageKey = 'home_brand_sections_v1';

  /// Public so tests can assert the storage-trim behaviour.
  static const int maxMoviesPerSection = 30;

  /// Persist the last-good brand sections. Fire-and-forget from `_loadHome`;
  /// a storage failure must never break the home page, so everything is
  /// wrapped fail-soft.
  static Future<void> save(List<MovieSection> sections) async {
    if (sections.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(
        sections.map(sectionToJson).toList(growable: false),
      );
      await prefs.setString(_storageKey, payload);
    } catch (_) {
      // Fail-soft: the cache is an optimization, never a requirement.
    }
  }

  /// Load the last-good brand sections, or an empty list when none exist or
  /// the payload is unreadable (schema change, corruption).
  static Future<List<MovieSection>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(sectionFromJson)
          .whereType<MovieSection>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Remove the cache (used by tests and by a forced refresh).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {
      // Fail-soft.
    }
  }

  /// Identity key used by the home page to replace a cached section with
  /// its fresh counterpart (same addon, same catalog).
  static String identityKey(MovieSection s) =>
      '${s.addonBaseUrl}|${s.catalog.type}|${s.catalog.id}';

  /// Pure serializer — unit-testable without SharedPreferences.
  static Map<String, dynamic> sectionToJson(MovieSection s) => {
    'title': s.title,
    'subtitle': s.subtitle,
    'contentType': s.contentType,
    'addonBaseUrl': s.addonBaseUrl,
    'catalog': s.catalog.toJson(),
    'movies': s.movies
        .take(maxMoviesPerSection)
        .map(_movieToJson)
        .toList(growable: false),
  };

  /// Pure deserializer — returns null for malformed entries so one bad
  /// section cannot blank the whole cached rail.
  static MovieSection? sectionFromJson(Map<String, dynamic> json) {
    try {
      final catalogJson = json['catalog'];
      if (catalogJson is! Map<String, dynamic>) return null;
      final catalog = AddonCatalog.fromJson(catalogJson);
      if (catalog.id.isEmpty) return null;

      final moviesJson = json['movies'];
      final baseUrl = json['addonBaseUrl']?.toString() ?? '';
      final movies = moviesJson is List
          ? moviesJson
                .whereType<Map<String, dynamic>>()
                .map(_movieFromJson)
                .where((m) => m.id.isNotEmpty && m.name.isNotEmpty)
                .map((m) => Movie(
                      id: m.id,
                      name: m.name,
                      poster: m.poster,
                      year: m.year,
                      type: m.type,
                      addonBaseUrl: baseUrl,
                      imdbRating: m.imdbRating,
                    ))
                .toList(growable: false)
          : const <Movie>[];
      if (movies.isEmpty) return null;

      return MovieSection(
        title: json['title']?.toString() ?? '',
        subtitle: json['subtitle']?.toString() ?? '',
        contentType: json['contentType']?.toString() ?? '',
        addonBaseUrl: baseUrl,
        catalog: catalog,
        movies: movies,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _movieToJson(Movie m) => {
    'id': m.id,
    'name': m.name,
    if (m.poster != null) 'poster': m.poster,
    if (m.year != null) 'year': m.year,
    'type': m.type,
    if (m.imdbRating != null) 'imdbRating': m.imdbRating,
  };

  static Movie _movieFromJson(Map<String, dynamic> json) => Movie(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    poster: json['poster']?.toString(),
    year: json['year']?.toString(),
    type: json['type']?.toString() ?? 'movie',
    addonBaseUrl: json['addonBaseUrl']?.toString() ?? '',
    imdbRating: json['imdbRating']?.toString(),
  ); // addonBaseUrl is re-stamped from the section in sectionFromJson.
}
