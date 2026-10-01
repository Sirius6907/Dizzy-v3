import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_prefs.dart';

class InboxItem {
  const InboxItem({
    required this.id,
    required this.title,
    required this.body,
    required this.kindKey,
    required this.atMs,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String kindKey;
  final int atMs;
  final bool read;

  NotificationKind get kind =>
      NotificationKind.fromKey(kindKey) ?? NotificationKind.social;

  InboxItem copyWith({bool? read}) => InboxItem(
    id: id,
    title: title,
    body: body,
    kindKey: kindKey,
    atMs: atMs,
    read: read ?? this.read,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'kind': kindKey,
    'at': atMs,
    'read': read,
  };

  factory InboxItem.fromJson(Map<String, dynamic> json) => InboxItem(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    body: json['body']?.toString() ?? '',
    kindKey: json['kind']?.toString() ?? NotificationKind.social.key,
    atMs: (json['at'] as num?)?.toInt() ?? 0,
    read: json['read'] == true,
  );
}

/// Phase J3 — the local Notification Center: one merged list of server
/// announcements and local events, newest first, hard-capped.
class NotificationInbox {
  NotificationInbox._();

  static const String kStorageKey = 'notification_inbox_v1';
  static const int maxItems = 50;
  static const int maxUnreadBadge = 99;

  static final ValueNotifier<List<InboxItem>> items =
      ValueNotifier<List<InboxItem>>(<InboxItem>[]);

  static bool _loaded = false;

  /// Pure cap: newest first, never grows past [max].
  static List<InboxItem> capInbox(
    List<InboxItem> current,
    InboxItem add, {
    int max = maxItems,
  }) {
    final next = <InboxItem>[add, ...current.where((e) => e.id != add.id)];
    return next.length <= max ? next : next.sublist(0, max);
  }

  static List<InboxItem> decode(String? raw) {
    if (raw == null || raw.isEmpty) return <InboxItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <InboxItem>[];
      return decoded
          .whereType<Map>()
          .map((e) => InboxItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return <InboxItem>[];
    }
  }

  static String encode(List<InboxItem> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static int unreadCount(List<InboxItem> list) =>
      list.where((e) => !e.read).length;

  /// Badge clamps at 99 instead of showing 4-digit noise.
  static int badgeCount(List<InboxItem> list) =>
      unreadCount(list).clamp(0, maxUnreadBadge);

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      items.value = decode(prefs.getString(kStorageKey));
    } catch (e) {
      debugPrint('[Inbox] load failed (soft): $e');
    }
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kStorageKey, encode(items.value));
    } catch (e) {
      debugPrint('[Inbox] persist failed (soft): $e');
    }
  }

  /// Returns true when the item landed in the inbox.
  static Future<bool> add({
    required String title,
    required String body,
    required NotificationKind kind,
    String? id,
    DateTime? at,
  }) async {
    final item = InboxItem(
      id: id ?? '${kind.key}-${(at ?? DateTime.now()).microsecondsSinceEpoch}',
      title: title,
      body: body,
      kindKey: kind.key,
      atMs: (at ?? DateTime.now()).millisecondsSinceEpoch,
    );
    items.value = capInbox(items.value, item);
    await _persist();
    return true;
  }

  static Future<void> markAllRead() async {
    items.value = [for (final e in items.value) e.copyWith(read: true)];
    await _persist();
  }

  static Future<void> clear() async {
    items.value = <InboxItem>[];
    await _persist();
  }

  @visibleForTesting
  static void resetForTest({List<InboxItem>? seed}) {
    _loaded = seed == null;
    items.value = seed ?? <InboxItem>[];
  }
}
