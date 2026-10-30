import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';
import 'notification_inbox.dart';
import 'notification_prefs.dart';

/// Server-backed half of the Notification Center (v1.3.3 Phase 4).
///
/// `push_send_log` keeps what the brain sent, so a fresh install (or a device
/// that was offline for a day) still shows history. Local items always win:
/// they carry the read state and arrive in real time.
class NotificationHistory {
  NotificationHistory._();

  static Future<List<InboxItem>> fetch({int limit = 30}) async {
    if (!CloudClient.isReady) return const <InboxItem>[];
    try {
      final rows = await CloudClient.db
          .from('push_send_log')
          .select('id, kind, title, body, dedupe_id, created_at')
          .inFilter('status', ['sent', 'skipped'])
          .order('created_at', ascending: false)
          .limit(limit);
      final out = <InboxItem>[];
      for (final row in (rows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final title = (map['title'] ?? '').toString();
        final body = (map['body'] ?? '').toString();
        if (title.isEmpty && body.isEmpty) continue;
        final atMs =
            DateTime.tryParse('${map['created_at']}')?.millisecondsSinceEpoch ??
            0;
        final dedupe = (map['dedupe_id'] ?? '').toString();
        out.add(
          InboxItem(
            id: dedupe.isNotEmpty ? dedupe : 'srv_${map['id']}',
            title: title.isEmpty ? 'Dizzy' : title,
            body: body,
            kindKey:
                NotificationKind.fromKey((map['kind'] ?? '').toString())?.key ??
                NotificationKind.release.key,
            atMs: atMs,
            // Server rows are backfill: the banner already happened.
            read: true,
          ),
        );
      }
      return out;
    } catch (e) {
      AppLog.d('[NotifyHistory] fetch failed (soft): $e');
      return const <InboxItem>[];
    }
  }

  /// Newest first, deduped by id, local wins, optional clear watermark.
  static List<InboxItem> merge(
    List<InboxItem> local,
    List<InboxItem> server, {
    int max = NotificationInbox.maxItems,
    int clearBeforeMs = 0,
  }) {
    final byId = <String, InboxItem>{};
    for (final s in server) {
      if (s.atMs <= clearBeforeMs) continue;
      byId[s.id] = s;
    }
    for (final l in local) {
      byId[l.id] = l;
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.atMs.compareTo(a.atMs));
    return list.length <= max ? list : list.sublist(0, max);
  }
}
