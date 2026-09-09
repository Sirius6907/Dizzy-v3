import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../cloud/cloud_client.dart';
import '../device/device_id_service.dart';

/// WP-P3: Discord-style voice for watch parties over LiveKit Cloud.
///
/// 1 Supabase room = 1 LiveKit room (same 6-char code).
/// Join-muted by default; tap to speak. Host gets mute-all via the
/// `party-voice-admin` edge function (API secret never leaves the server).
class PartyVoiceService {
  static Room? _room;
  static EventsListener<RoomEvent>? _listener;

  static final ValueNotifier<bool> connected = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> micOn = ValueNotifier<bool>(false);
  static final ValueNotifier<Set<String>> speakingIds =
      ValueNotifier<Set<String>>(<String>{});
  static final ValueNotifier<int> memberCount = ValueNotifier<int>(0);
  static bool amHost = false;
  static String? currentRoomCode;

  /// Pure: token-request payload. Unit tested.
  static Map<String, dynamic> buildTokenRequest(
      String roomCode, String deviceCode, bool isHost) {
    return {
      'room_code': roomCode.trim().toUpperCase(),
      'device_code': deviceCode,
      'wants_publish': isHost,
    };
  }

  /// Pure: LiveKit grant shape the edge function must return for this role.
  static Map<String, bool> grantsFor(bool isHost) => {
        'roomJoin': true,
        'canPublish': isHost,
        'canSubscribe': true,
        'canPublishData': true,
      };

  static Future<bool> join({required String roomCode, bool asHost = false}) async {
    if (!CloudClient.isReady) return false;
    await leave();
    try {
      final code = roomCode.trim().toUpperCase();
      final device = DeviceIdService.deviceCode.value ?? 'unknown';
      debugPrint('[Voice] token req: ${buildTokenRequest(code, device, asHost)}');
      final res = await CloudClient.db.functions.invoke(
        'mint-livekit-token',
        body: {'room_code': code},
      );
      final data = res.data;
      final Map<String, dynamic> json =
          data is Map ? Map<String, dynamic>.from(data) : {};
      final token = json['token']?.toString() ?? '';
      final url = json['url']?.toString() ?? '';
      if (token.isEmpty || url.isEmpty) return false;

      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      _listener = room.createListener();
      final listener = _listener;
      if (listener == null) {
        try {
          await room.dispose();
        } catch (_) {}
        return false;
      }
      listener.on<ActiveSpeakersChangedEvent>((e) {
        speakingIds.value = e.speakers.map((p) => p.identity).toSet();
      });
      listener.on<ParticipantConnectedEvent>((_) => _refreshCount(room));
      listener.on<ParticipantDisconnectedEvent>((_) => _refreshCount(room));
      listener.on<TrackMutedEvent>((_) => _refreshCount(room));
      listener.on<TrackUnmutedEvent>((_) => _refreshCount(room));
      listener.on<RoomDisconnectedEvent>((_) {
        connected.value = false;
        micOn.value = false;
        speakingIds.value = <String>{};
      });

      await room.connect(url, token);
      // Join-muted: never auto-publish. Tap mic to speak.
      _room = room;
      amHost = json['is_host'] == true || asHost;
      currentRoomCode = code;
      connected.value = true;
      micOn.value = false;
      _refreshCount(room);
      return true;
    } catch (e) {
      debugPrint('[Voice] join failed (soft): $e');
      await leave();
      return false;
    }
  }

  static void _refreshCount(Room room) {
    try {
      memberCount.value = room.remoteParticipants.length + 1;
    } catch (_) {}
  }

  static Future<void> toggleMic() async =>
      setMicEnabled(!micOn.value);

  static Future<void> setMicEnabled(bool enabled) async {
    final room = _room;
    if (room == null || !connected.value) return;
    try {
      await room.localParticipant?.setMicrophoneEnabled(enabled);
      micOn.value = enabled;
    } catch (e) {
      debugPrint('[Voice] mic toggle failed (soft): $e');
    }
  }

  /// Host-only: server-mutes every other publisher.
  static Future<bool> muteAll() async {
    final code = currentRoomCode;
    if (!amHost || code == null || !CloudClient.isReady) return false;
    try {
      final res = await CloudClient.db.functions.invoke(
        'party-voice-admin',
        body: {'room_code': code, 'action': 'mute_all'},
      );
      return (res.data as Map?)?['ok'] == true;
    } catch (e) {
      debugPrint('[Voice] mute-all failed (soft): $e');
      return false;
    }
  }

  static Future<void> leave() async {
    final room = _room;
    _room = null;
    try {
      await _listener?.cancelAll();
    } catch (_) {}
    _listener = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
    connected.value = false;
    micOn.value = false;
    speakingIds.value = <String>{};
    memberCount.value = 0;
    amHost = false;
    currentRoomCode = null;
  }
}
