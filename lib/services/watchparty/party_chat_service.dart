import 'package:flutter/foundation.dart';

import '../cloud/cloud_client.dart';
import 'party_voice_service.dart';

/// WP-P4: room chat + moderation over Supabase.
///
/// Writes go through the `send_room_message` RPC (membership + 500-char
/// cap + 1msg/2s enforced server-side). Reads are members-only by RLS.
/// Chat is ephemeral: room close wipes it, clients hide >24h stragglers.
class PartyChatService {
  static const maxBodyLength = 500;
  static const ttlHours = 24;

  /// Pure: client-side pre-check (server re-validates). Unit tested.
  static bool validBody(String body) {
    final t = body.trim();
    return t.isNotEmpty && t.length <= maxBodyLength;
  }

  /// Pure: hide messages older than the TTL. Unit tested.
  static bool isExpired(DateTime createdAt, {DateTime? now}) {
    final ref = (now ?? DateTime.now()).toUtc();
    return ref.difference(createdAt.toUtc()).inHours >= ttlHours;
  }

  static Future<bool> sendMessage(String roomId, String body) async {
    if (!CloudClient.isReady || !validBody(body)) return false;
    try {
      final ok = await CloudClient.db.rpc('send_room_message', params: {
        'p_room_id': roomId.trim().toUpperCase(),
        'p_body': body.trim(),
      });
      return ok == true;
    } catch (e) {
      debugPrint('[Chat] send failed (soft): $e');
      return false;
    }
  }

  /// Live message feed, oldest-first, TTL-filtered.
  static Stream<List<PartyChatMessage>> watchMessages(String roomId) {
    if (!CloudClient.isReady) return const Stream.empty();
    return CloudClient.db
        .from('room_messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId.trim().toUpperCase())
        .order('created_at', ascending: true)
        .map((rows) => rows
            .map((r) => PartyChatMessage.fromJson(
                Map<String, dynamic>.from(r as Map)))
            .where((m) => !isExpired(m.createdAt))
            .toList());
  }

  /// Members with display codes (device code when the install row exists).
  static Future<List<PartyMember>> listMembers(String roomId) async {
    if (!CloudClient.isReady) return const [];
    try {
      final code = roomId.trim().toUpperCase();
      final members = await CloudClient.db
          .from('room_members')
          .select('user_id, role')
          .eq('room_id', code);
      final installs = await CloudClient.db
          .from('installs')
          .select('owner_user_id, device_code');
      final codeByUser = <String, String>{};
      for (final row in (installs as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final uid = m['owner_user_id']?.toString();
        final dc = m['device_code']?.toString();
        if (uid != null && dc != null && dc.isNotEmpty) codeByUser[uid] = dc;
      }
      return (members as List).map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        final uid = m['user_id']?.toString() ?? '';
        return PartyMember(
          userId: uid,
          role: m['role']?.toString() ?? 'member',
          deviceCode: codeByUser[uid],
        );
      }).toList();
    } catch (e) {
      debugPrint('[Chat] members failed (soft): $e');
      return const [];
    }
  }

  /// Host-only: lock/unlock new joins (existing members unaffected).
  static Future<bool> setLocked(String roomId, bool locked) async {
    if (!CloudClient.isReady) return false;
    try {
      await CloudClient.db.from('rooms').update({'locked': locked}).eq(
          'room_id', roomId.trim().toUpperCase());
      return true;
    } catch (e) {
      debugPrint('[Chat] lock failed (soft): $e');
      return false;
    }
  }

  /// Host-only: kick = LiveKit remove + membership delete (RLS host policy).
  static Future<bool> kickMember(String roomId, String userId) async {
    if (!CloudClient.isReady || !PartyVoiceService.amHost) return false;
    final code = roomId.trim().toUpperCase();
    try {
      await CloudClient.db.functions.invoke('party-voice-admin', body: {
        'room_code': code,
        'action': 'kick',
        'target_identity': userId,
      });
    } catch (e) {
      debugPrint('[Chat] voice kick failed (soft): $e');
    }
    try {
      await CloudClient.db.from('room_members').delete().match(
          {'room_id': code, 'user_id': userId});
      return true;
    } catch (e) {
      debugPrint('[Chat] kick failed (soft): $e');
      return false;
    }
  }
}

class PartyChatMessage {
  final String id;
  final String senderId;
  final String? senderCode;
  final String body;
  final DateTime createdAt;

  const PartyChatMessage({
    required this.id,
    required this.senderId,
    required this.senderCode,
    required this.body,
    required this.createdAt,
  });

  factory PartyChatMessage.fromJson(Map<String, dynamic> json) =>
      PartyChatMessage(
        id: json['id']?.toString() ?? '',
        senderId: json['sender_id']?.toString() ?? '',
        senderCode: json['sender_code']?.toString(),
        body: json['body']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  /// Introvert-friendly display: device code, never raw uuid.
  String get displayName => senderCode != null && senderCode!.isNotEmpty
      ? 'DIZ-$senderCode'
      : 'Guest';
}

class PartyMember {
  final String userId;
  final String role;
  final String? deviceCode;

  const PartyMember({
    required this.userId,
    required this.role,
    required this.deviceCode,
  });

  bool get isHost => role == 'host';

  String get displayName => deviceCode != null && deviceCode!.isNotEmpty
      ? 'DIZ-$deviceCode'
      : 'Guest';
}
