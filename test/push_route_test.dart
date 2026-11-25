import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/notification/notification_inbox.dart';
import 'package:dizzy/services/notification/notification_prefs.dart';
import 'package:dizzy/services/notification/push_route.dart';
import 'package:dizzy/services/push/active_thread.dart';
import 'package:dizzy/services/push/push_service.dart';

Map<String, dynamic> chatData({
  String kind = 'social',
  String senderUid = 'uid-1',
  String senderName = 'Aria',
  String avatar = 'https://cdn/a.jpg',
  String entityId = '',
}) => {
  'kind': kind,
  'title': 'Aria',
  'body': 'see you at 8',
  if (senderUid.isNotEmpty) 'sender_uid': senderUid,
  if (senderName.isNotEmpty) 'sender_name': senderName,
  if (avatar.isNotEmpty) 'avatar': avatar,
  if (entityId.isNotEmpty) 'entity_id': entityId,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PushRoute.resolve priority', () {
    test('a direct message wins over everything else', () {
      final route = PushRoute.resolve(
        senderUid: 'uid-1',
        senderName: 'Aria',
        groupId: 'g-1',
        roomCode: 'AB12CD',
        entityId: '550',
      );
      expect(route.target, PushTarget.dm);
      expect(route.threadId, 'uid-1');
      expect(route.label, 'Aria');
    });

    test('a group chat beats a room code and a title', () {
      final route = PushRoute.resolve(
        groupId: 'g-1',
        groupName: 'Friday crew',
        roomCode: 'AB12CD',
        entityId: '550',
      );
      expect(route.target, PushTarget.group);
      expect(route.threadId, 'g-1');
      expect(route.label, 'Friday crew');
    });

    test('a room code beats a title link', () {
      final route = PushRoute.resolve(
        roomCode: 'ab12cd',
        entityId: '550',
      );
      expect(route.target, PushTarget.room);
      // Codes are upper-cased so a typed/shared code always matches.
      expect(route.threadId, 'AB12CD');
    });

    test('a bare entity id opens the title', () {
      final route = PushRoute.resolve(entityId: '550', poster: 'p.jpg');
      expect(route.target, PushTarget.title);
      expect(route.threadId, '550');
      expect(route.poster, 'p.jpg');
    });

    test('nothing to open decodes to none', () {
      final route = PushRoute.fromData(null);
      expect(route.target, PushTarget.none);
      expect(route.opens, isFalse);
      expect(PushRoute.fromData(const {}).target, PushTarget.none);
    });

    test('a group with no name falls back to the sender name', () {
      final route = PushRoute.resolve(groupId: 'g-1', senderName: 'Aria');
      expect(route.label, 'Aria');
    });

    test('an update push opens the Updates screen', () {
      // v1.3.7's update campaign shipped with no destination at all: the tap
      // only foregrounded the app. kind=updates now resolves to a real screen.
      final route = PushRoute.fromData(const {
        'kind': 'updates',
        'latest_version': '1.3.7',
      });
      expect(route.target, PushTarget.update);
      expect(route.opens, isTrue);
      expect(route.routeName, 'route:update');
      // A chat still wins over the kind, so a social push never misroutes.
      expect(
        PushRoute.resolve(senderUid: 'uid-1', kind: 'updates').target,
        PushTarget.dm,
      );
    });
  });

  group('PushRoute.fromData', () {
    test('reads the social wire keys', () {
      final route = PushRoute.fromData(chatData());
      expect(route.target, PushTarget.dm);
      expect(route.threadId, 'uid-1');
      expect(route.label, 'Aria');
      expect(route.avatar, 'https://cdn/a.jpg');
    });

    test('room_code and group_id are read', () {
      expect(
        PushRoute.fromData({'room_code': 'zz9'}).threadId,
        'ZZ9',
      );
      expect(
        PushRoute.fromData({'group_id': 'g-9', 'group_name': 'Crew'}).label,
        'Crew',
      );
    });

    test('blank and whitespace-only values are ignored', () {
      final route = PushRoute.fromData({
        'sender_uid': '   ',
        'group_id': '',
        'room_code': '  ',
        'entity_id': 'tt123',
      });
      expect(route.target, PushTarget.title);
    });

    test('toData round-trips through fromData', () {
      final original = PushRoute.fromData(chatData());
      final again = PushRoute.fromData(original.toData());
      expect(again.target, original.target);
      expect(again.threadId, original.threadId);
      expect(again.label, original.label);
      expect(again.avatar, original.avatar);

      for (final source in <Map<String, dynamic>>[
        {'group_id': 'g-1', 'group_name': 'Crew'},
        {'room_code': 'ab12'},
        {'entity_id': '550', 'poster': 'p.jpg'},
      ]) {
        final route = PushRoute.fromData(source);
        final copy = PushRoute.fromData(route.toData());
        expect(copy.target, route.target, reason: '$source');
        expect(copy.threadId, route.threadId, reason: '$source');
      }
    });
  });

  group('threadKey', () {
    test('namespaces ids so a uid never collides with a group', () {
      expect(PushRoute.fromData(chatData()).threadKey, 'uid-1');
      expect(
        PushRoute.fromData({'group_id': 'uid-1'}).threadKey,
        'group:uid-1',
      );
      expect(
        PushRoute.fromData({'room_code': 'AB'}).threadKey,
        'room:AB',
      );
      expect(
        PushRoute.fromData({'entity_id': '550'}).threadKey,
        'title:550',
      );
      expect(PushRoute.fromData(null).threadKey, '');
    });

    test('routeName is stable for logs and tests', () {
      expect(PushRoute.fromData(chatData()).routeName, 'route:dm');
      expect(
        PushRoute.fromData({'group_id': 'g'}).routeName,
        'route:group',
      );
      expect(
        PushRoute.fromData({'room_code': 'x'}).routeName,
        'route:room',
      );
      expect(
        PushRoute.fromData({'entity_id': '1'}).routeName,
        'route:title',
      );
      expect(PushRoute.fromData(null).routeName, 'route:none');
    });
  });

  group('PushPayload carries the routing fields', () {
    test('fromData picks up sender, group and room', () {
      final p = PushPayload.fromData({
        ...chatData(),
        'group_id': 'g-1',
        'group_name': 'Crew',
        'room_code': 'ab12',
      });
      expect(p.senderUid, 'uid-1');
      expect(p.senderName, 'Aria');
      expect(p.avatar, 'https://cdn/a.jpg');
      expect(p.groupId, 'g-1');
      expect(p.groupName, 'Crew');
      expect(p.roomCode, 'ab12');
      expect(p.route.target, PushTarget.dm);
    });

    test('a release payload keeps an empty route', () {
      final p = PushPayload.fromData({
        'kind': 'release',
        'title': 'Jawan',
        'entity_type': 'movie',
        'entity_id': '550',
      });
      expect(p.route.target, PushTarget.title);
      expect(p.route.threadId, '550');
    });

    test('tapDataFor round-trips the route', () {
      final original = PushPayload.fromData(chatData());
      final rebuilt = PushPayload.fromData(
        PushService.tapDataFor(original).cast<String, dynamic>(),
      );
      expect(rebuilt.title, original.title);
      expect(rebuilt.body, original.body);
      expect(rebuilt.hasContent, isTrue);
      expect(rebuilt.route.target, original.route.target);
      expect(rebuilt.route.threadId, original.route.threadId);
      expect(rebuilt.route.label, original.route.label);
      expect(rebuilt.route.avatar, original.route.avatar);
    });

    test('tapDataFor adds no social keys for a release push', () {
      final data = PushService.tapDataFor(
        PushPayload.fromData({
          'kind': 'release',
          'title': 'Jawan',
          'entity_id': '550',
        }),
      );
      expect(data.containsKey('sender_uid'), isFalse);
      expect(data.containsKey('group_id'), isFalse);
      expect(data.containsKey('room_code'), isFalse);
      expect(data['entity_id'], '550');
    });
  });

  group('InboxItem route data', () {
    test('add keeps the data blob and encode/decode preserves it', () async {
      NotificationInbox.resetForTest(seed: <InboxItem>[]);
      await NotificationInbox.add(
        title: 'Aria',
        body: 'see you at 8',
        kind: NotificationKind.social,
        id: 'dm-1',
        data: const {'sender_uid': 'uid-1', 'sender_name': 'Aria'},
      );
      final item = NotificationInbox.items.value.single;
      expect(item.route.target, PushTarget.dm);
      expect(item.route.threadId, 'uid-1');

      final round = InboxItem.fromJson(item.toJson());
      expect(round.data['sender_uid'], 'uid-1');
      expect(round.route.target, PushTarget.dm);
    });

    test('an item without data decodes to no route', () {
      final item = InboxItem.fromJson({
        'id': 'x',
        'title': 't',
        'body': 'b',
        'kind': 'releases',
        'at': 1,
      });
      expect(item.data, isEmpty);
      expect(item.route.target, PushTarget.none);
      expect(item.toJson().containsKey('data'), isFalse);
    });

    test('non-string stored values are coerced, not dropped', () {
      final item = InboxItem.fromJson({
        'id': 'x',
        'title': 't',
        'body': 'b',
        'kind': 'social',
        'at': 1,
        'data': {'entity_id': 550, 'sender_uid': ''},
      });
      expect(item.data['entity_id'], '550');
      expect(item.data.containsKey('sender_uid'), isFalse);
      expect(item.route.target, PushTarget.title);
    });

    test('markRead flips one row only', () async {
      NotificationInbox.resetForTest(seed: <InboxItem>[]);
      await NotificationInbox.add(
        title: 'A',
        body: 'a',
        kind: NotificationKind.social,
        id: 'a',
      );
      await NotificationInbox.add(
        title: 'B',
        body: 'b',
        kind: NotificationKind.social,
        id: 'b',
      );
      await NotificationInbox.markRead('a');
      final byId = {
        for (final e in NotificationInbox.items.value) e.id: e.read,
      };
      expect(byId['a'], isTrue);
      expect(byId['b'], isFalse);
    });

    test('markRead on an unknown id changes nothing', () async {
      NotificationInbox.resetForTest(seed: <InboxItem>[]);
      await NotificationInbox.add(
        title: 'A',
        body: 'a',
        kind: NotificationKind.social,
        id: 'a',
      );
      await NotificationInbox.markRead('nope');
      expect(NotificationInbox.items.value.single.read, isFalse);
    });
  });

  group('ActiveThread', () {
    tearDown(ActiveThread.resetForTest);

    test('suppresses only the open thread', () {
      ActiveThread.enter('uid-1');
      expect(ActiveThread.isOpen('uid-1'), isTrue);
      expect(ActiveThread.isOpen('group:uid-1'), isFalse);
      expect(ActiveThread.isOpen(''), isFalse);
      expect(ActiveThread.isOpen(null), isFalse);
    });

    test('a stale leave cannot clear the newer thread', () {
      ActiveThread.enter('uid-1');
      ActiveThread.enter('uid-2');
      ActiveThread.leave('uid-1');
      expect(ActiveThread.isOpen('uid-2'), isTrue);
      ActiveThread.leave('uid-2');
      expect(ActiveThread.key, isNull);
    });

    test('blank enter clears the slot', () {
      ActiveThread.enter('uid-1');
      ActiveThread.enter('  ');
      expect(ActiveThread.key, isNull);
    });
  });
}
