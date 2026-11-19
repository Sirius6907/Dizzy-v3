import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/social/dizzy_group_service.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
import 'package:dizzy/services/social/social_hub_service.dart';

DizzyDirectMessage _msg({
  required String sender,
  required DateTime at,
  String body = 'hi',
}) {
  return DizzyDirectMessage(
    id: 'm${at.microsecondsSinceEpoch}',
    threadId: 'dm:a_b',
    senderId: sender,
    clientMsgId: 'c${at.microsecondsSinceEpoch}',
    kind: 'text',
    body: body,
    createdAt: at,
  );
}

void main() {
  group('SocialHubService.unreadCountFor', () {
    final base = DateTime(2026, 11, 20, 12);

    test('counts only incoming messages after the cursor', () {
      final messages = [
        _msg(sender: 'me', at: base.subtract(const Duration(minutes: 5))),
        _msg(sender: 'friend', at: base.subtract(const Duration(minutes: 4))),
        _msg(sender: 'friend', at: base.add(const Duration(minutes: 1))),
        _msg(sender: 'friend', at: base.add(const Duration(minutes: 2))),
      ];
      final n = SocialHubService.unreadCountFor(
        messages: messages,
        myUid: 'me',
        cursor: base,
      );
      expect(n, 2);
    });

    test('own messages never count, even after the cursor', () {
      final messages = [
        _msg(sender: 'me', at: base.add(const Duration(minutes: 1))),
        _msg(sender: 'me', at: base.add(const Duration(minutes: 2))),
      ];
      expect(
        SocialHubService.unreadCountFor(
          messages: messages,
          myUid: 'me',
          cursor: null,
        ),
        0,
      );
    });

    test('a null cursor treats all incoming history as unread', () {
      final messages = [
        _msg(sender: 'friend', at: base.subtract(const Duration(days: 3))),
        _msg(sender: 'friend', at: base),
        _msg(sender: 'me', at: base),
      ];
      expect(
        SocialHubService.unreadCountFor(
          messages: messages,
          myUid: 'me',
          cursor: null,
        ),
        2,
      );
    });

    test('cursor equality is read, not unread', () {
      final messages = [_msg(sender: 'friend', at: base)];
      expect(
        SocialHubService.unreadCountFor(
          messages: messages,
          myUid: 'me',
          cursor: base,
        ),
        0,
      );
    });
  });

  group('SocialHubService.latestStamp', () {
    test('returns the newest message time', () {
      final older = DateTime(2026, 11, 20, 9);
      final newer = DateTime(2026, 11, 20, 11);
      expect(
        SocialHubService.latestStamp([
          _msg(sender: 'a', at: older),
          _msg(sender: 'b', at: newer),
        ]),
        newer,
      );
    });

    test('empty history has no stamp', () {
      expect(SocialHubService.latestStamp(const []), isNull);
    });
  });

  group('SocialHubService.groupUnreadCountFor', () {
    final base = DateTime(2026, 11, 20, 18);

    DizzyGroupMessage gm(String sender, DateTime at) => DizzyGroupMessage(
      id: 'g${at.microsecondsSinceEpoch}',
      groupId: 'grp:abc',
      senderId: sender,
      clientMsgId: 'c${at.microsecondsSinceEpoch}',
      kind: 'text',
      body: 'hi',
      createdAt: at,
    );

    test('counts incoming group messages after the cursor', () {
      final messages = [
        gm('me', base.add(const Duration(minutes: 1))),
        gm('friend', base.subtract(const Duration(minutes: 1))),
        gm('friend', base.add(const Duration(minutes: 2))),
      ];
      expect(
        SocialHubService.groupUnreadCountFor(
          messages: messages,
          myUid: 'me',
          cursor: base,
        ),
        1,
      );
    });

    test('no cursor means the whole group history is unread', () {
      final messages = [
        gm('friend', base.subtract(const Duration(days: 1))),
        gm('friend', base),
      ];
      expect(
        SocialHubService.groupUnreadCountFor(
          messages: messages,
          myUid: 'me',
          cursor: null,
        ),
        2,
      );
    });
  });

  group('SocialHubService cursor storage', () {
    test('markRead never moves a cursor backwards', () async {
      SharedPreferences.setMockInitialValues({});
      final later = DateTime(2026, 11, 20, 20);
      final earlier = DateTime(2026, 11, 20, 10);

      await SocialHubService.markRead('dm:test', through: later);
      await SocialHubService.markRead('dm:test', through: earlier);

      final cursor = await SocialHubService.readCursor('dm:test');
      expect(cursor, later);
    });

    test('an unopened thread has no cursor', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await SocialHubService.readCursor('dm:never'), isNull);
    });
  });

  group('DizzySocialService.displayNameFor', () {
    tearDown(() => DizzySocialService.resolvedNames.value = const {});

    test('prefers the resolved @username', () {
      DizzySocialService.resolvedNames.value = {'u1': 'riya'};
      expect(DizzySocialService.displayNameFor('u1'), 'riya');
    });

    test('never returns a raw id or friend_<uid> placeholder', () {
      final label = DizzySocialService.displayNameFor('0f8a1b2c-3333-4444');
      expect(label, isNotEmpty);
      expect(label.startsWith('friend_'), isFalse);
      expect(label.contains('0f8a1b2c'), isFalse);
    });

    test('empty uid still gets a human label', () {
      expect(DizzySocialService.displayNameFor(''), 'Dizzy member');
    });
  });
}
