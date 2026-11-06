import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../cloud/cloud_client.dart';
import '../errors/app_error_log.dart';
import '../errors/app_log.dart';

/// User search match result.
class DizzyUserMatch {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;

  const DizzyUserMatch({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  factory DizzyUserMatch.fromJson(Map<String, dynamic> json) => DizzyUserMatch(
        userId: json['user_id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString(),
      );
}

/// In-app DM Message model with Media Card support.
class DizzyDirectMessage {
  final String id;
  final String threadId;
  final String senderId;
  final String clientMsgId;
  final String kind; // 'text' | 'media_card' | 'action'
  final String body;
  final String? mediaRef;
  final DateTime createdAt;

  const DizzyDirectMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.clientMsgId,
    required this.kind,
    required this.body,
    this.mediaRef,
    required this.createdAt,
  });

  factory DizzyDirectMessage.fromJson(Map<String, dynamic> json) =>
      DizzyDirectMessage(
        id: json['id']?.toString() ?? '',
        threadId: json['thread_id']?.toString() ?? '',
        senderId: json['sender_id']?.toString() ?? '',
        clientMsgId: json['client_msg_id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'text',
        body: json['body']?.toString() ?? '',
        mediaRef: json['media_ref']?.toString(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Production Social Hub & In-App Direct Messaging Service.
class DizzySocialService {
  static final ValueNotifier<String?> currentUsername =
      ValueNotifier<String?>(null);

  static const _keyUsername = 'dizzy_username_v1';

  /// v1.3.3-T1.1 boot loader: local cache first (instant), cloud refresh
  /// after (soft). Without this, every restart fell back to user_<code>.
  static Future<void> loadCurrentUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_keyUsername);
      if (cached != null && cached.isNotEmpty) {
        currentUsername.value = cached;
      }
    } catch (_) {}
    if (!CloudClient.isReady) return;
    try {
      final uid = CloudClient.db.auth.currentUser?.id;
      if (uid == null) return;
      final row = await CloudClient.db
          .from('usernames')
          .select('username')
          .eq('user_id', uid)
          .maybeSingle();
      final name = (row as Map?)?['username']?.toString();
      if (name != null && name.isNotEmpty) {
        currentUsername.value = name;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyUsername, name);
      }
    } catch (e) {
      AppLog.d('loadCurrentUsername: $e');
    }
  }

  /// Claims or updates an @username with atomic uniqueness check.
  static Future<Map<String, dynamic>> claimUsername(String username) async {
    if (!CloudClient.isReady) {
      return {'success': false, 'error': 'Network connection required'};
    }

    try {
      final res = await CloudClient.db.rpc('claim_username', params: {
        'p_username': username,
      });

      if (res is Map && res['success'] == true) {
        currentUsername.value = res['username']?.toString();
        try {
          final prefs = await SharedPreferences.getInstance();
          final v = currentUsername.value;
          if (v != null && v.isNotEmpty) {
            await prefs.setString(_keyUsername, v);
          }
        } catch (_) {}
        return {'success': true, 'username': currentUsername.value};
      }
      return {
        'success': false,
        'code': res is Map ? res['code'] : null,
        'error': res is Map ? res['error'] : 'Could not claim username'
      };
    } catch (e) {
      AppLog.d('claimUsername: $e');
      return {'success': false, 'error': 'Could not update username right now'};
    }
  }

  /// Instant GIN Trigram Search for @usernames and friends.
  /// Throws on unavailable cloud or lookup failure; [] means no matches.
  static Future<List<DizzyUserMatch>> searchUsers(String query) async {
    final normalizedQuery = query.trim().replaceFirst(RegExp(r'^@'), '').trim();
    if (normalizedQuery.length < 2) return [];
    if (!CloudClient.isReady) {
      throw StateError('User search is unavailable');
    }

    try {
      final res = await CloudClient.db.rpc('search_users', params: {
        'p_query': normalizedQuery,
        'p_limit': 15,
      });

      if (res is List) {
        return res
            .map((item) =>
                DizzyUserMatch.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      throw const FormatException('Invalid user search response');
    } catch (e) {
      AppLog.d('searchUsers: $e');
      rethrow;
    }
  }

  /// Generates a deterministic thread ID between two user IDs.
  static String getThreadId(String u1, String u2) {
    final sorted = [u1, u2]..sort();
    return 'dm:${sorted[0]}_${sorted[1]}';
  }

  /// Sends a direct message with idempotency UUID and rate-limit guard.
  static Future<bool> sendDirectMessage({
    required String recipientUid,
    required String body,
    String kind = 'text',
    String? mediaRef,
  }) async {
    if (!CloudClient.isReady) return false;
    final myUid = CloudClient.db.auth.currentUser?.id;
    if (myUid == null) return false;

    final threadId = getThreadId(myUid, recipientUid);
    final clientMsgId = const Uuid().v4();

    try {
      // Ensure thread exists
      await CloudClient.db.from('dm_threads').upsert({
        'thread_id': threadId,
        'user1_id': myUid,
        'user2_id': recipientUid,
      }, onConflict: 'thread_id');

      // Insert message with client_msg_id idempotency
      await CloudClient.db.from('dm_messages').insert({
        'thread_id': threadId,
        'sender_id': myUid,
        'client_msg_id': clientMsgId,
        'kind': kind,
        'body': body,
        'media_ref': mediaRef,
      });

      return true;
    } catch (e) {
      AppLog.d('sendDirectMessage: $e');
      unawaited(AppErrorLog.log(
          code: 'dm_send', screen: 'social', detail: 'insert_failed'));
      return false;
    }
  }

  /// Subscribes to real-time incoming messages for a conversation thread.
  static RealtimeChannel subscribeToThread(
    String threadId, {
    required void Function(DizzyDirectMessage message) onMessage,
  }) {
    return CloudClient.db
        .channel('public:dm_messages:thread_$threadId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'dm_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'thread_id',
            value: threadId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isNotEmpty) {
              onMessage(DizzyDirectMessage.fromJson(row));
            }
          },
        )
        .subscribe();
  }
}
