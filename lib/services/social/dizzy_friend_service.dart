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
  ///
  /// Mutual-safe: if [recipientId] already has a pending request toward us,
  /// the two pending rows collapse into one accepted friendship instead of
  /// leaving both users staring at "Sent ✓" forever.
  static Future<bool> sendRequest(String recipientId) async {
    if (!isReady) return false;
    final uid = myUid;
    if (uid == null || uid == recipientId) return false;

    try {
      // Reverse pending row? Accept it — this is a mutual add.
      final reverse = await CloudClient.db.from('friendships').select().eq(
            'requester_id',
            recipientId,
          ).eq('addressee_id', uid).eq('status', 'pending');
      if (reverse.isNotEmpty) {
        await CloudClient.db.from('friendships').update({
          'status': 'accepted',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('requester_id', recipientId).eq('addressee_id', uid);
        refreshAndNotify();
        return true;
      }

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
  ///
  /// Also settles our own outgoing pending row toward [senderId] when one
  /// exists, so the other side never keeps seeing "Sent ✓" after a mutual
  /// add.
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

      final now = DateTime.now().toIso8601String();
      await CloudClient.db.from('friendships').update({
        'status': 'accepted',
        'updated_at': now,
      }).eq('requester_id', senderId).eq('addressee_id', uid);

      // Settle our own outgoing pending row toward the same user, if any.
      final mine = await CloudClient.db.from('friendships').select().eq(
            'requester_id',
            uid,
          ).eq('addressee_id', senderId).eq('status', 'pending');
      if (mine.isNotEmpty) {
        await CloudClient.db.from('friendships').update({
          'status': 'accepted',
          'updated_at': now,
        }).eq('requester_id', uid).eq('addressee_id', senderId);
      }
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
  ///
  /// `accepted` wins over `pending`: after a mutual add there can be two
  /// rows between the same pair, and the friendship must display as a
  /// friendship, not as a stale request.
  static FriendStatus? getStatus(String otherUserId) {
    if (!isReady) return null;
    final uid = myUid;
    if (uid == null) return null;
    return statusFor(uid, friendships.value, otherUserId);
  }

  /// Pure resolver — [FriendStatus.accepted] wins over `pending`: after a
  /// mutual add there can be two rows between the same pair, and the
  /// friendship must display as a friendship, not as a stale request.
  /// Split from [getStatus] so it is unit-testable without a cloud session.
  static FriendStatus? statusFor(
    String uid,
    List<Friendship> rows,
    String otherUserId,
  ) {
    FriendStatus? fallback;
    for (final f in rows) {
      final involved =
          (f.requesterId == uid && f.addresseeId == otherUserId) ||
          (f.addresseeId == uid && f.requesterId == otherUserId);
      if (!involved) continue;
      if (f.status == FriendStatus.accepted) return FriendStatus.accepted;
      fallback ??= f.status;
    }
    return fallback;
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

  // ── Realtime ─────────────────────────────────────────────────

  static RealtimeChannel? _realtimeChannel;
  static Timer? _refetchDebounce;

  /// Live friendship sync. Subscribes to INSERT **and** UPDATE events on
  /// `friendships` (RLS already limits events to rows where we are a
  /// participant) and re-fetches the full list on any change — the server
  /// list is the single source of truth, so no client-side row merging
  /// can drift. This is what makes "Sent ✓" flip to "Chat" the moment the
  /// other user accepts.
  ///
  /// Safe to call repeatedly: an existing channel is reused.
  static void startRealtime() {
    if (!isReady) return;
    final uid = myUid;
    if (uid == null) return;
    if (_realtimeChannel != null) return;

    _realtimeChannel = CloudClient.db
        .channel('friendships:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          callback: (_) => _refetchSoon(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'friendships',
          callback: (_) => _refetchSoon(),
        )
        .subscribe();
  }

  /// Stop the realtime channel (call when the session ends).
  static Future<void> stopRealtime() async {
    _refetchDebounce?.cancel();
    _refetchDebounce = null;
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (channel == null || !CloudClient.isReady) return;
    try {
      await CloudClient.db.removeChannel(channel);
    } catch (_) {}
  }

  /// Burst-safe refetch: many events in quick succession (accept + settle,
  /// block + delete …) trigger exactly one network read.
  static void _refetchSoon() {
    _refetchDebounce?.cancel();
    _refetchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(loadFriendships());
    });
  }

  /// Subscribe to raw friendship change events.
  ///
  /// Kept for tests and custom callers; prefer [startRealtime], which also
  /// refetches the shared notifier on every event.
  static RealtimeChannel? subscribeToFriendshipChanges({
    void Function(Friendship)? onChange,
  }) {
    final uid = myUid;
    if (uid == null) {
      AppLog.d('[DizzyFriendService] subscribe skipped: not authenticated');
      return null;
    }

    return CloudClient.db
        .channel('friendships-raw:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isNotEmpty) onChange?.call(Friendship.fromJson(row));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'friendships',
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isNotEmpty) onChange?.call(Friendship.fromJson(row));
          },
        )
        .subscribe();
  }

  // ── Perspective helpers (UI display logic) ─────────────────────

  /// True when [otherUserId] has a pending request toward us — the search
  /// tab must offer "Accept", not "Sent ✓".
  static bool isIncomingPending(String otherUserId) {
    if (!isReady) return false;
    final uid = myUid;
    if (uid == null) return false;
    return incomingPendingFor(uid, friendships.value, otherUserId);
  }

  /// Pure resolver — true when [otherUserId] has a pending request toward
  /// [uid]. Split from [isIncomingPending] so it is unit-testable without
  /// a cloud session.
  static bool incomingPendingFor(
    String uid,
    List<Friendship> rows,
    String otherUserId,
  ) {
    return rows.any(
      (f) =>
          f.status == FriendStatus.pending &&
          f.addresseeId == uid &&
          f.requesterId == otherUserId,
    );
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
