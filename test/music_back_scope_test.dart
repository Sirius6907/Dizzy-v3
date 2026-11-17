import 'package:dizzy/pages/music/widgets/music_back_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The music player, queue and lyrics are in-page overlays, not routes.
/// Android back must therefore close a layer first, and only leave the
/// section when nothing is open — otherwise the user is thrown to the app
/// home while the now-playing screen is still on top.
void main() {
  Future<void> systemBack(WidgetTester tester) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'flutter/navigation',
          const JSONMethodCodec().encodeMethodCall(
            const MethodCall('popRoute'),
          ),
          (_) {},
        );
    await tester.pumpAndSettle();
  }

  Widget app({
    required bool hasOverlay,
    required VoidCallback onDismiss,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MusicBackScope(
                    hasOverlay: hasOverlay,
                    onDismiss: onDismiss,
                    child: const Scaffold(body: Text('music home')),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('back closes the open layer instead of leaving the section', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(app(hasOverlay: true, onDismiss: () => dismissed++));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('music home'), findsOneWidget);

    await systemBack(tester);

    expect(dismissed, 1, reason: 'the topmost layer consumed the back press');
    expect(
      find.text('music home'),
      findsOneWidget,
      reason: 'still inside the music section, not on the app home',
    );
  });

  testWidgets('back leaves the section once no layer is open', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(
      app(hasOverlay: false, onDismiss: () => dismissed++),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('music home'), findsOneWidget);

    await systemBack(tester);

    expect(dismissed, 0);
    expect(
      find.text('music home'),
      findsNothing,
      reason: 'a plain section exit pops the route as usual',
    );
  });
}
