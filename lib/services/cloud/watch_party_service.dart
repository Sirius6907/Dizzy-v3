import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../profiles/dizzy_profile_service.dart';
import 'cloud_client.dart';

/// S3C (v1.1.9): Watch Party room + Realtime Broadcast control plane.
/// No media bytes/URLs are sent to Supabase — only media IDs and playback
/// control events. Works with anonymous sessions (device-local identity).
class WatchPartyService {
  static RealtimeChannel? _channel;
  static StreamController<WatchPartyEvent>? _events;

  static bool get isAvailable {
    if (!CloudClient.isReady) return false;
    return CloudClient.db.auth.currentUser != null;
  }

  static Stream<WatchPartyEvent> get events =>
      (_events ??= StreamController<WatchPartyEvent>.broadcast()).stream;

  // ── WP-P1b: 18+ age gate (local) + kids hard-exclude ──
  static const keyAdultUnlock = 'wp_adult_unlocked_v1';
  static final ValueNotifier<bool> adultUnlocked = ValueNotifier<bool>(false);

  /// True when the active profile is a kids profile (zero 18+ everywhere).
  static bool get isKidsProfile =>
      DizzyProfileService.active?.isKids ?? false;

  static Future<void> loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      adultUnlocked.value = prefs.getBool(keyAdultUnlock) ?? false;
    } catch (_) {}
  }

  /// Only callable by an explicit "I am 18+" confirm; never for kids.
  static Future<void> setAdultUnlocked(bool value) async {
    if (value && isKidsProfile) return;
    adultUnlocked.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyAdultUnlock, value);
    } catch (_) {}
  }

  /// Layer 1+2 detector: TMDB adult flag, title keywords, host declaration.
  /// Pure — unit tested. Genre blocklist rides in [blockedGenreIds].
  static bool isAdultContent({
    bool tmdbAdult = false,
    List<int> genreIds = const [],
    List<int> blockedGenreIds = const [],
    String title = '',
    bool hostDeclared = false,
  }) {
    if (tmdbAdult || hostDeclared) return true;
    if (genreIds.any(blockedGenreIds.contains)) return true;
    final t = title.toLowerCase();
    const keywords = [
      'xxx', 'porn', 'erotic', 'uncensored', 'hentai',
      'blue film', 'adults only', 'pornographic',
    ];
    return keywords.any(t.contains);
  }

  static String generateRoomId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// WP-P5: v1 room size. Server enforces in join_watch_room; this is the
  /// client mirror for "Full" labels. Unit tested.
  static const int maxMembers = 20;
  static bool isFull(int memberCount) => memberCount >= maxMembers;

  static String hashPass(String pass) =>
      sha256.convert(utf8.encode(pass.trim())).toString();

  static bool validPass(String pass) => RegExp(r'^\d{6}$').hasMatch(pass.trim());

  /// 6-char room code from the unambiguous alphabet (no 0/O/1/I/L).
  static bool validRoomId(String id) =>
      RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$')
          .hasMatch(id.trim().toUpperCase());

  static Future<WatchPartyRoom?> createRoom({
    required String title,
    required String? mediaRef,
    required bool isPrivate,
    String? pass,
    bool isAdult = false,
  }) async {
    if (!isAvailable || (isPrivate && !validPass(pass ?? ''))) return null;
    // WP-P2 mandatory-playback gate: no media attached = no room.
    // (Player auto-prefill lands in WP-P2b; until then the dialog collects it.)
    if (mediaRef == null || mediaRef.trim().isEmpty) return null;
    try {
      final uid = CloudClient.db.auth.currentUser!.id;
      final id = generateRoomId();
      final row = await CloudClient.db.from('rooms').insert({
        'room_id': id,
        'host_user_id': uid,
        'title': title.trim().isEmpty ? 'Watch Party' : title.trim(),
        'media_ref': mediaRef,
        'visibility': isPrivate ? 'private' : 'public',
        'pass_hash': isPrivate ? hashPass(pass!) : null,
        'is_adult': isAdult || isAdultContent(title: title),
        'status': 'lobby',
      }).select().single();
      // Host also becomes a member through secure RPC (pass hash valid).
      await CloudClient.db.rpc('join_watch_room', params: {
        'p_room_id': id,
        'p_pass_hash': isPrivate ? hashPass(pass!) : null,
      });
      final room = WatchPartyRoom.fromJson(Map<String, dynamic>.from(row));
      await connect(room);
      // WP-P5: opportunistic GC — one cheap call keeps the lobby rot-free.
      // ignore: unawaited_futures
      sweepStale();
      return room;
    } catch (e) {
      debugPrint('[WatchParty] create failed (soft): $e');
      return null;
    }
  }

  static Future<WatchPartyRoom?> joinRoom({
    required String roomId,
    String? pass,
  }) async {
    if (!isAvailable) return null;
    final id = roomId.trim().toUpperCase();
    if (!validRoomId(id)) return null;
    try {
      final ok = await CloudClient.db.rpc('join_watch_room', params: {
        'p_room_id': id,
        'p_pass_hash': (pass?.isNotEmpty ?? false) ? hashPass(pass!) : null,
      });
      if (ok != true) return null;
      final row = await CloudClient.db.from('rooms').select().eq('room_id', id).single();
      final room = WatchPartyRoom.fromJson(Map<String, dynamic>.from(row));
      await connect(room);
      // WP-P5: opportunistic GC — one cheap call keeps the lobby rot-free.
      // ignore: unawaited_futures
      sweepStale();
      return room;
    } catch (e) {
      debugPrint('[WatchParty] join failed (soft): $e');
      return null;
    }
  }

  /// WP-P1: live public lobby. Reads the safe view only — never `rooms`
  /// directly, so pass hashes and host ids can never leak to clients.
  /// WP-P1b: adult excluded by default; kids profiles can never opt in.
  static Future<List<WatchPartyRoom>> listPublicRooms({
    int limit = 50,
    bool showAdult = false,
  }) async {
    if (!isAvailable) return const [];
    final effectiveShowAdult = showAdult && !isKidsProfile;
    try {
      var query = CloudClient.db.from('public_rooms_safe').select();
      if (!effectiveShowAdult) query = query.eq('is_adult', false);
      final rows = await query
          .order('member_count', ascending: false)
          .limit(limit.clamp(1, 50));
      return (rows as List)
          .map((r) => WatchPartyRoom.fromJson(Map<String, dynamic>.from(r as Map)))
          .where((r) => r.roomId.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[WatchParty] lobby list failed (soft): $e');
      return const [];
    }
  }

  /// WP-P1b: report a room. 3+ reports auto-hides it server-side (safe view).
  static Future<bool> reportRoom(String roomId) async {
    if (!isAvailable || !validRoomId(roomId)) return false;
    try {
      await CloudClient.db.from('room_reports').insert({
        'room_id': roomId.trim().toUpperCase(),
        'reporter_id': CloudClient.db.auth.currentUser!.id,
      });
      return true;
    } catch (e) {
      debugPrint('[WatchParty] report failed (soft): $e');
      return false;
    }
  }

  /// WP-P5: fire-and-forget stale-room sweep (server closes rotting rooms).
  static Future<void> sweepStale() async {
    if (!isAvailable) return;
    try {
      await CloudClient.db.rpc('sweep_stale_rooms');
    } catch (e) {
      debugPrint('[WatchParty] sweep failed (soft): $e');
    }
  }

  /// WP-P5: heartbeat for presence pruning input. Cheap, soft-fail.
  static Future<void> touchMembership(String roomId) async {
    if (!isAvailable) return;
    try {
      await CloudClient.db.rpc('touch_membership', params: {
        'p_room_id': roomId.trim().toUpperCase(),
      });
    } catch (e) {
      debugPrint('[WatchParty] touch failed (soft): $e');
    }
  }

  static Future<void> connect(WatchPartyRoom room) async {
    if (!isAvailable) return;
    await disconnect();
    _channel = CloudClient.db.channel('watch-party:${room.roomId}');
    _channel!
        .onBroadcast(
          event: 'control',
          callback: (payload) => _events?.add(WatchPartyEvent.fromJson(payload)),
        )
        .subscribe();
  }

  static Future<void> sendControl({
    required String type, // play | pause | seek | chat
    int? positionMs,
    String? text,
  }) async {
    final channel = _channel;
    if (channel == null || !isAvailable) return;
    final event = WatchPartyEvent(
      type: type,
      positionMs: positionMs,
      text: text,
      sentAt: DateTime.now(),
    );
    await channel.sendBroadcastMessage(
      event: 'control',
      payload: event.toJson(),
    );
  }

  static Future<void> leaveRoom(String roomId) async {
    try {
      if (isAvailable) {
        await CloudClient.db
            .from('room_members')
            .delete()
            .match({'room_id': roomId, 'user_id': CloudClient.db.auth.currentUser!.id});
      }
    } catch (_) {}
    await disconnect();
  }

  static Future<void> closeRoom(String roomId) async {
    try {
      if (isAvailable) {
        await CloudClient.db
            .from('rooms')
            .update({'status': 'closed'})
            .eq('room_id', roomId);
      }
    } catch (_) {}
    await disconnect();
  }

  static Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    if (channel != null && CloudClient.isReady) {
      await CloudClient.db.removeChannel(channel);
    }
  }
}

class WatchPartyRoom {
  final String roomId;
  final String title;
  final String? mediaRef;
  final bool isPrivate;
  final String status;
  final int memberCount;
  final bool isAdult;

  const WatchPartyRoom({
    required this.roomId,
    required this.title,
    required this.mediaRef,
    required this.isPrivate,
    required this.status,
    this.memberCount = 0,
    this.isAdult = false,
  });

  factory WatchPartyRoom.fromJson(Map<String, dynamic> json) => WatchPartyRoom(
        roomId: json['room_id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Watch Party',
        mediaRef: json['media_ref']?.toString(),
        isPrivate: json['visibility']?.toString() == 'private',
        status: json['status']?.toString() ?? 'lobby',
        memberCount: int.tryParse(json['member_count']?.toString() ?? '') ?? 0,
        isAdult: json['is_adult'] == true,
      );
}

class WatchPartyEvent {
  final String type;
  final int? positionMs;
  final String? text;
  final DateTime sentAt;

  const WatchPartyEvent({
    required this.type,
    this.positionMs,
    this.text,
    required this.sentAt,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'position_ms': positionMs,
        'text': text,
        'sent_at': sentAt.toUtc().toIso8601String(),
      };

  factory WatchPartyEvent.fromJson(Map<String, dynamic> json) => WatchPartyEvent(
        type: json['type']?.toString() ?? 'unknown',
        positionMs: json['position_ms'] is int
            ? json['position_ms'] as int
            : int.tryParse(json['position_ms']?.toString() ?? ''),
        text: json['text']?.toString(),
        sentAt: DateTime.tryParse(json['sent_at']?.toString() ?? '') ?? DateTime.now(),
      );
}
