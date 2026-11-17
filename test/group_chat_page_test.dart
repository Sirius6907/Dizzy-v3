import 'package:dizzy/pages/social/group_chat_page.dart';
import 'package:dizzy/services/social/dizzy_group_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DizzyGroupMessage _msg({
  String id = 'm1',
  String kind = 'text',
  String body = 'hello',
  String? mediaRef,
  String senderId = 'friend-uid',
}) =>
    DizzyGroupMessage(
      id: id,
      groupId: 'grp:test',
      senderId: senderId,
      clientMsgId: 'c-$id',
      kind: kind,
      body: body,
      mediaRef: mediaRef,
      createdAt: DateTime(2026, 11, 18, 14, 5),
    );

/// Phase A (Groups UI): chat renders history, sends text, and never loses
/// what the user typed when a send fails.
void main() {
  group('GroupChatPage', () {
    testWidgets('renders injected history', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatPage(
            groupId: 'grp:test',
            groupName: 'Movie Night',
            memberCount: 3,
            loadHistory: (_) async => [
              _msg(id: 'a', body: 'first message'),
              _msg(id: 'b', body: 'second message'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('first message'), findsOneWidget);
      expect(find.text('second message'), findsOneWidget);
      expect(find.text('Message the group...'), findsOneWidget);
    });

    testWidgets('empty chat shows the say-hi hint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatPage(
            groupId: 'grp:test',
            groupName: 'Movie Night',
            loadHistory: (_) async => const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Say hi to Movie Night'), findsOneWidget);
    });

    testWidgets('sending clears the field and passes the group id',
        (tester) async {
      String? sentGroupId;
      String? sentBody;
      String? sentKind;
      String? sentRef;

      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatPage(
            groupId: 'grp:test',
            groupName: 'Movie Night',
            loadHistory: (_) async => const [],
            send: ({
              required String groupId,
              required String body,
              String kind = 'text',
              String? mediaRef,
            }) async {
              sentGroupId = groupId;
              sentBody = body;
              sentKind = kind;
              sentRef = mediaRef;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  yo team  ');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();

      expect(sentGroupId, 'grp:test');
      expect(sentBody, 'yo team');
      expect(sentKind, 'text');
      expect(sentRef, isNull);
      // Field is empty again — the hint is back and the text is gone.
      expect(find.text('yo team'), findsNothing);
      expect(find.text('Message the group...'), findsOneWidget);
    });

    testWidgets('failed send keeps the typed text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatPage(
            groupId: 'grp:test',
            groupName: 'Movie Night',
            loadHistory: (_) async => const [],
            send: ({
              required String groupId,
              required String body,
              String kind = 'text',
              String? mediaRef,
            }) async =>
                false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'keep me');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();

      expect(find.text('keep me'), findsOneWidget);
    });

    testWidgets('media card bubble offers join with the room code',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatPage(
            groupId: 'grp:test',
            groupName: 'Movie Night',
            loadHistory: (_) async => [
              _msg(
                id: 'card',
                kind: 'media_card',
                body: 'Join my Watch Together room: R7K2',
                mediaRef: 'party:R7K2',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Watch Together'), findsWidgets);
      expect(find.text('Room R7K2 — tap to join.'), findsOneWidget);
      expect(find.text('Join room'), findsOneWidget);
    });
  });
}
