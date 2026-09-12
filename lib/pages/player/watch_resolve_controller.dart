import 'dart:async';

import '../../../models/stream/stream_model.dart';
import '../../../services/player/dub_mode_service.dart';
import '../../../services/stream/dub_filter.dart';
import '../../../services/stream/stream_probe_race.dart';
import '../../../services/stream/stream_service.dart';

/// P17 — source-resolve pipeline extracted verbatim from `watch_screen.dart`
/// (god-file split, step 1). Zero behavior change: the screen owns the UI
/// list (`_sources`) + filters; this controller owns the scrape subscription,
/// dub-mode gating, 60ms batching, the autoplay probe race and the
/// English-fallback release. UI effects cross back via callbacks so this
/// file stays widget-free (unit-testable, no BuildContext).
class WatchResolveController {
  WatchResolveController({
    required this.type,
    required this.streamId,
    required this.title,
    this.year,
    this.season,
    this.episode,
    required this.mediaTitle,
    required this.embeddedStreams,
    required this.isMounted,
    required this.shouldAutoOpen,
    required this.hindiCountReader,
    required this.onBatch,
    required this.onLoadingDone,
    required this.onInstantOpen,
    required this.onEnglishFallback,
    this.scrapeOverride,
  });

  // ── Resolve inputs (were `widget.*` reads) ──────────────────────────
  final String type;
  final String streamId;
  final String title;
  final int? year;
  final int? season;
  final int? episode;
  final String mediaTitle;
  final List<StreamSource> embeddedStreams;

  // ── Screen bridges ─────────────────────────────────────────────────
  final bool Function() isMounted;
  final bool Function() shouldAutoOpen;
  final void Function(List<StreamSource> batch) onBatch;
  final void Function() onLoadingDone;
  final void Function(StreamSource source) onInstantOpen;
  final void Function() onEnglishFallback;

  /// Test-only seam: replaces the `StreamService.fetchStreams` subscription
  /// so unit tests can drive the pipeline without network. `null` in prod
  /// (identical behavior to the old inline code).
  final Stream<StreamSource>? scrapeOverride;

  // ── Moved state (was `_pendingSources` / `_nonHindiPool` /
  // `_sourceBatchTimer` / `_autoplayRace` on the screen) ──────────────
  final List<StreamSource> _pending = [];
  final List<StreamSource> _nonHindiPool = [];
  Timer? _batchTimer;
  StreamProbeRace? _race;

  /// Moved verbatim: old `_WatchScreenState._loadStreams`.
  Future<void> start() async {
    // ── Instant autoplay race (Phase 1) ─────────────────────────────
    // Every scraped source is health-probed in parallel; the FIRST one
    // verified alive auto-opens the player (unless the user has already
    // picked a source or autoplay is disabled in settings).
    if (shouldAutoOpen()) {
      final race = StreamProbeRace();
      _race = race;

      // Embedded debrid streams are offered further below (after the
      // dub-mode gate) so Hindi mode only races hindi-tagged links.

      race.winner.then((src) {
        if (!isMounted() || src == null) return;
        if (!shouldAutoOpen()) return;
        onInstantOpen(src);
      });
    }

    // 1. Immediately inject any embedded streams from the video (e.g. Torbox/Debrid direct streams)
    if (embeddedStreams.isNotEmpty) {
      // Dub-mode gate: Hindi mode pe embedded debrid links bhi hindi-tagged honi
      // chahiye (strict same-language playback). Non-hindi embedded links
      // fallback pool mein jayengi — zero hindi mila to release ho jayengi.
      if (DubModeService.isHindi) {
        final embeddedHindi = filterByDubMode(embeddedStreams,
            hindi: true, mediaTitle: mediaTitle);
        final embeddedOther = embeddedStreams
            .where((s) => !embeddedHindi.contains(s))
            .toList();
        _pending.addAll(embeddedHindi);
        if (embeddedHindi.isNotEmpty) {
          for (final s in embeddedHindi) {
            _race?.offerEmbedded(s);
          }
        }
        _nonHindiPool.addAll(embeddedOther);
        if (embeddedHindi.isNotEmpty) flush();
      } else {
        _pending.addAll(embeddedStreams);
        for (final s in embeddedStreams) {
          _race?.offerEmbedded(s);
        }
        flush();
      }
    }

    try {
      final scrape = scrapeOverride ??
          StreamService.fetchStreams(
            type: type,
            id: streamId,
            title: title,
            year: year,
            season: season,
            episode: episode,
          );
      await for (final source in scrape) {
        if (!isMounted()) return;
        // ── Dub-mode gate ────────────────────────────────────────────
        // Hindi mode ON: sirf hindi-tagged sources UI list aur autoplay
        // race dono ko jaate hain (health probe bhi sirf unhi pe).
        // Baaki sources fallback pool mein rakhe jaate hain — agar scrape
        // complete hone tak ek bhi hindi source nahi mila, to English
        // default play ke liye release kar diye jaate hain.
        if (DubModeService.isHindi &&
            !source.hasAudioLanguage('hindi', mediaTitle: mediaTitle)) {
          _nonHindiPool.add(source);
          continue;
        }
        _pending.add(source);
        _batchTimer ??= Timer(
          const Duration(milliseconds: 60),
          flush,
        );
        // Parallel health probe for the autoplay race (never blocks UI).
        _race?.offer(source);
      }
    } catch (_) {}

    flush();

    // ── Dub-mode English fallback ─────────────────────────────────
    // Hindi mode ON thi lekin ek bhi hindi source nahi mila — English
    // default play karo + user ko ek baar notice kar do.
    if (DubModeService.isHindi && _nonHindiPool.isNotEmpty) {
      // NOTE: hindi-count is computed by the screen (it owns `_sources`);
      // the screen reports back through [reportHindiCount].
      if (_screenHindiCount == 0) {
        for (final s in _nonHindiPool) {
          _pending.add(s);
          _race?.offer(s);
        }
        flush();
        if (isMounted()) onEnglishFallback();
      }
      _nonHindiPool.clear();
    }

    _race?.closeDrain();
    if (isMounted()) onLoadingDone();
  }

  /// Last reader-seen hindi count in the screen's visible list
  /// (was an inline `_sources.where(...)` on the screen).
  int _screenHindiCount = 0;

  /// Reader the screen installs so the English-fallback check sees the
  /// visible hindi count (was an inline `_sources.where(...)` on the screen).
  int Function()? hindiCountReader;

  /// Moved verbatim: old `_WatchScreenState._flushPendingSources`
  /// (minus `setState` — the screen applies the batch in `onBatch`).
  void flush() {
    _batchTimer?.cancel();
    _batchTimer = null;
    // Refresh the screen-visible hindi count on EVERY flush (even empty
    // ones) so the English-fallback check reads a live value.
    final reader = hindiCountReader;
    if (reader != null) _screenHindiCount = reader();
    if (!isMounted() || _pending.isEmpty) return;

    final batch = List<StreamSource>.of(_pending);
    _pending.clear();
    onBatch(batch);
  }

  /// User tapped a source manually — stop the autoplay race (was inline
  /// `_autoplayRace?.dispose()` in `onUserPicked`).
  void cancelAutoplay() => _race?.dispose();

  void dispose() {
    _batchTimer?.cancel();
    _race?.dispose();
  }
}
