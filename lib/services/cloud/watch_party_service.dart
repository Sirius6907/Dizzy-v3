import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  static String generateRoomId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String hashPass(String pass) =>
      sha256.convert(utf8.encode(pass.trim())).toString();

  static bool validPass(String pass) => RegExp(r'^\d{6}$').hasMatch(pass.trim());

  static Future<WatchPartyRoom?> createRoom({
    required String title,
    required String? mediaRef,
    required bool isPrivate,
    String? pass,
  }) async {
    if (!isAvailable || (isPrivate && !validPass(pass ?? ''))) return null;
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
        'status': 'lobby',
      }).select().single();
      // Host also becomes a member through secure RPC (pass hash valid).
      await CloudClient.db.rpc('join_watch_room', params: {
        'p_room_id': id,
        'p_pass_hash': isPrivate ? hashPass(pass!) : null,
      });
      final room = WatchPartyRoom.fromJson(Map<String, dynamic>.from(row));
      await connect(room);
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
    if (id.length != 6) return null;
    try {
      final ok = await CloudClient.db.rpc('join_watch_room', params: {
        'p_room_id': id,
        'p_pass_hash': (pass?.isNotEmpty ?? false) ? hashPass(pass!) : null,
      });
      if (ok != true) return null;
      final row = await CloudClient.db.from('rooms').select().eq('room_id', id).single();
      final room = WatchPartyRoom.fromJson(Map<String, dynamic>.from(row));
      await connect(room);
      return room;
    } catch (e) {
      debugPrint('[WatchParty] join failed (soft): $e');
      return null;
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

  const WatchPartyRoom({
    required this.roomId,
    required this.title,
    required this.mediaRef,
    required this.isPrivate,
    required this.status,
  });

  factory WatchPartyRoom.fromJson(Map<String, dynamic> json) => WatchPartyRoom(
        roomId: json['room_id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Watch Party',
        mediaRef: json['media_ref']?.toString(),
        isPrivate: json['visibility']?.toString() == 'private',
        status: json['status']?.toString() ?? 'lobby',
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
