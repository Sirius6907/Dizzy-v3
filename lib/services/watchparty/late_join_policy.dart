/// F4 — arriving late to a film already in progress.
///
/// The promise: you tap the code, and you land **where everyone else is**,
/// not at 0:00 with thirty people waiting. The math is P4's, not ours —
/// this file only decides the two things the transport does not: whether
/// to seek at all, and what to say while we do it.
///
/// Pure, so "late-join catch-up" is testable without a player.
library;

import 'guest_auto_open.dart';
import 'watch_sync_engine.dart';

/// What a late guest should do on arrival.
class LateJoinPlan {
  /// Where to seek, in milliseconds. `null` = already close enough, do not
  /// move the bar under someone who is watching.
  final int? seekMs;

  /// Play or pause, or `null` to leave whatever the player is doing.
  final bool? play;

  /// True when the guest is far enough behind to deserve the "catching
  /// up" line instead of a silent jump.
  final bool showCatchingUp;

  /// What the guest is joining, for the header.
  final String? title;

  const LateJoinPlan({
    this.seekMs,
    this.play,
    this.showCatchingUp = false,
    this.title,
  });

  /// True when the guest should just watch, not move.
  bool get alreadyInSync => seekMs == null;
}

abstract final class LateJoinPolicy {
  /// A guest further behind than this gets the "catching up" line. Below
  /// it, the seek is quiet — a bar that twitches for half a second looks
  /// like a glitch, and people report those as bugs.
  static const catchingUpMs = WatchSyncEngine.toastThresholdMs;

  /// The plan for a guest who just walked into a room.
  ///
  /// Reuses the P4 resync math ([GuestAutoOpen.initialPositionFor] and
  /// [WatchSyncEngine.resyncPosition]) rather than re-deriving it: two
  /// implementations of "where is the host" is how a room ends up with
  /// two different answers.
  static LateJoinPlan planFor(
    WatchSyncMessage msg, {
    int guestPositionMs = 0,
    bool guestPlaying = false,
    int? nowMs,
  }) {
    final target = GuestAutoOpen.initialPositionFor(msg, nowMs: nowMs);
    final seek = WatchSyncEngine.resyncPosition(
      guestPositionMs: guestPositionMs,
      targetPositionMs: target.inMilliseconds,
    );
    final play = msg.playing == guestPlaying ? null : msg.playing;
    final behind = target.inMilliseconds - guestPositionMs;
    return LateJoinPlan(
      seekMs: seek,
      play: play,
      showCatchingUp: behind.abs() > catchingUpMs,
      title: msg.mediaTitle,
    );
  }

  /// A room that has not started yet. The guest joins, the host is still
  /// choosing — no seek, no "catching up", just an honest "they are
  /// picking now".
  static LateJoinPlan planForIdleRoom() => const LateJoinPlan(
        seekMs: 0,
        play: false,
        showCatchingUp: false,
        title: null,
      );

  /// The one line the guest sees. Easy English, never a number, never a
  /// code, never a word about packets.
  static String arrivalLine(LateJoinPlan plan, {required int memberCount}) {
    if (plan.title == null || plan.title!.isEmpty) {
      return memberCount > 1
          ? 'You are in. They are picking what to play.'
          : 'You are in. Pick something to play.';
    }
    if (plan.showCatchingUp) {
      return 'Jumping you to where ${plan.title} is right now.';
    }
    return 'You are in. Watching ${plan.title}.';
  }
}
