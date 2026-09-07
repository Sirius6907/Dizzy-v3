import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/stream/stream_model.dart';
import '../../models/movie/video.dart';
import '../player/dub_mode_service.dart';
import 'dub_filter.dart';
import 'stream_probe_race.dart';
import 'stream_service.dart';

/// Result of computing the "next episode" in a binge chain.
class NextEpisode {
  final Video episode; // The Video to play next (has id/season/episode).
  final bool isSeriesFinale; // True if current was the last episode ever.

  const NextEpisode({required this.episode, required this.isSeriesFinale});
}

/// Prefetches the next episode's playable stream *while the current one is
/// still playing*, so that when playback completes the next episode can
/// start in < 1 second (Netflix-style binge).
///
/// Pipeline:
///   1. [startPrefetch] → resolves the next (season, episode) from the
///      show's episode list (episode N+1, wrapping seasons on finale).
///   2. Scrapes + parallel-probes its sources via [StreamProbeRace].
///   3. [prefetchedSource] holds the first verified playable source,
///      ready for the moment playback completes.
class NextEpisodeEngine {
  StreamProbeRace? _race;
  StreamSubscription<StreamSource>? _scrapeSub;
  StreamSource? _prefetchedSource;
  Video? _prefetchedEpisode;
  bool _running = false;

  // Dub mode (Hindi): embedded english debrid links held back while the
  // scrape looks for hindi sources — released only as English fallback.
  final List<StreamSource> _embeddedFallbackPool = [];

  /// The verified playable source for the next episode (null until ready).
  StreamSource? get prefetchedSource => _prefetchedSource;

  /// The Video metadata of the next episode (null until computed).
  Video? get prefetchedEpisode => _prefetchedEpisode;

  /// Whether a prefetch cycle is currently in flight.
  bool get isRunning => _running;

  /// True when a next episode exists and its source is ready to play.
  bool get hasNextEpisode =>
      !_running && _prefetchedSource != null && _prefetchedEpisode != null;

  /// Computes the next episode in order from the show's full episode list.
  ///
  /// Ordering: sort by (season, episode-number). Next = the entry after the
  /// current (season, episode). Wraps season finales (S1E12 → S2E1). Returns
  /// null when the current episode is the series finale or the list is
  /// missing/empty.
  static NextEpisode? computeNext({
    required List<Video> episodes,
    required int currentSeason,
    required int currentEpisode,
  }) {
    if (episodes.isEmpty) return null;

    // Order episodes: season asc, then episode number asc (nulls last).
    final sorted = List<Video>.of(episodes)..sort((a, b) {
      final sa = a.season ?? 0;
      final sb = b.season ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      final ea = a.episode ?? 0;
      final eb = b.episode ?? 0;
      return ea.compareTo(eb);
    });

    // Find index of current episode in the sorted list.
    int idx = -1;
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i].season ?? 0;
      final e = sorted[i].episode ?? 0;
      if (s == currentSeason && e == currentEpisode) {
        idx = i;
        break;
      }
    }

    if (idx == -1) {
      // Current not found (specials/unknown) — can't compute reliably.
      return null;
    }

    if (idx + 1 >= sorted.length) {
      return NextEpisode(
        episode: Video(id: '', title: ''), // sentinel for callers to check isSeriesFinale
        isSeriesFinale: true,
      );
    }

    return NextEpisode(episode: sorted[idx + 1], isSeriesFinale: false);
  }

  /// Starts scraping + probing the next episode after
  /// (currentSeason, currentEpisode). Safe to call multiple times —
  /// restarts a fresh cycle and drops the previous one.
  Future<void> startPrefetch({
    required String type,
    required String id,
    required String title,
    required List<Video> allEpisodes,
    required int currentSeason,
    required int currentEpisode,
    int? year,
  }) async {
    dispose(); // drop any previous cycle

    final next = computeNext(
      episodes: allEpisodes,
      currentSeason: currentSeason,
      currentEpisode: currentEpisode,
    );

    if (next == null || next.isSeriesFinale) {
      debugPrint('[NextEpisodeEngine] No next episode (finale or unknown list).');
      return;
    }

    final nextEp = next.episode;
    _prefetchedEpisode = nextEp;
    _running = true;

    debugPrint('[NextEpisodeEngine] Prefetching S${nextEp.season}E${nextEp.episode}...');

    // 1. Trusted embedded streams (debrid direct links) probe in 0ms.
    if (nextEp.streams.isNotEmpty) {
      // Dub-mode gate: Hindi mode pe next episode ka embedded stream bhi
      // hindi-tagged hona chahiye. Non-hindi embedded fallback pool mein.
      final isHindiMode = DubModeService.isHindi;
      final embeddedHindi = isHindiMode
          ? filterByDubMode(nextEp.streams, hindi: true, mediaTitle: title)
          : nextEp.streams;
      final embeddedOther = isHindiMode
          ? nextEp.streams.where((s) => !embeddedHindi.contains(s)).toList()
          : const <StreamSource>[];

      if (embeddedHindi.isNotEmpty) {
        final race = StreamProbeRace(
          probeFn: (_) async => true, // embedded debrid streams are direct
          onVerifiedBatch: null,
        );
        _race = race;
        for (final s in embeddedHindi) {
          race.offer(s);
        }
        race.close();
        _prefetchedSource = await race.winner;
        if (_prefetchedSource != null) {
          debugPrint('[NextEpisodeEngine] Embedded stream ready for S${nextEp.season}E${nextEp.episode}.');
          _running = false;
          return;
        }
      }

      // Hindi mode + zero hindi embedded → remember as fallback pool; the
      // scrape below may still find hindi sources. Embedded English links
      // are only raced after scrape confirms zero hindi overall.
      if (embeddedOther.isNotEmpty) {
        _embeddedFallbackPool.addAll(embeddedOther);
      }
    }

    // 2. Scrape + parallel-probe the next episode's sources.
    final race = StreamProbeRace();
    _race = race;

    final winnerFuture = race.winner;
    final nonHindiPool = <StreamSource>[];
    final embeddedFallback = List<StreamSource>.from(_embeddedFallbackPool);
    _embeddedFallbackPool.clear();

    _scrapeSub = StreamService.fetchStreams(
      type: type,
      id: id,
      title: title,
      year: year,
      season: nextEp.season,
      episode: nextEp.episode,
    ).listen(
      (source) {
        // Dub-mode gate: next-episode autoplay must stay in the selected
        // language. Non-hindi sources wait in the fallback pool.
        if (DubModeService.isHindi &&
            !source.hasAudioLanguage('hindi', mediaTitle: title)) {
          nonHindiPool.add(source);
          return;
        }
        race.offer(source);
      },
      onError: (Object e) {
        debugPrint('[NextEpisodeEngine] Scrape error: $e');
      },
      onDone: () {
        // English fallback: zero hindi found → release non-hindi sources
        // (incl. embedded english debrid links) so the winner is still a
        // healthy (english) source.
        if (DubModeService.isHindi &&
            race.verifiedSources.isEmpty &&
            (nonHindiPool.isNotEmpty || embeddedFallback.isNotEmpty)) {
          for (final s in nonHindiPool) {
            race.offer(s);
          }
          for (final s in embeddedFallback) {
            race.offerEmbedded(s);
          }
        }
        race.close();
      },
    );

    _prefetchedSource = await winnerFuture;
    _running = false;

    if (_prefetchedSource != null) {
      debugPrint('[NextEpisodeEngine] Prefetch ready: '
          '${_prefetchedSource!.name ?? "?"} (${_prefetchedSource!.addonName}) '
          'for S${nextEp.season}E${nextEp.episode}.');
    } else {
      debugPrint('[NextEpisodeEngine] No playable source found for next episode.');
    }
  }

  /// Cancels the in-flight cycle and clears the prefetched state.
  void dispose() {
    _running = false;
    _scrapeSub?.cancel();
    _scrapeSub = null;
    _race?.dispose();
    _race = null;
    _prefetchedSource = null;
    _prefetchedEpisode = null;
    _embeddedFallbackPool.clear();
  }
}
