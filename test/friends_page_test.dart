import 'dart:async';

import 'package:dizzy/pages/social/friends_page.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
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

    testWidgets('debounces input and passes the trimmed username to lookup',
        (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);

      await tester.enterText(find.byType(TextField), 'al');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), '  @alice  ');
      await tester.pump(const Duration(milliseconds: 399));
      expect(lookup.queries, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(lookup.queries, ['alice']);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      lookup.requests.single.complete([_alice]);
      await tester.pump();
      expect(find.text('@alice'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('newer results survive reversed completions', (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);
      await _searchFor(tester, 'alice');
      await _searchFor(tester, 'bobby');

      lookup.requests[1].complete([_bobby]);
      await tester.pump();
      lookup.requests[0].complete([_alice]);
      await tester.pump();

      expect(find.text('@bobby'), findsOneWidget);
      expect(find.text('@alice'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('invalidates pending results before the next debounce fires',
        (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);
      await _searchFor(tester, 'alice');
      await tester.enterText(find.byType(TextField), 'bobby');

      lookup.requests[0].complete([_alice]);
      await tester.pump(const Duration(milliseconds: 399));
      expect(lookup.queries, ['alice']);
      expect(find.text('@alice'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      lookup.requests[1].complete([_bobby]);
      await tester.pump();
      expect(find.text('@bobby'), findsOneWidget);
    });

    testWidgets('stale completion cannot settle the current spinner',
        (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);
      await _searchFor(tester, 'alice');
      await _searchFor(tester, 'bobby');

      lookup.requests[0].complete([_alice]);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('@alice'), findsNothing);
      lookup.requests[1].complete([_bobby]);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    for (final input in ['', 'a', '@a', ' @ ']) {
      testWidgets('clearing to "$input" immediately settles pending search',
          (tester) async {
        final lookup = _ControlledLookup();
        await _showFriends(tester, lookup);
        await _searchFor(tester, 'alice');
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.enterText(find.byType(TextField), input);
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Search any @username to add friends.'), findsOneWidget);
        lookup.requests[0].complete([_alice]);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('@alice'), findsNothing);
        expect(lookup.queries, ['alice']);
        expect(find.text('Retry'), findsNothing);
      });
    }

    testWidgets('successful empty lookup shows no results, not a failure',
        (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);
      await _searchFor(tester, 'nobody');
      lookup.requests.single.complete([]);
      await tester.pump();

      expect(find.text('No users found.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('failed lookup settles and can retry the same query',
        (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);
      await _searchFor(tester, '  @alice  ');
      lookup.requests.single.completeError(StateError('offline'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining("Couldn't search"), findsOneWidget);
      expect(find.text('No users found.'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(lookup.queries, ['alice', 'alice']);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      lookup.requests[1].complete([_alice]);
      await tester.pump();
      expect(find.text('@alice'), findsOneWidget);
      expect(find.textContaining("Couldn't search"), findsNothing);
    });

    testWidgets('times out at eight seconds and ignores a late completion',
        (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);
      await _searchFor(tester, 'alice');
      await tester.pump(const Duration(milliseconds: 7999));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining("Couldn't search"), findsOneWidget);
      expect(find.text('No users found.'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 400));
      lookup.requests[1].complete([_bobby]);
      await tester.pump();
      lookup.requests[0].complete([_alice]);
      await tester.pump();
      expect(find.text('@bobby'), findsOneWidget);
      expect(find.text('@alice'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('stale failure during debounce cannot show a retry error',
        (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);
      await _searchFor(tester, 'alice');
      await tester.enterText(find.byType(TextField), 'bobby');
      lookup.requests[0].completeError(StateError('old failure'));
      await tester.pump(const Duration(milliseconds: 399));
      expect(tester.takeException(), isNull);
      expect(find.text('Retry'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      lookup.requests[1].complete([_bobby]);
      await tester.pump();
      expect(find.text('@bobby'), findsOneWidget);
    });

    testWidgets('stale timeout cannot settle a newer pending search',
        (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);
      await _searchFor(tester, 'alice');
      await tester.pump(const Duration(seconds: 4));
      await _searchFor(tester, 'bobby');
      await tester.pump(const Duration(milliseconds: 3600));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      lookup.requests[1].complete([_bobby]);
      lookup.requests[0].completeError(StateError('late failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('@bobby'), findsOneWidget);
    });

    testWidgets('default lookup reports unavailable service as retryable',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FriendsPage()));
      await _searchFor(tester, 'alice');
      expect(find.textContaining("Couldn't search"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No users found.'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('synchronous lookup failure also settles the spinner',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: FriendsPage(lookup: (_) => throw StateError('unavailable')),
      ));
      await _searchFor(tester, 'alice');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('dispose cancels a lookup still waiting for debounce',
        (tester) async {
      final lookup = _ControlledLookup();
      await _showFriends(tester, lookup);
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 9));
      expect(lookup.queries, isEmpty);
      expect(tester.takeException(), isNull);
    });

    for (final fail in [false, true]) {
      testWidgets('dispose ignores pending ${fail ? 'failure' : 'success'}',
          (tester) async {
        final lookup = _ControlledLookup();
        await _showFriends(tester, lookup);
        await _searchFor(tester, 'alice');
        await tester.pumpWidget(const SizedBox.shrink());
        if (fail) {
          lookup.requests.single.completeError(StateError('disposed'));
        } else {
          lookup.requests.single.complete([_alice]);
        }
        await tester.pump(const Duration(seconds: 9));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

const _alice = DizzyUserMatch(
  userId: 'user-alice',
  username: 'alice',
  displayName: 'Alice',
);
const _bobby = DizzyUserMatch(
  userId: 'user-bobby',
  username: 'bobby',
  displayName: 'Bobby',
);

class _ControlledLookup {
  final queries = <String>[];
  final requests = <Completer<List<DizzyUserMatch>>>[];

  Future<List<DizzyUserMatch>> call(String query) {
    queries.add(query);
    final request = Completer<List<DizzyUserMatch>>();
    requests.add(request);
    return request.future;
  }
}

Future<void> _showFriends(WidgetTester tester, _ControlledLookup lookup) async {
  await tester.pumpWidget(MaterialApp(home: FriendsPage(lookup: lookup.call)));
}

Future<void> _searchFor(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 400));
}
