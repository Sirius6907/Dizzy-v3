
import '../cloud/cloud_client.dart';
import 'party_voice_service.dart';
import '../errors/app_log.dart';

/// WP-P4: room chat + moderation over Supabase.
///
/// Writes go through the `send_room_message` RPC (membership + 500-char
/// cap + 1msg/2s enforced server-side). Reads are members-only by RLS.
/// Chat is ephemeral: room close wipes it, clients hide >24h stragglers.
class PartyChatService {
  static const maxBodyLength = 500;
  static const ttlHours = 24;

  /// P11: the only reactions that exist (server enforces the same list).
  static const allowedEmoji = ['❤️', '😂', '😮', '😢', '😡', '👍', '👏', '🎉'];

  /// Pure: client-side pre-check (server re-validates). Unit tested.
  static bool validBody(String body) {
    final t = body.trim();
    return t.isNotEmpty && t.length <= maxBodyLength;
  }

  /// Pure: reaction jsonb → emoji → count. Accepts {emoji:[uids]} (server
  /// shape) and {emoji:int} (forgiving). Garbage → empty. Unit tested.
  static Map<String, int> parseReactions(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    for (final e in raw.entries) {
      final key = e.key?.toString() ?? '';
      if (key.isEmpty || key.length > 8) continue;
      final v = e.value;
      if (v is List) {
        if (v.isNotEmpty) out[key] = v.length;
      } else if (v is int && v > 0) {
        out[key] = v;
      }
    }
    return out;
  }

  static Future<bool> sendMessage(String roomId, String body,
      {String? replyToId}) async {
    if (!CloudClient.isReady || !validBody(body)) return false;
    try {
      final params = <String, dynamic>{
        'p_room_id': roomId.trim().toUpperCase(),
        'p_body': body.trim(),
      };
      if (replyToId != null && replyToId.isNotEmpty) {
        params['p_reply_to_id'] = replyToId;
      }
      final ok =
          await CloudClient.db.rpc('send_room_message', params: params);
      return ok == true;
    } catch (e) {
      AppLog.d('[Chat] send failed (soft): $e');
      return false;
    }
  }

  /// P11: toggle one reaction (server flips caller in/out). Fail-soft.
  static Future<bool> toggleReaction(String messageId, String emoji) async {
    if (!CloudClient.isReady || !allowedEmoji.contains(emoji)) return false;
    try {
      final ok = await CloudClient.db.rpc('react_to_message', params: {
        'p_msg_id': messageId,
        'p_emoji': emoji,
      });
      return ok == true;
    } catch (e) {
      AppLog.d('[Chat] react failed (soft): $e');
      return false;
    }
  }

  /// P11: host pins ([messageId]) or unpins (null). Fail-soft.
  static Future<bool> setPinned(String roomId, String? messageId) async {
    if (!CloudClient.isReady) return false;
    try {
      final ok = await CloudClient.db.rpc('pin_room_message', params: {
        'p_room_id': roomId.trim().toUpperCase(),
        'p_msg_id': messageId,
      });
      return ok == true;
    } catch (e) {
      AppLog.d('[Chat] pin failed (soft): $e');
      return false;
    }
  }

  /// P11: live pin banner (null = nothing pinned). Members-only via RLS.
  static Stream<String?> watchPinned(String roomId) {
    if (!CloudClient.isReady) return const Stream.empty();
    return CloudClient.db
        .from('rooms')
        .stream(primaryKey: ['room_id'])
        .eq('room_id', roomId.trim().toUpperCase())
        .map((rows) {
      if (rows.isEmpty) return null;
      final t =
          (rows.first as Map)['pinned_text']?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    });
  }

  /// Pure: hide messages older than the TTL. Unit tested.
  static bool isExpired(DateTime createdAt, {DateTime? now}) {
    final ref = (now ?? DateTime.now()).toUtc();
    return ref.difference(createdAt.toUtc()).inHours >= ttlHours;
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
      AppLog.d('[Chat] members failed (soft): $e');
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
      AppLog.d('[Chat] lock failed (soft): $e');
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
      AppLog.d('[Chat] voice kick failed (soft): $e');
    }
    try {
      await CloudClient.db.from('room_members').delete().match(
          {'room_id': code, 'user_id': userId});
      return true;
    } catch (e) {
      AppLog.d('[Chat] kick failed (soft): $e');
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

  /// P11: reply link + server-filled quote (no extra fetch to display).
  final String? replyToId;
  final String? replyPreview;
  final String? replyToCode;

  /// P11: emoji → count (uid lists never reach the UI).
  final Map<String, int> reactions;

  const PartyChatMessage({
    required this.id,
    required this.senderId,
    required this.senderCode,
    required this.body,
    required this.createdAt,
    this.replyToId,
    this.replyPreview,
    this.replyToCode,
    this.reactions = const {},
  });

  factory PartyChatMessage.fromJson(Map<String, dynamic> json) =>
      PartyChatMessage(
        id: json['id']?.toString() ?? '',
        senderId: json['sender_id']?.toString() ?? '',
        senderCode: json['sender_code']?.toString(),
        body: json['body']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        replyToId: json['reply_to_id']?.toString(),
        replyPreview: json['reply_preview']?.toString(),
        replyToCode: json['reply_to_code']?.toString(),
        reactions: PartyChatService.parseReactions(json['reactions']),
      );

  /// Introvert-friendly display: device code, never raw uuid.
  String get displayName => senderCode != null && senderCode!.isNotEmpty
      ? 'DIZ-$senderCode'
      : 'Guest';

  /// Quote header for a reply ("DIZ-4820193" or "Guest").
  String get replyName =>
      replyToCode != null && replyToCode!.isNotEmpty
          ? 'DIZ-$replyToCode'
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
