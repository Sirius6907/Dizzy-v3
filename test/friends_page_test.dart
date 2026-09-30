import 'package:dizzy/pages/social/friends_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 2 (Friends UI): page renders 3 tabs, search field, empty states.
void main() {
  group('FriendsPage', () {
    testWidgets('renders 3 tabs + search field', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: FriendsPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Friends'), findsWidgets);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.textContaining('@username'), findsWidgets);
    });

    testWidgets('search tab shows empty hint initially', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: FriendsPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Search any @username to add friends.'),
          findsOneWidget);
    });

    testWidgets('requests + friends tabs show empty states', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: FriendsPage()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Requests').last);
      await tester.pumpAndSettle();
      expect(find.text('No requests right now.'), findsOneWidget);

      await tester.tap(find.text('Friends').last);
      await tester.pumpAndSettle();
      expect(find.text('No friends yet — search above to add some!'),
          findsOneWidget);
    });
  });
}
