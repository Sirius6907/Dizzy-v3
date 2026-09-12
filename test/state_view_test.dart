import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/widgets/common/error_view.dart';
import 'package:dizzy/widgets/common/state_view.dart';

/// Polish P10: trio contract — illustration + Easy English + ONE action.
/// Raw tech text never reaches the screen.
void main() {
  group('StateViewCopy.friendlyError', () {
    test('net failure → easy net line', () {
      expect(
        StateViewCopy.friendlyError('SocketException: failed host lookup'),
        contains('Internet is slow or off'),
      );
      expect(
        StateViewCopy.friendlyError('TimeoutException after 0:00:10'),
        contains('Internet is slow or off'),
      );
    });

    test('auth failure → login line', () {
      expect(
        StateViewCopy.friendlyError('Http 403 forbidden'),
        contains('Login needed'),
      );
    });

    test('missing → not-found line', () {
      expect(
        StateViewCopy.friendlyError('Http 404 not found'),
        contains('Not found'),
      );
    });

    test('unknown → generic line, raw never leaks', () {
      const raw = 'RangeError (index): Invalid value: boom-42';
      final friendly = StateViewCopy.friendlyError(raw);
      expect(friendly, contains('Something went wrong'));
      expect(friendly, isNot(contains('boom-42')));
    });

    test('null → generic line', () {
      expect(
        StateViewCopy.friendlyError(null),
        contains('Something went wrong'),
      );
    });
  });

  group('ErrorView widget', () {
    testWidgets('shows trio + hides raw text', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(
              error: 'SocketException: OS Error boom-99',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      // Trio present.
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.textContaining('Internet is slow or off'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      // Raw tech text hidden.
      expect(find.textContaining('boom-99'), findsNothing);
      // Action works.
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });

    testWidgets('DizzyStateView empty variant renders action', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DizzyStateView(
              icon: Icons.inbox_rounded,
              title: 'Nothing here',
              line: StateViewCopy.friendlyEmpty('downloads'),
              actionLabel: 'Explore',
              onAction: () {},
            ),
          ),
        ),
      );
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('No downloads yet. Explore and add some you love.'),
          findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
    });
  });
}
