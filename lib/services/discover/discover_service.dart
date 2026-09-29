/// F5 — the one place Discover Daily turns local state into rails.
///
/// Everything it decides is already decided by a pure policy next door:
/// [HistoryRailPolicy] ranks, [MoodQuizPolicy] answers, [ReminderSchedule]
/// builds alerts, [YearlyWrap] counts the year. This file only **collects**
/// — history rows, catalog sections, liked tracks — and **asks**.
///
/// Local first, always: no account, no AI call, no cost per rail. The rails
/// are worth something precisely because they are free and instant.
library;

import 'package:flutter/foundation.dart';

import '../../models/continue_watching/continue_watching_item.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../addon/addon_manager.dart';
import '../continue_watching/continue_watching_service.dart';
import '../home/genre_preference_service.dart';
import '../music/music_library_service.dart';
import '../music/music_smart_mix_service.dart';
import 'discover_copy.dart';
import 'history_rail_policy.dart';

/// One row on Discover Daily, ready to render.
class DiscoverSection {
  final String id;
  final String title;
  final String subtitle;

  /// Movie picks. Empty for the music row, which carries its own cards.
  final List<Movie> movies;

  /// Smart-mix ids for the music row. Empty for every other row.
  final List<String> mixIds;

  const DiscoverSection({
    required this.id,
    required this.title,
    required this.subtitle,
    this.movies = const [],
    this.mixIds = const [],
  });

  bool get isMusic => mixIds.isNotEmpty;
}

/// Builds and caches the Discover Daily rows.
class DiscoverService {
  DiscoverService._();
  static final DiscoverService instance = DiscoverService._();

  static const String musicSectionId = 'discover:smart-mix';

  final ValueNotifier<List<DiscoverSection>> sections =
      ValueNotifier<List<DiscoverSection>>(const []);

  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  List<DiscoverRail>? _railCache;
  List<Movie> _catalogPool = const [];

  /// True when the last build produced at least one rail with cards.
  bool get hasRails => sections.value.any((s) => s.movies.isNotEmpty);

  /// Drop cached rails. Called when history changes so a new show is
  /// reflected the next time the screen opens.
  void invalidate() {
    _railCache = null;
  }

  /// Build every row once, from local state only.
  Future<void> build({bool forceRefresh = false}) async {
    if (isLoading.value) return;
    if (!forceRefresh && _railCache != null) {
      sections.value = _fromRails(_railCache!);
      return;
    }

    isLoading.value = true;
    error.value = null;

    try {
      final history = historySignals();
      final candidates = await _catalogCandidates();

      final rails = HistoryRailPolicy.discoverRails(
        signals: history,
        candidates: candidates,
        genreScores: GenrePreferenceService.scores.value,
      );
      _railCache = rails;
      final out = _fromRails(rails);

      final mixes = await _musicMixes();
      if (mixes.isNotEmpty) {
        out.add(DiscoverSection(
          id: musicSectionId,
          title: DiscoverCopy.musicRailTitle,
          subtitle: DiscoverCopy.musicRailSubtitle,
          mixIds: mixes,
        ));
      }

      sections.value = out;
    } catch (e) {
      debugPrint('[DiscoverService] build failed: $e');
      error.value = DiscoverCopy.railError(null);
    } finally {
      isLoading.value = false;
    }
  }

  /// Rows from rails, in rail order. Movies are looked back up from the
  /// catalog so a card keeps its real poster and id.
  List<DiscoverSection> _fromRails(List<DiscoverRail> rails) {
    final byId = <String, Movie>{};
    for (final m in _catalogPool) {
      byId[m.id] = m;
    }

    final out = <DiscoverSection>[];
    for (final rail in rails) {
      if (rail.isEmpty) continue;
      final movies = <Movie>[];
      for (final p in rail.picks) {
        final m = byId[p.id];
        if (m != null) movies.add(m);
      }
      if (movies.isEmpty) continue;
      out.add(DiscoverSection(
        id: rail.id,
        title: rail.title,
        subtitle: rail.subtitle,
        movies: movies,
      ));
    }
    return out;
  }

  /// The local watch history, flattened for the rail policy.
  ///
  /// `ContinueWatchingItem` has no genres, so genre overlap comes from the
  /// local taste map instead — one number per genre, no raw titles, which is
  /// also what keeps this anonymous-first.
  static List<WatchSignal> historySignals({
    List<ContinueWatchingItem>? items,
  }) {
    final src = items ?? ContinueWatchingService.activeItems.value;
    final genres = <String, double>{};
    for (final g in GenrePreferenceService.scores.value.entries) {
      genres[g.key.trim().toLowerCase()] = g.value;
    }

    return src
        .where((i) => i.id.trim().isNotEmpty && i.title.trim().isNotEmpty)
        .map((i) => WatchSignal(
              mediaId: i.id,
              title: i.title,
              type: i.type,
              genres: const [],
              watchedAt: i.lastWatchedAt,
              progress: i.progressPercent,
            ))
        .toList();
  }

  /// Flatten catalog sections into rail candidates, keeping the movies for
  /// rendering.
  Future<List<RailCandidate>> _catalogCandidates() async {
    List<MovieSection> secs = const [];
    try {
      secs = await CatalogSections.load();
    } catch (e) {
      debugPrint('[DiscoverService] catalog unavailable: $e');
    }

    final movies = <Movie>[];
    final candidates = <RailCandidate>[];
    final seen = <String>{};

    for (final s in secs) {
      final genres = s.catalog.genres;
      for (final m in s.movies) {
        if (m.id.trim().isEmpty) continue;
        if (!seen.add(m.id)) continue;
        movies.add(m);
        candidates.add(RailCandidate(
          id: m.id,
          title: m.name,
          type: m.type,
          genres: genres,
          rating: double.tryParse(m.imdbRating ?? ''),
          // Sections have no id of their own; catalog id + type identifies
          // where a card came from without inventing a second key space.
          origin: '${s.contentType}:${s.catalog.id}',
        ));
      }
      if (candidates.length >= HistoryRailPolicy.maxCandidates) break;
    }

    _catalogPool = movies;
    return candidates;
  }

  /// Smart-mix ids for the music row.
  ///
  /// The mixes themselves stay in the music service — Discover only names
  /// them, so there is exactly one generator of mixes in the app.
  Future<List<String>> _musicMixes() async {
    try {
      final library = MusicLibraryService.instance;
      if (library.likedTracks.isEmpty && library.recentTracks.isEmpty) {
        return const [];
      }
      final mixes = await MusicSmartMixService.instance.getOrGenerateMixes();
      return mixes
          .where((m) => m.tracks.isNotEmpty)
          .map((m) => m.id)
          .toList();
    } catch (e) {
      debugPrint('[DiscoverService] mixes unavailable: $e');
      return const [];
    }
  }
}

/// Seam over the addon manager.
///
/// Discover depends on exactly one thing from the catalog: a list of
/// sections. Naming that one thing here keeps the test seam honest and keeps
/// the rest of the file from reaching into the manager.
abstract final class CatalogSections {
  static Future<List<MovieSection>> Function()? _loader;

  /// Test seam. `null` restores the real catalog.
  static void override(Future<List<MovieSection>> Function()? loader) {
    _loader = loader;
  }

  static Future<List<MovieSection>> load() async {
    final o = _loader;
    if (o != null) return o();
    return AddonManager.instance.fetchAllHomeSections();
  }
}
