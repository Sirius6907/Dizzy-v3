import 'package:flutter/services.dart';

import '../share/native_share.dart';
import 'watch_sync_engine.dart' show WatchSyncMessage;

/// F4 — getting your friends into the room takes one tap.
///
/// The host taps "Invite", the system share sheet opens with the code
/// already in it. That is the whole flow. No room-management screen, no
/// "copy link then paste it into the chat" — a room code that a person
/// has to assemble by hand is a room nobody joins.
///
/// Every share is a fallback chain, never a dead end: the native sheet, then
/// the clipboard, then the text is simply on screen to read out loud.
class RoomInvite {
  final String roomCode;
  final String? pass;
  final String? mediaTitle;
  final String? hostName;

  const RoomInvite({
    required this.roomCode,
    this.pass,
    this.mediaTitle,
    this.hostName,
  });

  /// The Easy English message a friend receives.
  ///
  /// Short on purpose: it is read on a lock screen, in a notification, or
  /// read aloud. The code comes first so it survives truncation.
  String get message {
    final title = (mediaTitle ?? '').trim();
    final who = (hostName ?? '').trim();
    final buf = StringBuffer();
    buf.write('Join my room on Dizzy');
    if (title.isNotEmpty) buf.write(' — $title');
    buf.write('. Code: $roomCode');
    if (pass != null && pass!.isNotEmpty) buf.write('  Pass: $pass');
    if (who.isNotEmpty) buf.write('\n$who is watching now.');
    return buf.toString();
  }

  /// The shortest thing that still works: just the code, for a person
  /// typing it in by hand across the room.
  String get spokenLine => 'Room code is $roomCode.';
}

/// How an invite left the device. The UI shows nothing extra — this exists
/// so the flow can be tested and so a failed share is never silent.
enum ShareResult { sheet, clipboard, failed }

abstract final class RoomInviteService {
  /// Share [invite]. Tries the native sheet, then the clipboard.
  ///
  /// Never throws: a person who cannot share still has the code on
  /// screen, and telling them "share failed" would be a lie about a
  /// non-event.
  static Future<ShareResult> share(RoomInvite invite) async {
    final text = invite.message;
    if (text.isEmpty) return ShareResult.failed;

    if (await NativeShare.shareText(text)) return ShareResult.sheet;

    try {
      await Clipboard.setData(ClipboardData(text: text));
      return ShareResult.clipboard;
    } catch (_) {
      return ShareResult.failed;
    }
  }

  /// The line shown after a share. Easy English, no jargon.
  static String resultLine(ShareResult result) => switch (result) {
        ShareResult.sheet => 'Sent. They just tap the code.',
        ShareResult.clipboard => 'Copied. Send it any way you like.',
        ShareResult.failed => 'Code is on screen. Read it out loud.',
      };
}

/// F4 — "they just opened it": what a guest should do the moment a room
/// code lands, with no tapping beyond the code itself.
///
/// Host auto-open is P4's [GuestAutoOpen]; this is the small piece that
/// turns a code into a decision, so the "it just works" feeling is a
/// tested function rather than a hope.
class GuestAutoOpenDecision {
  /// Open straight away — no "are you sure?" screen in between.
  final bool openNow;

  /// Prewarm the title before the player is ready, so arrival feels
  /// instant rather than slow.
  final bool prewarm;

  /// What to tell the guest. `null` when the open is self-evident.
  final String? line;

  const GuestAutoOpenDecision({
    required this.openNow,
    required this.prewarm,
    this.line,
  });
}

abstract final class GuestAutoOpenPolicy {
  /// A room with a lock wants the pass before it opens — asking for a
  /// 6-digit code up front is the one prompt we do not skip.
  static GuestAutoOpenDecision decide({
    required String roomCode,
    required String? pass,
    required bool hasMedia,
  }) {
    final code = roomCode.trim().toUpperCase();
    if (code.isEmpty) {
      return const GuestAutoOpenDecision(
        openNow: false,
        prewarm: false,
        line: 'That code looks wrong. Check it and try again.',
      );
    }
    final needsPass = pass != null && pass.isNotEmpty;
    if (needsPass) {
      return const GuestAutoOpenDecision(
        openNow: false,
        prewarm: false,
        line: 'This room has a pass. Type it to come in.',
      );
    }
    return GuestAutoOpenDecision(
      openNow: true,
      prewarm: hasMedia,
      line: hasMedia ? 'Joining now...' : null,
    );
  }

  /// A guest who has been in the room already does not re-announce: a
  /// late heartbeat must not steal the screen.
  static bool shouldAnnounce(WatchSyncMessage msg, {required bool alreadyInRoom}) {
    if (alreadyInRoom) return false;
    return msg.mediaRef.trim().isNotEmpty;
  }
}
