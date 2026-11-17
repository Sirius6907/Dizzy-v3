import 'package:dizzy/pages/social/group_chat_page.dart';
import 'package:dizzy/pages/social/groups_page.dart';
import 'package:dizzy/services/social/dizzy_group_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase A (Groups UI): hub renders the empty state, lists my groups,
/// and opens the chat for a tapped group.
void main() {
  group('GroupsPage', () {
    tearDown(() {
      DizzyGroupService.myGroups.value = const [];
      DizzyGroupService.myRoles.value = const {};
    });

    testWidgets('empty state offers create + join', (tester) async {
      DizzyGroupService.myGroups.value = const [];

      await tester.pumpWidget(const MaterialApp(home: GroupsPage()));
      await tester.pumpAndSettle();

      expect(find.text('Groups'), findsWidgets);
      expect(find.text('No groups yet'), findsOneWidget);
      expect(find.text('Create a group'), findsOneWidget);
      expect(find.text('Join with a code'), findsOneWidget);
    });

    testWidgets('lists groups from the service notifier', (tester) async {
      DizzyGroupService.myGroups.value = [
        DizzyGroup(
          groupId: 'grp:aaa111',
          name: 'Movie Night',
          ownerId: 'u1',
          memberCount: 4,
          lastMessage: 'who is bringing snacks?',
          lastKind: 'text',
          lastMessageAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        const DizzyGroup(
          groupId: 'grp:bbb222',
          name: 'Cricket Crew',
          ownerId: 'u2',
          memberCount: 2,
        ),
      ];

      await tester.pumpWidget(const MaterialApp(home: GroupsPage()));
      await tester.pumpAndSettle();

      expect(find.text('Movie Night'), findsOneWidget);
      expect(find.text('Cricket Crew'), findsOneWidget);
      expect(find.text('who is bringing snacks?'), findsOneWidget);
      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.text('4 members'), findsOneWidget);
      expect(find.text('2 members'), findsOneWidget);
      expect(find.text('No groups yet'), findsNothing);
    });

    testWidgets('media card preview is readable, not raw text', (tester) async {
      DizzyGroupService.myGroups.value = [
        const DizzyGroup(
          groupId: 'grp:ccc333',
          name: 'Watch Party',
          ownerId: 'u1',
          memberCount: 3,
          lastMessage: 'Join my Watch Together room: R7K2',
          lastKind: 'media_card',
        ),
      ];

      await tester.pumpWidget(const MaterialApp(home: GroupsPage()));
      await tester.pumpAndSettle();

      expect(find.text('🎬 Watch Together card'), findsOneWidget);
    });

    testWidgets('tapping a group opens its chat', (tester) async {
      DizzyGroupService.myGroups.value = [
        const DizzyGroup(
          groupId: 'grp:ddd444',
          name: 'Sunday Squad',
          ownerId: 'u1',
          memberCount: 5,
        ),
      ];

      await tester.pumpWidget(const MaterialApp(home: GroupsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sunday Squad'));
      await tester.pumpAndSettle();

      expect(find.byType(GroupChatPage), findsOneWidget);
      // Chat title shows the group name + member count from the row.
      expect(find.text('Sunday Squad'), findsWidgets);
      expect(find.text('5 members'), findsOneWidget);
    });
  });
}
