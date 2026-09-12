import 'dart:async';
import '../../models/stream/stream_model.dart';
import 'stream_health_checker.dart';
import '../errors/app_log.dart';

/// Races health probes of many sources **in parallel** (never serialized).
///
/// The FIRST source that passes its health check wins the [winner] future —
/// used to trigger instant autoplay the millisecond a playable source is
/// verified, instead of waiting for an ordered scrape cascade.
///
/// Usage:
///   final race = StreamProbeRace(onVerifiedBatch: (b) => setState(...));
///   scrapeStream.listen((s) => race.offer(s), onDone: race.close);
///   final src = await race.winner; // null if none alive
class StreamProbeRace {
  /// Injectable probe function (tests stub latencies/dead sources).
  final Future<bool> Function(StreamSource source) probeFn;

  /// Emits batches of newly-verified sources for UI list updates.
  final void Function(List<StreamSource> batch)? onVerifiedBatch;

  /// How long to wait before flushing a verified batch to the UI.
  final Duration batchDelay;

  /// Max simultaneous health probes. Bounded to prevent socket floods.
  /// Budget: 8 concurrent (see project resource budgets — uncapped fan-out
  /// is a RAM bomb on low-end phones).
  static const int maxConcurrentProbes = 8;

  /// Probes queued past [maxConcurrentProbes] when the queue already holds
  /// this many are DROPPED.
  static const int maxQueueDepth = 120;

  final Completer<StreamSource?> _winnerCompleter = Completer<StreamSource?>();
  final List<StreamSource> verifiedSources = [];

  bool _closed = false;

  /// True after [closeDrain]: no new offers accepted, but in-flight probes
  /// keep running until they finish (bounded by [_drainDeadline]).
  bool _draining = false;

  /// Safety net so a hung probe can never block the winner future forever.
  static const Duration _drainDeadline = Duration(seconds: 4);
  Timer? _batchTimer;
  final List<StreamSource> _pendingUiBatch = [];
  int _inFlight = 0;
  final List<StreamSource> _probeQueue = [];

  StreamProbeRace({
    this.probeFn = StreamHealthChecker.isAlive,
    this.onVerifiedBatch,
    this.batchDelay = const Duration(milliseconds: 80),
  });

  /// The first source that passed its health check, or null when [close]
  /// was called with no alive source. Never throws.
  Future<StreamSource?> get winner => _winnerCompleter.future;

  /// Offer a fresh scraped source. Fire-and-forget: probes run in
  /// parallel (bounded by [maxConcurrentProbes]) and never block the
  /// scrape stream. Extra sources wait in a capped queue.
  ///
  /// Probing CONTINUES after the winner so the manual sources list keeps
  /// filling for the user (bounded — 8 concurrent HEADs cost nothing).
  void offer(StreamSource source) {
    if (_closed || _draining) return;
    if (_inFlight >= maxConcurrentProbes) {
      if (_probeQueue.length >= maxQueueDepth) return; // shed load
      _probeQueue.add(source);
      return;
    }
    _launchProbe(source);
  }

  void _launchProbe(StreamSource source) {
    _inFlight++;
    unawaited(_probeAndMaybeWin(source));
  }

  void _onProbeDone() {
    _inFlight--;
    if (_closed) {
      _probeQueue.clear();
      return;
    }
    if (_draining) {
      // Scrape finished: queued sources are stale — drop them, and settle
      // the winner as soon as the last in-flight probe lands.
      _probeQueue.clear();
      if (_inFlight <= 0) close();
      return;
    }
    while (_inFlight < maxConcurrentProbes && _probeQueue.isNotEmpty) {
      _launchProbe(_probeQueue.removeAt(0));
    }
  }

  /// Offer a trusted direct source (e.g. embedded debrid links) that
  /// bypasses the health probe — the winner can fire in ~0ms.
  void offerEmbedded(StreamSource source) {
    if (_closed) return;
    unawaited(_winImmediately(source));
  }

  Future<void> _winImmediately(StreamSource source) async {
    if (_closed) return;
    verifiedSources.add(source);
    if (!_winnerCompleter.isCompleted) {
      _winnerCompleter.complete(source);
    }
    _pendingUiBatch.add(source);
    _batchTimer ??= Timer(batchDelay, _flushUiBatch);
  }

  Future<void> _probeAndMaybeWin(StreamSource source) async {
    bool alive;
    try {
      alive = await probeFn(source);
    } catch (_) {
      alive = false;
    }
    // Record the result BEFORE the drain countdown — _onProbeDone may
    // settle the winner via close() when the last probe lands, and a
    // verified source must never be dropped by that settle.
    if (alive) {
      verifiedSources.add(source);
      if (!_winnerCompleter.isCompleted) {
        _winnerCompleter.complete(source);
      }
      // Batch UI updates so rapid-fire verified sources don't spam setState.
      _pendingUiBatch.add(source);
      _batchTimer ??= Timer(batchDelay, _flushUiBatch);
    } else {
      AppLog.d('[StreamProbeRace] dead source dropped: '
          '${source.name ?? "?"} (${source.addonName})');
    }
    _onProbeDone();
  }

  void _flushUiBatch() {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_pendingUiBatch.isEmpty) return;
    final batch = List<StreamSource>.of(_pendingUiBatch);
    _pendingUiBatch.clear();
    onVerifiedBatch?.call(batch);
  }

  /// Scraping finished (onDone). Flush pending UI batch and settle the
  /// winner future if nothing passed.
  void close() {
    if (_closed) return;
    _closed = true;
    _draining = false;
    _flushUiBatch();
    if (!_winnerCompleter.isCompleted) {
      _winnerCompleter.complete(null); // no alive source found
    }
  }

  /// Scrape-done path (use this on `onDone`, NOT [close]).
  ///
  /// Stops accepting NEW offers but lets already-running probes finish, so
  /// a source verified a millisecond after the last scrape event still wins
  /// instead of being dropped (the old close-drop bug). Settles via [close]
  /// once in-flight probes land, or after [_drainDeadline] — whichever first.
  void closeDrain() {
    if (_closed || _draining) return;
    _draining = true;
    if (_inFlight <= 0) {
      close();
      return;
    }
    Timer(_drainDeadline, () {
      if (!_closed) close(); // hung probe safety net
    });
  }

  /// Stop everything immediately (route disposed). Pending probes are
  /// ignored on completion via the `_closed` flag.
  void dispose() {
    close();
  }
}
