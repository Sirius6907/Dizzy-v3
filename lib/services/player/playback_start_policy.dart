/// Resume-position safety for the player.
///
/// A stored or carried-over position near the end is worse than no resume at
/// all: the player opens on a black final frame and looks frozen. The emulator
/// reproduced exactly that after a codec failure — failover carried the dead
/// source's end-of-file position into the next source.
abstract final class PlaybackStartPolicy {
  /// Positions this close to the end are treated as "finished", not resume.
  static const Duration tailWindow = Duration(seconds: 30);

  /// The last 5% counts as the tail even in very long media.
  static const double tailFraction = 0.95;

  /// Media shorter than this is a clip; looping it back to zero would be
  /// worse than leaving it alone.
  static const Duration minGuardedDuration = Duration(seconds: 60);

  /// Returns [start] when it is a safe resume point, otherwise null (= 0:00).
  static Duration? sanitize(Duration? start, {Duration? duration}) {
    if (start == null || start <= Duration.zero) return null;
    if (duration == null || duration <= Duration.zero) return start;
    if (duration < minGuardedDuration) return start;
    if (start >= duration) return null;
    if (((duration - start) <= tailWindow) ||
        (start > duration * tailFraction)) {
      return null;
    }
    return start;
  }

  /// Failover must not inherit a position from a source that never played.
  static Duration? resumeAfterFailover({
    required Duration position,
    required bool confirmedPlayback,
    Duration? duration,
  }) {
    if (!confirmedPlayback) return null;
    return sanitize(position, duration: duration);
  }

  /// True when [position] sits in the closing tail of [duration].
  static bool isAtTail(Duration position, Duration duration) {
    if (duration < minGuardedDuration) return false;
    if (position <= Duration.zero) return false;
    if (position >= duration) return true;
    return (duration - position) <= tailWindow ||
        position > duration * tailFraction;
  }
}
