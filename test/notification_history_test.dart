import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/notification/notification_history.dart';
import 'package:dizzy/services/notification/notification_inbox.dart';

InboxItem item(String id, int atMs, {bool read = false}) => InboxItem(
  id: id,
  title: 'T$id',
  body: 'B$id',
  kindKey: 'releases',
  atMs: atMs,
  read: read,
);

void main() {
  group('NotificationHistory.merge', () {
    test('local items win over the same id from the server', () {
      final local = [item('rel_1', 2000, read: false)];
      final server = [item('rel_1', 2000, read: true)];

      final merged = NotificationHistory.merge(local, server);

      expect(merged, hasLength(1));
      expect(merged.single.read, false);
    });

    test('server-only history backfills a fresh install', () {
      final merged = NotificationHistory.merge(
        const [],
        [item('rel_9', 5000), item('rel_8', 4000)],
      );

      expect(merged.map((e) => e.id), ['rel_9', 'rel_8']);
    });

    test('newest first across both sources and capped', () {
      final local = [item('a', 1000), item('c', 3000)];
      final server = [item('b', 2000), item('d', 4000)];

      final merged = NotificationHistory.merge(local, server, max: 3);

      expect(merged.map((e) => e.id), ['d', 'c', 'b']);
    });

    test('clearedAt hides server rows the user already dismissed', () {
      final merged = NotificationHistory.merge(
        [item('new', 6000)],
        [item('old', 3000), item('edge', 5000)],
        clearBeforeMs: 5000,
      );

      expect(merged.map((e) => e.id), ['new']);
    });
  });
}
