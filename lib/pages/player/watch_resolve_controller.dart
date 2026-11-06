import 'dart:async';

import '../../../models/stream/stream_model.dart';
import '../../../services/player/dub_mode_service.dart';
import '../../../services/stream/dub_filter.dart';
import '../../../services/stream/instant_play_gate.dart';
import '../../../services/stream/stream_health_checker.dart';
import '../../../services/stream/stream_probe_race.dart';
import '../../../services/stream/stream_relevance.dart';
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
    this.hindiFirstWindow = const Duration(seconds: 4),
    this.probeFn,
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

  /// How long a Hindi candidate gets to prove playable before explicit /
  /// default-English sources are released. Discovery itself may run 20s;
  /// a dead Hindi entry must not starve a working stream that whole time.
  final Duration hindiFirstWindow;

  /// Test seam for the health probe. Null uses the real checker.
  final Future<bool> Function(StreamSource source)? probeFn;

  // ── Moved state (was `_pendingSources` / `_nonHindiPool` /
  // `_sourceBatchTimer` / `_autoplayRace` on the screen) ──────────────
  final List<StreamSource> _pending = [];
  final List<StreamSource> _nonHindiPool = [];
  final List<StreamSource> _torrentCandidates = [];
  Timer? _batchTimer;
  Timer? _fallbackTimer;
  StreamProbeRace? _race;
  bool _hindiWon = false;
  bool _fallbackReleased = false;

  /// First exposure waits for this window so a fast HTTP source that lands a
  /// few hundred ms later can outrank an early torrent that would stall.
  static const Duration _exposureWindow = Duration(milliseconds: 400);
  bool _exposureWindowOpen = true;

  /// F1: "first valid source wins" lives here, not in the race. The race
  /// answers "which source is alive?"; the gate answers "should this
  /// source open playback right now, or is the race already won?" — so a
  /// second verified source can never interrupt the first.
  late final InstantPlayGate _autoplayGate = InstantPlayGate(
    autoplayEnabled: shouldAutoOpen,
    autoFailover: () => true, // failover is the player's business
  );

  /// Moved verbatim: old `_WatchScreenState._loadStreams`.
  Future<void> start() async {
    // ── Instant autoplay race (Phase 1) ─────────────────────────────
    // Every scraped source is health-probed in parallel; the FIRST one
    // verified alive auto-opens the player (unless the user has already
    // picked a source or autoplay is disabled in settings).
    if (shouldAutoOpen()) {
      final race = StreamProbeRace(probeFn: probeFn ?? StreamHealthChecker.isAlive);
      _race = race;

      // Embedded debrid streams are offered further below (after the
      // dub-mode gate) so Hindi mode only races hindi-tagged links.

      race.winner.then((src) {
        if (!isMounted() || src == null) return;
        if (DubModeService.isHindi && !_fallbackReleased) _hindiWon = true;
        if (!shouldAutoOpen()) return;
        // F1: the gate takes the first valid source; later winners are
        // ignored so a slow-but-alive source can never cut in.
        if (_autoplayGate.offer(src) != InstantPlayDecision.playNow) return;
        onInstantOpen(src);
      });
    }

    // 1. Immediately inject any embedded streams from the video (e.g. Torbox/Debrid direct streams)
    if (embeddedStreams.isNotEmpty) {
      final embedded = embeddedStreams.where(_isRelevant).toList();
      if (embedded.isEmpty) {
        // Everything embedded belongs to another show/episode — fall through
        // to the scraped stream instead of playing the wrong content.
      } else if (DubModeService.isHindi) {
        // Dub-mode gate: Hindi mode pe embedded debrid links bhi hindi-tagged honi
        // chahiye (strict same-language playback). Non-hindi embedded links
        // fallback pool mein jayengi — zero hindi mila to release ho jayengi.
        final embeddedHindi = filterByDubMode(
          embedded,
          hindi: true,
          mediaTitle: mediaTitle,
        );
        final embeddedOther = embedded
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
        _armFallbackDeadline();
      } else {
        _pending.addAll(embedded);
        for (final s in embedded) {
          _race?.offerEmbedded(s);
        }
        flush();
      }
    }

    try {
      final scrape =
          scrapeOverride ??
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
        // Wrong show / wrong episode / conflicting year → never offer it to
        // autoplay or the picker. A provider answering "Nocturne (2026)" with
        // "Castlevania Nocturne (2023)" must not get a green light.
        if (!_isRelevant(source)) continue;
        if (source.isTorrent) _torrentCandidates.add(source);
        // ── Dub-mode gate ────────────────────────────────────────────
        // Hindi mode ON: sirf hindi-tagged sources UI list aur autoplay
        // race dono ko jaate hain (health probe bhi sirf unhi pe).
        // Baaki sources fallback pool mein rakhe jaate hain — agar scrape
        // complete hone tak ek bhi hindi source nahi mila, to English
        // default play ke liye release kar diye jaate hain.
        if (DubModeService.isHindi &&
            !source.hasAudioLanguage('hindi', mediaTitle: mediaTitle)) {
          _nonHindiPool.add(source);
          _armFallbackDeadline();
          continue;
        }
        _pending.add(source);
        _scheduleBatch();
        // 3+ verified-looking HTTP hits are enough to expose immediately.
        if (_pending.where(_isHttpLike).length >= 3) flush();
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
      if (_screenHindiCount == 0) _releaseEnglishFallback(notify: true);
      _nonHindiPool.clear();
    }

    _fallbackTimer?.cancel();
    _maybeAutoplayTorrent();
    _race?.closeDrain();
    if (isMounted()) onLoadingDone();
  }

  /// Torrents cannot be HTTP-probed, so a torrent-only title used to stop at
  /// the picker even with autoplay on. Once discovery is done and no HTTP
  /// source opened, the best-seeded torrent goes straight to the player
  /// (TorrServer pre-warms the first megabytes).
  void _maybeAutoplayTorrent() {
    if (!shouldAutoOpen() || _torrentCandidates.isEmpty) return;
    final ranked = List<StreamSource>.of(_torrentCandidates);
    ranked.sort((a, b) => (b.seeders ?? 0).compareTo(a.seeders ?? 0));
    for (final torrent in ranked.take(3)) {
      if (_autoplayGate.offer(torrent) == InstantPlayDecision.playNow) {
        onInstantOpen(torrent);
        return;
      }
    }
  }

  bool _isRelevant(StreamSource source) => StreamRelevance.isRelevant(
    source: source,
    title: title,
    year: year,
    season: season,
    episode: episode,
  );

  /// Starts the one-shot playable-Hindi deadline. Armed only when autoplay
  /// is racing: without a race there is no "winner" to wait for, and the
  /// discovery-end check stays the only fallback trigger.
  void _armFallbackDeadline() {
    if (_fallbackTimer != null || _fallbackReleased || _race == null) return;
    _fallbackTimer = Timer(hindiFirstWindow, () {
      if (!isMounted() || _fallbackReleased || _hindiWon) return;
      _releaseEnglishFallback(notify: true);
    });
  }

  /// Releases held non-Hindi sources to the list and the race. Explicit
  /// English is offered first; untagged/default-audio and other languages
  /// follow so a mislabelled pool still has something playable.
  void _releaseEnglishFallback({required bool notify}) {
    if (_fallbackReleased) return;
    _fallbackReleased = true;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    if (_nonHindiPool.isEmpty) return;

    final ranked = List<StreamSource>.of(_nonHindiPool);
    _sortForExposure(ranked);
    final explicitEnglish = ranked
        .where((s) => s.hasAudioLanguage('english', mediaTitle: mediaTitle))
        .toList();
    final rest = ranked.where((s) => !explicitEnglish.contains(s));
    for (final s in [...explicitEnglish, ...rest]) {
      _pending.add(s);
      _race?.offer(s);
    }
    _nonHindiPool.clear();
    flush();
    if (notify && isMounted()) onEnglishFallback();
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
    _exposureWindowOpen = false;
    // Refresh the screen-visible hindi count on EVERY flush (even empty
    // ones) so the English-fallback check reads a live value.
    final reader = hindiCountReader;
    if (reader != null) _screenHindiCount = reader();
    if (!isMounted() || _pending.isEmpty) return;

    final batch = List<StreamSource>.of(_pending);
    _pending.clear();
    _sortForExposure(batch);
    onBatch(batch);
  }

  void _scheduleBatch() {
    if (_batchTimer != null) return;
    _batchTimer = Timer(
      _exposureWindowOpen ? _exposureWindow : const Duration(milliseconds: 60),
      flush,
    );
  }

  static bool _isHttpLike(StreamSource source) => _protocolTier(source) >= 2;

  /// https/HLS > plain HTTP > torrent. Everything else is treated as direct.
  static int _protocolTier(StreamSource source) {
    if (source.infoHash != null &&
        source.infoHash!.isNotEmpty &&
        !source.isDebrid) {
      return 0;
    }
    final url = (source.url ?? source.externalUrl ?? '').toLowerCase();
    if (url.contains('.m3u8') ||
        url.contains('/hls/') ||
        url.startsWith('https://')) {
      return 2;
    }
    if (url.startsWith('http://')) return 1;
    return 1;
  }

  /// Stable rank: protocol, seeders, quality/bitrate, title; arrival order
  /// is the final tiebreaker (explicit index sort — Dart's sort isn't stable).
  static void _sortForExposure(List<StreamSource> batch) {
    final order = List<int>.generate(batch.length, (i) => i);
    order.sort((a, b) {
      final byRank = _compareForExposure(batch[a], batch[b]);
      return byRank != 0 ? byRank : a.compareTo(b);
    });
    final sorted = [for (final i in order) batch[i]];
    for (var i = 0; i < batch.length; i++) {
      batch[i] = sorted[i];
    }
  }

  static int _compareForExposure(StreamSource a, StreamSource b) {
    final byProtocol = _protocolTier(b).compareTo(_protocolTier(a));
    if (byProtocol != 0) return byProtocol;

    final bySeeders = (b.seeders ?? 0).compareTo(a.seeders ?? 0);
    if (bySeeders != 0) return bySeeders;

    final byQuality = b.qualityRank.compareTo(a.qualityRank);
    if (byQuality != 0) return byQuality;

    final byBitrate = _maxBitrate(b).compareTo(_maxBitrate(a));
    if (byBitrate != 0) return byBitrate;

    return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
  }

  static int _maxBitrate(StreamSource source) {
    var max = 0;
    for (final rendition in source.renditions) {
      if (rendition.bitrate > max) max = rendition.bitrate;
    }
    return max;
  }

  /// User tapped a source manually — stop the autoplay race (was inline
  /// `_autoplayRace?.dispose()` in `onUserPicked`).
  void cancelAutoplay() => _race?.dispose();

  void dispose() {
    _batchTimer?.cancel();
    _fallbackTimer?.cancel();
    _race?.dispose();
  }
}
