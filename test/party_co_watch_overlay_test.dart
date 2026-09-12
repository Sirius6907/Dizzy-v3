import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/widgets/party/party_co_watch_overlay.dart';

/// Polish P5: co-watch overlay copy never regresses to tech-speak.
/// Dadi-ma test — Easy English only.
void main() {
  group('PartyCoWatchOverlay', () {
    testWidgets('catching up shows Easy English + spinner',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PartyCoWatchOverlay(
              kind: PartyOverlayKind.catchingUp,
            ),
          ),
        ),
      );
      expect(find.text('Catching up with host…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('paused by host shows Easy English, no tech words',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PartyCoWatchOverlay(
              kind: PartyOverlayKind.pausedByHost,
            ),
          ),
        ),
      );
      expect(find.text('Host paused. You just watch.'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
    });

    testWidgets('paused with title names the title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PartyCoWatchOverlay(
              kind: PartyOverlayKind.pausedByHost,
              hostTitle: 'Dune',
            ),
          ),
        ),
      );
      expect(find.text('Host paused • Dune'), findsOneWidget);
    });
  });
}
