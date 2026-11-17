import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../cloud/cloud_client.dart';
import '../errors/app_error_log.dart';
import '../errors/app_log.dart';
import 'dizzy_social_service.dart';

/// A persistent group (chat + Watch Together cards). v1.3.6 Part G2.
class DizzyGroup {
  final String groupId;
  final String name;
  final String ownerId;
  final int memberCount;
  final String? lastMessage;
  final String? lastKind;
  final DateTime? lastMessageAt;

  const DizzyGroup({
    required this.groupId,
    required this.name,
    required this.ownerId,
    required this.memberCount,
    this.lastMessage,
    this.lastKind,
    this.lastMessageAt,
  });

  factory DizzyGroup.fromJson(Map<String, dynamic> json) => DizzyGroup(
    groupId: json['group_id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    ownerId: json['owner_id']?.toString() ?? '',
    memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    lastMessage: json['last_message']?.toString(),
    lastKind: json['last_kind']?.toString(),
    lastMessageAt:
        DateTime.tryParse(json['last_message_at']?.toString() ?? ''),
  );
}

/// Group membership roster row.
class DizzyGroupMember {
  final String userId;
  final String role; // 'owner' | 'member'
  final DateTime joinedAt;

  const DizzyGroupMember({
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  factory DizzyGroupMember.fromJson(Map<String, dynamic> json) =>
      DizzyGroupMember(
        userId: json['user_id']?.toString() ?? '',
        role: json['role']?.toString() ?? 'member',
        joinedAt:
            DateTime.tryParse(json['joined_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Group chat message (text + media_card for Watch Together).
class DizzyGroupMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String clientMsgId;
  final String kind; // 'text' | 'media_card'
  final String body;
  final String? mediaRef;
  final DateTime createdAt;

  const DizzyGroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.clientMsgId,
    required this.kind,
    required this.body,
    this.mediaRef,
    required this.createdAt,
  });

  factory DizzyGroupMessage.fromJson(Map<String, dynamic> json) =>
      DizzyGroupMessage(
        id: json['id']?.toString() ?? '',
        groupId: json['group_id']?.toString() ?? '',
        senderId: json['sender_id']?.toString() ?? '',
        clientMsgId: json['client_msg_id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'text',
        body: json['body']?.toString() ?? '',
        mediaRef: json['media_ref']?.toString(),
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Production Groups service: create/join/leave, roster, history,
/// idempotent sends, and Supabase Realtime subscriptions.
class DizzyGroupService {
  /// Cache of my groups, surfaced to listening UIs (roster screens).
  static final ValueNotifier<List<DizzyGroup>> myGroups =
      ValueNotifier<List<DizzyGroup>>(const []);

  /// uid -> 'owner' | 'member' for the groups in [myGroups].
  static final ValueNotifier<Map<String, String>> myRoles =
      ValueNotifier<Map<String, String>>(const {});

  static Future<String?> _myUid() async => CloudClient.db.auth.currentUser?.id;

  // ── Lifecycle ────────────────────────────────────────────────────

  /// Creates a group and puts me in as owner. Returns the group id
  /// (join code) on success, null on failure.
  static Future<String?> createGroup(String name) async {
    if (!CloudClient.isReady) return null;
    try {
      final res = await CloudClient.db.rpc(
        'create_group',
        params: {'p_name': name},
      );
      if (res is Map && res['success'] == true) {
        await refreshMyGroups();
        return res['group_id']?.toString();
      }
      AppLog.d('createGroup: ${(res as Map?)?['error']}');
      return null;
    } catch (e) {
      AppLog.d('createGroup: $e');
      return null;
    }
  }

  /// Joins by the group code shared from the owner. Returns the group
  /// name on success, null on failure (not found, offline).
  static Future<String?> joinGroup(String groupId) async {
    if (!CloudClient.isReady) return null;
    try {
      final res = await CloudClient.db.rpc(
        'join_group',
        params: {'p_group_id': groupId.trim()},
      );
      if (res is Map && res['success'] == true) {
        await refreshMyGroups();
        return res['name']?.toString();
      }
      AppLog.d('joinGroup: ${(res as Map?)?['error']}');
      return null;
    } catch (e) {
      AppLog.d('joinGroup: $e');
      return null;
    }
  }

  /// Leaves a group (or deletes it if I am the owner — server decides).
  static Future<bool> leaveGroup(String groupId) async {
    if (!CloudClient.isReady) return false;
    try {
      final res = await CloudClient.db.rpc(
        'leave_group',
        params: {'p_group_id': groupId},
      );
      final ok = res is Map && res['success'] == true;
      if (ok) await refreshMyGroups();
      return ok;
    } catch (e) {
      AppLog.d('leaveGroup: $e');
      return false;
    }
  }

  // ── Listing & roster ─────────────────────────────────────────────

  /// Reloads [myGroups] (and my role per group) from the server.
  static Future<void> refreshMyGroups() async {
    if (!CloudClient.isReady) return;
    try {
      final uid = await _myUid();
      final res = await CloudClient.db.rpc('my_groups');
      if (res is List) {
        final groups = res
            .map(
              (e) => DizzyGroup.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList();
        myGroups.value = groups;
        // Owner flag comes straight from the rows.
        final roles = <String, String>{};
        for (final g in groups) {
          roles[g.groupId] = g.ownerId == uid ? 'owner' : 'member';
        }
        myRoles.value = roles;
      }
    } catch (e) {
      AppLog.d('refreshMyGroups: $e');
    }
  }

  /// Roster for one group (fail-soft, empty list offline).
  static Future<List<DizzyGroupMember>> loadRoster(String groupId) async {
    if (!CloudClient.isReady || groupId.isEmpty) return const [];
    try {
      final res = await CloudClient.db
          .from('group_members')
          .select()
          .eq('group_id', groupId)
          .order('joined_at', ascending: true);
      return res
          .map((e) => DizzyGroupMember.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      AppLog.d('loadRoster: $e');
      return const [];
    }
  }

  /// Best-effort display name for a member (resolves via the DM resolver).
  static String memberNameFor(String uid) =>
      DizzySocialService.displayNameFor(uid);

  /// Warms the display-name cache for a roster.
  static Future<void> resolveNames(Iterable<String> uids) =>
      DizzySocialService.resolveUsernames(uids);

  // ── Chat ─────────────────────────────────────────────────────────

  /// Latest messages of a group, oldest first.
  static Future<List<DizzyGroupMessage>> loadMessages(
    String groupId, {
    int limit = 100,
  }) async {
    if (!CloudClient.isReady || groupId.isEmpty) return const [];
    try {
      final res = await CloudClient.db
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = res
          .map((e) => DizzyGroupMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return rows.reversed.toList();
    } catch (e) {
      AppLog.d('loadMessages: $e');
      return const [];
    }
  }

  /// Sends a message with idempotency UUID (DM pattern).
  static Future<bool> sendMessage({
    required String groupId,
    required String body,
    String kind = 'text',
    String? mediaRef,
  }) async {
    if (!CloudClient.isReady || groupId.isEmpty) return false;
    final myUid = await _myUid();
    if (myUid == null) return false;

    try {
      await CloudClient.db.from('group_messages').insert({
        'group_id': groupId,
        'sender_id': myUid,
        'client_msg_id': const Uuid().v4(),
        'kind': kind,
        'body': body,
        'media_ref': mediaRef,
      });
      return true;
    } catch (e) {
      AppLog.d('sendMessage: $e');
      unawaited(
        AppErrorLog.log(
          code: 'group_send',
          screen: 'groups',
          detail: 'insert_failed',
        ),
      );
      return false;
    }
  }

  /// Realtime inserts for one group's messages.
  static RealtimeChannel subscribeToMessages(
    String groupId, {
    required void Function(DizzyGroupMessage message) onMessage,
  }) {
    return CloudClient.db
        .channel('public:group_messages:group_$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isNotEmpty) {
              onMessage(DizzyGroupMessage.fromJson(row));
            }
          },
        )
        .subscribe();
  }

  /// Realtime inserts for a member join (roster refresh).
  static RealtimeChannel subscribeToRoster(
    String groupId, {
    required VoidCallback onChanged,
  }) {
    return CloudClient.db
        .channel('public:group_members:group_$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (_) => onChanged(),
        )
        .subscribe();
  }
}
