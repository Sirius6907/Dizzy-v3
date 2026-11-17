/// Sanity rules for the duration the player reports.
///
/// A broken/unknown stream (or a container whose timestamps are garbage) can
/// report a duration that has nothing to do with the media. The UI then shows
/// a nonsense countdown — the user-visible case was `-1:56:19` as
/// "remaining" three seconds after a fresh open — and, worse, the failover
/// policy treats "duration > 0" as proof of a healthy stream, so a dead
/// source keeps its error suppression and never fails over.
///
/// Everything that consumes a duration (remaining-time label, seek bar,
/// progress saving, resume-after-failover, open-on-tail guard) must go
/// through [trusted] first.
library;

abstract final class PlaybackDurationGuard {
  /// No real title runs longer than this; beyond it the value is garbage.
  static const Duration maxPlausible = Duration(hours: 24);

  /// Shorter than this cannot be a real title (mpv reports sub-second
  /// placeholders while probing the demuxer).
  static const Duration minPlausible = Duration(seconds: 2);

  /// Returns [d] when it can be trusted, else null (= "duration unknown").
  ///
  /// [reference] is the catalog runtime (movies only). When provided, a
  /// reported duration that is wildly longer or shorter than the known
  /// runtime is treated as bogus too — that is how a wrong file or a
  /// mangled container slips through the plain bounds check.
  static Duration? trusted(Duration? d, {Duration? reference}) {
    if (d == null) return null;
    if (d < minPlausible || d > maxPlausible) return null;
    if (reference != null && reference >= minPlausible) {
      // Movies run close to their catalog runtime; allow credits/extra cuts
      // but not a different title and not half of one.
      final upper = reference + const Duration(minutes: 30);
      final upperRatio = reference * 1.35;
      final hardUpper = upper > upperRatio ? upper : upperRatio;
      if (d > hardUpper) return null;
      if (d < reference * 0.5) return null;
    }
    return d;
  }

  /// Remaining time for display: never negative, null when unknown.
  static Duration? remaining(Duration position, Duration? duration) {
    if (duration == null) return null;
    final left = duration - position;
    if (left <= Duration.zero) return Duration.zero;
    return left;
  }

  /// True when playback has genuinely advanced (not just "position > 0" after
  /// an open that decoded one frame). Used to decide whether a source gets
  /// error suppression and whether a resume position may be carried over.
  static bool hasRealProgress(Duration furthestPosition) =>
      furthestPosition >= const Duration(seconds: 3);
}
