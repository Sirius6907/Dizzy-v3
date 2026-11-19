import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';
import 'dizzy_group_service.dart';
import 'dizzy_social_service.dart';

/// One row in the Social Hub inbox: a DM thread plus its unread state.
class SocialInboxItem {
  final String threadId;
  final String peerUid;
  final String? lastBody;
  final String? lastKind;
  final DateTime? lastAt;
  final int unreadCount;

  const SocialInboxItem({
    required this.threadId,
    required this.peerUid,
    required this.lastBody,
    required this.lastKind,
    required this.lastAt,
    required this.unreadCount,
  });

  bool get hasUnread => unreadCount > 0;
}

/// One row in the Social Hub group list.
class SocialGroupItem {
  final String groupId;
  final String name;
  final int memberCount;
  final String? lastBody;
  final String? lastKind;
  final DateTime? lastAt;
  final int unreadCount;

  const SocialGroupItem({
    required this.groupId,
    required this.name,
    required this.memberCount,
    required this.lastBody,
    required this.lastKind,
    required this.lastAt,
    required this.unreadCount,
  });

  bool get hasUnread => unreadCount > 0;
}

/// Social Hub v2 — one inbox for DMs, friends, groups and rooms.
///
/// Unread state comes from a per-thread `last_read` cursor kept on the
/// device (`social_read_v1_<threadId>`, `social_group_read_v1_<groupId>`).
/// The cloud schema has no read marker and adding one is a separately
/// approved migration, so the cursor stays local: it is private, works
/// offline, and never needs a policy. The cursor is a timestamp, not a
/// message count, so it survives history pagination and late delivery.
class SocialHubService {
  SocialHubService._();

  static const _dmPrefix = 'social_read_v1_';
  static const _groupPrefix = 'social_group_read_v1_';

  /// Unread DMs only.
  static final ValueNotifier<int> dmUnread = ValueNotifier<int>(0);

  /// Unread group messages only.
  static final ValueNotifier<int> groupUnread = ValueNotifier<int>(0);

  /// Everything unread. Drives every Social Hub badge.
  static final ValueNotifier<int> totalUnread = ValueNotifier<int>(0);

  static void _setDm(int n) {
    dmUnread.value = n;
    totalUnread.value = dmUnread.value + groupUnread.value;
  }

  static void _setGroup(int n) {
    groupUnread.value = n;
    totalUnread.value = dmUnread.value + groupUnread.value;
  }

  /// Pure unread math — unit-testable without prefs or a cloud session.
  ///
  /// A message counts when it was written by someone else and landed
  /// strictly after the cursor. A null cursor means "never opened here",
  /// so all incoming history counts until the thread is opened once.
  static int unreadCountFor({
    required Iterable<DizzyDirectMessage> messages,
    required String myUid,
    required DateTime? cursor,
  }) {
    var n = 0;
    for (final m in messages) {
      if (m.senderId == myUid) continue;
      if (cursor != null && !m.createdAt.isAfter(cursor)) continue;
      n++;
    }
    return n;
  }

  /// Same rule as [unreadCountFor], for group rows.
  static int groupUnreadCountFor({
    required Iterable<DizzyGroupMessage> messages,
    required String myUid,
    required DateTime? cursor,
  }) {
    var n = 0;
    for (final m in messages) {
      if (m.senderId == myUid) continue;
      if (cursor != null && !m.createdAt.isAfter(cursor)) continue;
      n++;
    }
    return n;
  }

  /// Latest timestamp in [messages], or null when the thread is empty.
  static DateTime? latestStamp(Iterable<DizzyDirectMessage> messages) {
    DateTime? latest;
    for (final m in messages) {
      if (latest == null || m.createdAt.isAfter(latest)) latest = m.createdAt;
    }
    return latest;
  }

  static String _dmKey(String threadId) => '$_dmPrefix$threadId';
  static String _groupKey(String groupId) => '$_groupPrefix$groupId';

  /// Reads the stored read cursor for [threadId] (null = never opened).
  static Future<DateTime?> readCursor(String threadId) async {
    if (threadId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_dmKey(threadId));
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  /// Marks [threadId] read through [through] (defaults to now).
  ///
  /// Moving the cursor backwards is ignored: a slow page load can never
  /// resurrect an already-cleared badge.
  static Future<void> markRead(String threadId, {DateTime? through}) async {
    await _advance(_dmKey(threadId), through);
  }

  /// Marks a group read through [through] (defaults to now).
  static Future<void> markGroupRead(String groupId, {DateTime? through}) async {
    await _advance(_groupKey(groupId), through);
  }

  static Future<void> _advance(String key, DateTime? through) async {
    if (key.isEmpty) return;
    final at = through ?? DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getInt(key);
      if (prev != null && prev >= at.millisecondsSinceEpoch) return;
      await prefs.setInt(key, at.millisecondsSinceEpoch);
      await refreshTotal();
    } catch (e) {
      AppLog.d('SocialHubService.markRead: $e');
    }
  }

  /// Loads the DM inbox newest-first. Fail-soft: offline returns [].
  ///
  /// Threads are fetched with two equality reads (requester/addressee style)
  /// instead of an `or` filter, matching the rest of the social layer and
  /// keeping the RLS-friendly query shape.
  static Future<List<SocialInboxItem>> loadInbox() async {
    if (!CloudClient.isReady) return const [];
    final uid = CloudClient.db.auth.currentUser?.id;
    if (uid == null) return const [];

    try {
      final threads = await _fetchThreads(uid);
      if (threads.isEmpty) {
        _setDm(0);
        return const [];
      }

      final ids = threads.keys.toList();
      final rawMessages = await CloudClient.db
          .from('dm_messages')
          .select(
            'id,thread_id,sender_id,client_msg_id,kind,body,media_ref,created_at',
          )
          .inFilter('thread_id', ids)
          .order('created_at', ascending: false)
          .limit(400);

      final byThread = <String, List<DizzyDirectMessage>>{};
      for (final row in rawMessages as List) {
        final m = DizzyDirectMessage.fromJson(
          Map<String, dynamic>.from(row as Map),
        );
        byThread.putIfAbsent(m.threadId, () => []).add(m);
      }

      final prefs = await SharedPreferences.getInstance();
      final items = <SocialInboxItem>[];
      for (final entry in threads.entries) {
        final threadId = entry.key;
        final row = entry.value;
        final peer = row['user1_id']?.toString() == uid
            ? row['user2_id']?.toString() ?? ''
            : row['user1_id']?.toString() ?? '';
        final messages = byThread[threadId] ?? const <DizzyDirectMessage>[];
        final ms = prefs.getInt(_dmKey(threadId));
        final cursor = ms == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ms);
        final last = messages.isEmpty ? null : messages.first;
        items.add(
          SocialInboxItem(
            threadId: threadId,
            peerUid: peer,
            lastBody: last?.body,
            lastKind: last?.kind,
            lastAt: last?.createdAt,
            unreadCount: unreadCountFor(
              messages: messages,
              myUid: uid,
              cursor: cursor,
            ),
          ),
        );
      }

      items.sort((a, b) {
        final at = a.lastAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.lastAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

      _setDm(items.fold(0, (sum, i) => sum + i.unreadCount));

      // Warm the name cache so the inbox never renders a placeholder.
      resolvePeerNames(items.map((i) => i.peerUid));
      return items;
    } catch (e) {
      AppLog.d('SocialHubService.loadInbox: $e');
      return const [];
    }
  }

  /// Loads my groups with per-group unread counts, newest first.
  static Future<List<SocialGroupItem>> loadGroupInbox() async {
    if (!CloudClient.isReady) return const [];
    final uid = CloudClient.db.auth.currentUser?.id;
    if (uid == null) return const [];

    try {
      final groups = await _fetchGroups();
      if (groups.isEmpty) {
        _setGroup(0);
        return const [];
      }

      final ids = groups.map((g) => g.groupId).toList();
      final prefs = await SharedPreferences.getInstance();
      final rows = await CloudClient.db
          .from('group_messages')
          .select('id,group_id,sender_id,client_msg_id,kind,body,media_ref,created_at')
          .inFilter('group_id', ids)
          .order('created_at', ascending: false)
          .limit(400);

      final byGroup = <String, List<DizzyGroupMessage>>{};
      for (final row in rows as List) {
        final m = DizzyGroupMessage.fromJson(
          Map<String, dynamic>.from(row as Map),
        );
        byGroup.putIfAbsent(m.groupId, () => []).add(m);
      }

      final items = <SocialGroupItem>[];
      for (final g in groups) {
        final messages = byGroup[g.groupId] ?? const <DizzyGroupMessage>[];
        final ms = prefs.getInt(_groupKey(g.groupId));
        final cursor = ms == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ms);
        items.add(
          SocialGroupItem(
            groupId: g.groupId,
            name: g.name,
            memberCount: g.memberCount,
            lastBody: g.lastMessage,
            lastKind: g.lastKind,
            lastAt: g.lastMessageAt,
            unreadCount: groupUnreadCountFor(
              messages: messages,
              myUid: uid,
              cursor: cursor,
            ),
          ),
        );
      }

      items.sort((a, b) {
        final at = a.lastAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.lastAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

      _setGroup(items.fold(0, (sum, i) => sum + i.unreadCount));
      return items;
    } catch (e) {
      AppLog.d('SocialHubService.loadGroupInbox: $e');
      return const [];
    }
  }

  /// Recomputes every unread count for the hub badges without opening the
  /// page. Safe to call at boot and on resume.
  static Future<void> refreshTotal() async {
    if (!CloudClient.isReady) {
      _setDm(0);
      _setGroup(0);
      return;
    }
    final uid = CloudClient.db.auth.currentUser?.id;
    if (uid == null) {
      _setDm(0);
      _setGroup(0);
      return;
    }
    try {
      final threads = await _fetchThreads(uid);
      final threadIds = threads.keys.toList();
      final prefs = await SharedPreferences.getInstance();

      var dmTotal = 0;
      if (threadIds.isNotEmpty) {
        final rows = await CloudClient.db
            .from('dm_messages')
            .select('thread_id,sender_id,created_at')
            .inFilter('thread_id', threadIds)
            .order('created_at', ascending: false)
            .limit(400);
        final byThread = <String, List<DizzyDirectMessage>>{};
        for (final row in rows as List) {
          final m = DizzyDirectMessage.fromJson(
            Map<String, dynamic>.from(row as Map),
          );
          byThread.putIfAbsent(m.threadId, () => []).add(m);
        }
        for (final id in threadIds) {
          final ms = prefs.getInt(_dmKey(id));
          dmTotal += unreadCountFor(
            messages: byThread[id] ?? const [],
            myUid: uid,
            cursor: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
          );
        }
      }
      _setDm(dmTotal);

      final groups = await _fetchGroups();
      final groupIds = groups.map((g) => g.groupId).toList();
      var groupTotal = 0;
      if (groupIds.isNotEmpty) {
        final rows = await CloudClient.db
            .from('group_messages')
            .select('group_id,sender_id,created_at')
            .inFilter('group_id', groupIds)
            .order('created_at', ascending: false)
            .limit(400);
        final byGroup = <String, List<DizzyGroupMessage>>{};
        for (final row in rows as List) {
          final m = DizzyGroupMessage.fromJson(
            Map<String, dynamic>.from(row as Map),
          );
          byGroup.putIfAbsent(m.groupId, () => []).add(m);
        }
        for (final id in groupIds) {
          final ms = prefs.getInt(_groupKey(id));
          groupTotal += groupUnreadCountFor(
            messages: byGroup[id] ?? const [],
            myUid: uid,
            cursor: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
          );
        }
      }
      _setGroup(groupTotal);
    } catch (e) {
      AppLog.d('SocialHubService.refreshTotal: $e');
    }
  }

  // ── Cloud reads ───────────────────────────────────────────────

  static Future<Map<String, Map<String, dynamic>>> _fetchThreads(
    String uid,
  ) async {
    final asOne = await CloudClient.db
        .from('dm_threads')
        .select('thread_id,user1_id,user2_id,created_at')
        .eq('user1_id', uid);
    final asTwo = await CloudClient.db
        .from('dm_threads')
        .select('thread_id,user1_id,user2_id,created_at')
        .eq('user2_id', uid);
    final threads = <String, Map<String, dynamic>>{};
    for (final row in [...(asOne as List), ...(asTwo as List)]) {
      final map = Map<String, dynamic>.from(row as Map);
      final id = map['thread_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      threads[id] = map;
    }
    return threads;
  }

  static Future<List<DizzyGroup>> _fetchGroups() async {
    final res = await CloudClient.db.rpc('my_groups');
    if (res is! List) return const [];
    return res
        .map((e) => DizzyGroup.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((g) => g.groupId.isNotEmpty)
        .toList();
  }
}

/// Fire-and-forget name resolution; kept outside the class body so the
/// service has no async gaps of its own.
void resolvePeerNames(Iterable<String> uids) {
  DizzySocialService.resolveUsernames(uids);
}
