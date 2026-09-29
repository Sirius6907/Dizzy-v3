/// F1 — Instant-Play gate: what plays first, and what plays next.
///
/// Two decisions the player used to hand-roll inline, both of which are
/// pure and therefore belong in one testable place:
///
///  1. **First valid source wins.** The instant a *playable* source is
///     verified it opens with autoplay — no "choose a server" step in
///     between. The manual picker stays available inside the player, but it
///     never gates the first playback.
///  2. **Failover advance.** A dead source moves to the next-ranked one,
///     silently, up to a bounded number of switches; then the picker takes
///     over. The user only ever sees one Easy-English line.
///
/// No Flutter import: this is decision logic, and the player widget owns
/// mpv. Nothing here touches the network or mpv.
library;

import '../../models/stream/stream_model.dart';
import '../errors/app_log.dart';
import 'source_ranker.dart';

/// The single line a user sees when a source dies and we move on.
/// Easy English by law: no codec names, no URLs, no stack traces.
const String kTryingNextSourceMessage = 'Trying next source…';

/// What the gate decided for a candidate source.
enum InstantPlayDecision {
  /// Nothing to do (empty / unplayable source, or autoplay already won).
  ignore,

  /// Open this source now, with autoplay.
  playNow,

  /// Open this source, but stay paused (user paused during the race).
  openPaused,
}

class InstantPlayGate {
  /// Auto-switches before the picker takes over. Mirrors the player's
  /// previous inline cap; kept here so the number has one home.
  static const int defaultMaxSwitches = 3;

  /// True when [source] is a real, playable candidate — it has a URL, or
  /// an infoHash we can turn into a magnet. Everything else is a listing
  /// entry, not a video, and must never win the race.
  static bool isValidCandidate(StreamSource source) =>
      source.magnetUrl != null ||
      (source.url != null && source.url!.trim().isNotEmpty);

  /// Whether autoplay is on right now. Read live so flipping the setting
  /// mid-resolve takes effect without rebuilding the gate.
  final bool Function() autoplayEnabled;

  /// Auto-skip the next source on death. Off ⇒ the picker opens instead.
  final bool Function() autoFailover;

  /// Auto-switches allowed before the picker takes over.
  final int maxSwitches;

  bool _won = false;
  int _switches = 0;
  final Set<String> _dead = <String>{};

  InstantPlayGate({
    required this.autoplayEnabled,
    required this.autoFailover,
    this.maxSwitches = defaultMaxSwitches,
  });

  /// True once a source has been handed to the player.
  bool get hasPlayed => _won;

  /// Switches spent this session (never re-tried sources don't count).
  int get switches => _switches;

  /// Sources proven dead this session, keyed by fingerprint. Shared with
  /// the ranker so a known-bad addon never climbs back into the chain.
  Set<String> get deadFingerprints => _dead;

  /// Record [source] as dead without advancing (controller errors that
  /// don't trigger a switch still need to poison the chain).
  void markDead(StreamSource source) => _dead.add(_fingerprint(source));

  /// Decide what to do with a freshly verified [source].
  ///
  /// First valid source wins the race; every later source is only a
  /// failover candidate, never an interrupt. Pure decision — the caller
  /// does the opening.
  InstantPlayDecision offer(StreamSource source) {
    if (!autoplayEnabled()) return InstantPlayDecision.ignore;
    if (!isValidCandidate(source)) return InstantPlayDecision.ignore;
    if (_won) return InstantPlayDecision.ignore;
    _won = true;
    return InstantPlayDecision.playNow;
  }

  /// Record that [source] died and pick the replacement.
  ///
  /// Returns the next source to try, or null when we should stop trying
  /// and hand the choice to the user. [chain] must already be ranked
  /// best-first (see `SourceRanker.order`).
  StreamSource? advance({
    required List<StreamSource> chain,
    required StreamSource failed,
  }) {
    markDead(failed);

    if (!autoFailover()) return null;
    if (_switches >= maxSwitches) {
      AppLog.d('[InstantPlay] switch cap reached — picker takes over');
      return null;
    }

    final failedFp = _fingerprint(failed);
    for (final candidate in chain) {
      final fp = _fingerprint(candidate);
      if (fp == failedFp || _dead.contains(fp)) continue;
      _switches++;
      AppLog.d('[InstantPlay] failover switch $_switches/$maxSwitches');
      return candidate;
    }

    AppLog.d('[InstantPlay] no backup source left — picker takes over');
    return null;
  }

  /// Whether [source] already failed this session.
  bool isDead(StreamSource source) => _dead.contains(_fingerprint(source));

  /// Fresh video: forget dead sources, switches, and the win.
  void reset() {
    _won = false;
    _switches = 0;
    _dead.clear();
  }

  static String _fingerprint(StreamSource s) => SourceRanker.fingerprint(s);
}
