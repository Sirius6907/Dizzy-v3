import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';
import '../../models/social/friendship.dart';

/// Friend Graph & Discovery Service (Phase 2).
///
/// Manages the mutual friend graph: send/accept/reject requests,
/// block/unblock, list friends, and query relationship status.
/// All operations fail-soft when cloud is unavailable.
class DizzyFriendService {
  static final ValueNotifier<List<Friendship>> friendships =
      ValueNotifier<List<Friendship>>([]);

  static bool get isReady => CloudClient.isReady;

  static String? _myUid;

  /// Current user's Supabase UID (caches for session lifetime).
  static String? get myUid {
    _myUid ??= CloudClient.isReady
        ? CloudClient.db.auth.currentUser?.id
        : null;
    return _myUid;
  }

  /// Refresh the cached UID (call after auth state changes).
  static void refreshUid() {
    _myUid = CloudClient.isReady
        ? CloudClient.db.auth.currentUser?.id
        : null;
  }

  // ── Core Operations ──────────────────────────────────────────

  /// Send a friend request to [recipientId].
  static Future<bool> sendRequest(String recipientId) async {
    if (!isReady) return false;
    final uid = myUid;
    if (uid == null || uid == recipientId) return false;

    try {
      await CloudClient.db.from('friendships').upsert({
        'requester_id': uid,
        'addressee_id': recipientId,
        'status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'requester_id,addressee_id');
      refreshAndNotify();
      return true;
    } catch (e) {
      AppLog.d('[DizzyFriendService] sendRequest: $e');
      return false;
    }
  }

  /// Accept a pending friend request from [senderId].
  static Future<bool> acceptRequest(String senderId) async {
    if (!isReady) return false;
    final uid = myUid;
    if (uid == null) return false;

    try {
      final rows = await CloudClient.db.from('friendships').select().eq(
            'requester_id',
            senderId,
          ).eq('addressee_id', uid).eq('status', 'pending');

      if (rows.isEmpty) return false;

      await CloudClient.db.from('friendships').update({
        'status': 'accepted',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('requester_id', senderId).eq('addressee_id', uid);
      refreshAndNotify();
      return true;
    } catch (e) {
      AppLog.d('[DizzyFriendService] acceptRequest: $e');
      return false;
    }
  }

  /// Reject (delete) a pending friend request from [senderId].
  static Future<bool> rejectRequest(String senderId) async {
    if (!isReady) return false;
    final uid = myUid;
    if (uid == null) return false;

    try {
      await CloudClient.db.from('friendships').delete().eq(
            'requester_id',
            senderId,
          ).eq('addressee_id', uid).eq('status', 'pending');
      refreshAndNotify();
      return true;
    } catch (e) {
      AppLog.d('[DizzyFriendService] rejectRequest: $e');
      return false;
    }
  }

  /// Block a user. Removes any existing pending/accepted relationship and
  /// creates a blocked record.
  static Future<bool> blockUser(String userId) async {
    if (!isReady) return false;
    final uid = myUid;
    if (uid == null || uid == userId) return false;

    try {
      // Remove any existing relationship first
      await CloudClient.db.from('friendships').delete().eq(
            'requester_id',
            uid,
          ).eq('addressee_id', userId);
      await CloudClient.db.from('friendships').delete().eq(
            'requester_id',
            userId,
          ).eq('addressee_id', uid);

      await CloudClient.db.from('friendships').upsert({
        'requester_id': uid,
        'addressee_id': userId,
        'status': 'blocked',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'requester_id,addressee_id');
      refreshAndNotify();
      return true;
    } catch (e) {
      AppLog.d('[DizzyFriendService] blockUser: $e');
      return false;
    }
  }

  /// Unblock a user.
  static Future<bool> unblockUser(String userId) async {
    if (!isReady) return false;
    final uid = myUid;
    if (uid == null) return false;

    try {
      await CloudClient.db.from('friendships').delete().eq(
            'requester_id',
            uid,
          ).eq('addressee_id', userId).eq('status', 'blocked');
      await CloudClient.db.from('friendships').delete().eq(
            'requester_id',
            userId,
          ).eq('addressee_id', uid).eq('status', 'blocked');
      refreshAndNotify();
      return true;
    } catch (e) {
      AppLog.d('[DizzyFriendService] unblockUser: $e');
      return false;
    }
  }

  // ── Queries ──────────────────────────────────────────────────

  /// Get the relationship status with another user from the current user's perspective.
  /// Returns null if no relationship exists.
  static FriendStatus? getStatus(String otherUserId) {
    if (!isReady) return null;
    final uid = myUid;
    if (uid == null) return null;

    for (final f in friendships.value) {
      if (f.requesterId == uid && f.addresseeId == otherUserId) {
        return f.status;
      }
      if (f.addresseeId == uid && f.requesterId == otherUserId) {
        // Incoming request: from our perspective it's 'pending' (they sent to us)
        if (f.status == FriendStatus.pending) return FriendStatus.pending;
        return f.status;
      }
    }
    return null;
  }

  /// List all accepted friends.
  static List<String> getFriends() {
    if (!isReady) return [];
    final uid = myUid;
    if (uid == null) return [];

    return friendships.value
        .where((f) =>
            f.status == FriendStatus.accepted &&
            (f.requesterId == uid || f.addresseeId == uid))
        .map((f) => f.peerId(uid))
        .toList();
  }

  /// List all pending incoming requests (others sent to us).
  static List<String> getPendingRequests() {
    if (!isReady) return [];
    final uid = myUid;
    if (uid == null) return [];

    return friendships.value
        .where((f) =>
            f.status == FriendStatus.pending && f.addresseeId == uid)
        .map((f) => f.requesterId)
        .toList();
  }

  /// List all blocked users.
  static List<String> getBlockedUsers() {
    if (!isReady) return [];
    final uid = myUid;
    if (uid == null) return [];

    return friendships.value
        .where((f) =>
            f.status == FriendStatus.blocked &&
            (f.requesterId == uid || f.addresseeId == uid))
        .map((f) => f.peerId(uid))
        .toList();
  }

  /// Subscribe to real-time friendship changes (insert events).
  /// Returns null if user is not authenticated (fail-soft).
  static RealtimeChannel? subscribeToFriendshipChanges({
    required void Function(Friendship) onChange,
  }) {
    final uid = myUid;
    if (uid == null) {
      AppLog.d('[DizzyFriendService] subscribe skipped: not authenticated');
      return null;
    }

    return CloudClient.db.channel('friendships:$uid').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'friendships',
      callback: (payload) {
        final row = payload.newRecord;
        if (row.isNotEmpty) {
          onChange(Friendship.fromJson(row));
        }
      },
    ).subscribe();
  }

  // ── Internal ─────────────────────────────────────────────────

  static void refreshAndNotify() {
    _myUid = CloudClient.isReady
        ? CloudClient.db.auth.currentUser?.id
        : null;
    _loadFromCloud();
  }

  static Future<void> _loadFromCloud() async {
    if (!isReady) {
      friendships.value = [];
      return;
    }
    final uid = myUid;
    if (uid == null) {
      friendships.value = [];
      return;
    }
    try {
      // Fetch rows where current user is either requester or addressee.
      final requesterRows = await CloudClient.db
          .from('friendships')
          .select()
          .eq('requester_id', uid);
      final addresseeRows = await CloudClient.db
          .from('friendships')
          .select()
          .eq('addressee_id', uid);

      final allRows = <Map<String, dynamic>>[];
      for (final r in requesterRows as List) {
        allRows.add(Map<String, dynamic>.from(r));
      }
      for (final r in addresseeRows as List) {
        allRows.add(Map<String, dynamic>.from(r));
      }

      friendships.value = allRows
          .map((e) => Friendship.fromJson(e))
          .toList();
    } catch (e) {
      AppLog.d('[DizzyFriendService] loadFromCloud: $e');
      friendships.value = [];
    }
  }

  /// Load friendships from cloud into the notifier (call once at login).
  static Future<void> loadFriendships() {
    return _loadFromCloud();
  }
}
