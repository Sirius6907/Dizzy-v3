import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/notification/notification_inbox.dart';
import 'package:dizzy/services/notification/notification_prefs.dart';

/// Phase J4 — notification policy (quiet hours + per-type prefs) and the
/// Notification Center inbox cap. All pure: no platform channel involved.
void main() {
  group('quiet hours (pure window math)', () {
    test('wraps midnight: 22:00 → 07:00', () {
      bool quiet(DateTime t) => NotificationGate.isQuietAt(
        t,
        startMinute: 22 * 60,
        endMinute: 7 * 60,
      );

      expect(quiet(DateTime(2026, 10, 1, 21, 59)), isFalse);
      expect(quiet(DateTime(2026, 10, 1, 22, 0)), isTrue);
      expect(quiet(DateTime(2026, 10, 1, 23, 59)), isTrue);
      expect(quiet(DateTime(2026, 10, 1, 0, 0)), isTrue);
      expect(quiet(DateTime(2026, 10, 1, 6, 59)), isTrue);
      expect(quiet(DateTime(2026, 10, 1, 7, 0)), isFalse);
      expect(quiet(DateTime(2026, 10, 1, 12, 0)), isFalse);
    });

    test('same-day window: 09:00 → 17:00', () {
      bool quiet(DateTime t) => NotificationGate.isQuietAt(
        t,
        startMinute: 9 * 60,
        endMinute: 17 * 60,
      );

      expect(quiet(DateTime(2026, 10, 1, 8, 59)), isFalse);
      expect(quiet(DateTime(2026, 10, 1, 9, 0)), isTrue);
      expect(quiet(DateTime(2026, 10, 1, 16, 59)), isTrue);
      expect(quiet(DateTime(2026, 10, 1, 17, 0)), isFalse);
    });

    test('zero-length window never silences anything', () {
      expect(
        NotificationGate.isQuietAt(
          DateTime(2026, 10, 1, 12, 0),
          startMinute: 720,
          endMinute: 720,
        ),
        isFalse,
      );
    });
  });

  group('gate policy', () {
    test('everything is on by default', () {
      const gate = NotificationGate();
      for (final kind in NotificationKind.values) {
        expect(gate.kindEnabled(kind), isTrue, reason: kind.key);
        expect(gate.allows(kind, DateTime(2026, 10, 1, 12, 0)), isTrue);
      }
    });

    test('a switched-off kind never notifies, even outside quiet hours', () {
      final gate = const NotificationGate().copyWith(
        off: {NotificationKind.download.key},
      );
      expect(gate.kindEnabled(NotificationKind.download), isFalse);
      expect(
        gate.allows(NotificationKind.download, DateTime(2026, 10, 1, 12, 0)),
        isFalse,
      );
      expect(
        gate.allows(NotificationKind.update, DateTime(2026, 10, 1, 12, 0)),
        isTrue,
        reason: 'one off kind must not silence the others',
      );
    });

    test('quiet hours block every kind, and only inside the window', () {
      final gate = const NotificationGate(
        quietEnabled: true,
      ).copyWith(quietStartMinute: 22 * 60, quietEndMinute: 7 * 60);

      for (final kind in NotificationKind.values) {
        expect(
          gate.allows(kind, DateTime(2026, 10, 1, 23, 30)),
          isFalse,
          reason: kind.key,
        );
        expect(
          gate.allows(kind, DateTime(2026, 10, 1, 12, 0)),
          isTrue,
          reason: kind.key,
        );
      }
    });

    test('quiet toggle off means the same window is ignored', () {
      final off = const NotificationGate(
        quietEnabled: false,
      ).copyWith(quietStartMinute: 22 * 60, quietEndMinute: 7 * 60);
      expect(
        off.allows(NotificationKind.update, DateTime(2026, 10, 1, 23, 30)),
        isTrue,
      );
    });

    test('json round-trip preserves the whole gate', () {
      const original = NotificationGate(
        off: {'social', 'announcement'},
        quietEnabled: true,
        quietStartMinute: 1320,
        quietEndMinute: 420,
      );
      final restored = NotificationGate.fromJson(original.toJson());

      expect(restored.off, original.off);
      expect(restored.quietEnabled, isTrue);
      expect(restored.quietStartMinute, 1320);
      expect(restored.quietEndMinute, 420);
    });

    test('time helpers parse, format and reject junk', () {
      expect(NotificationGate.parseHhMm('22:30'), 1350);
      expect(NotificationGate.parseHhMm('7:05'), 425);
      expect(NotificationGate.parseHhMm('24:00'), isNull);
      expect(NotificationGate.parseHhMm('12:99'), isNull);
      expect(NotificationGate.parseHhMm('noon'), isNull);
      expect(NotificationGate.parseHhMm(null), isNull);

      expect(NotificationGate.hhmm(1350), '22:30');
      expect(NotificationGate.hhmm(425), '07:05');
      expect(NotificationGate.hhmm(0), '00:00');
    });

    test('unknown kind key degrades to social, never throws', () {
      expect(NotificationKind.fromKey('updates'), NotificationKind.update);
      expect(NotificationKind.fromKey('nonsense'), isNull);
      expect(
        const InboxItem(
          id: 'x',
          title: 't',
          body: 'b',
          kindKey: 'nonsense',
          atMs: 0,
        ).kind,
        NotificationKind.social,
      );
    });
  });

  group('inbox (cap 50)', () {
    InboxItem make(String id) => InboxItem(
      id: id,
      title: 'Title $id',
      body: 'Body $id',
      kindKey: NotificationKind.social.key,
      atMs: 0,
    );

    test('newest first, hard capped at 50', () {
      var list = <InboxItem>[];
      for (var i = 0; i < 60; i++) {
        list = NotificationInbox.capInbox(list, make('item-$i'));
      }
      expect(list.length, NotificationInbox.maxItems);
      expect(list.first.id, 'item-59', reason: 'newest sits at the top');
      expect(
        list.any((e) => e.id == 'item-0'),
        isFalse,
        reason: 'oldest evicted once the cap is hit',
      );
      expect(list.any((e) => e.id == 'item-10'), isTrue);
    });

    test('re-adding the same id refreshes it instead of duplicating', () {
      var list = NotificationInbox.capInbox(<InboxItem>[], make('a'));
      list = NotificationInbox.capInbox(list, make('a'));
      expect(list.length, 1);
      expect(list.first.id, 'a');
    });

    test('custom cap is honoured', () {
      var list = <InboxItem>[];
      for (var i = 0; i < 10; i++) {
        list = NotificationInbox.capInbox(list, make('i$i'), max: 3);
      }
      expect(list.length, 3);
    });

    test('decode is fail-soft: junk becomes an empty list', () {
      expect(NotificationInbox.decode(null), isEmpty);
      expect(NotificationInbox.decode(''), isEmpty);
      expect(NotificationInbox.decode('{not a list}'), isEmpty);
      expect(
        NotificationInbox.decode('[1,2,3]'),
        isEmpty,
        reason: 'non-object entries are skipped, not thrown',
      );
    });

    test('encode/decode round-trips read state', () {
      final list = [
        NotificationInbox.capInbox(
          <InboxItem>[],
          make('a'),
        ).first.copyWith(read: true),
        NotificationInbox.capInbox(<InboxItem>[], make('b')).first,
      ];
      final back = NotificationInbox.decode(NotificationInbox.encode(list));

      expect(back.length, 2);
      expect(back.first.read, isTrue);
      expect(back.last.read, isFalse);
      expect(NotificationInbox.unreadCount(back), 1);
    });

    test('badge clamps at 99 instead of showing 4 digits', () {
      final many = [
        for (var i = 0; i < 250; i++)
          InboxItem(
            id: 'n$i',
            title: 't',
            body: 'b',
            kindKey: NotificationKind.update.key,
            atMs: i,
          ),
      ];
      expect(NotificationInbox.unreadCount(many), 250);
      expect(NotificationInbox.badgeCount(many), 99);
    });
  });
}
