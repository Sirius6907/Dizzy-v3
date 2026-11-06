import 'package:dizzy/pages/common/notification_center_sheet.dart';
import 'package:dizzy/services/notification/notification_prefs.dart';
import 'package:dizzy/services/notification/notification_service.dart';
import 'package:dizzy/widgets/cloud/consent_onboarding_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-reported light-theme defects:
///   * consent copy was hardcoded white on a light sheet;
///   * the recommendation voice had no visible control.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('consent copy uses theme ink, not hardcoded white', (tester) async {
    final theme = ThemeData.light();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: ConsentOnboardingSheet()),
      ),
    );

    final title = tester.widget<Text>(find.text('Your privacy, your call'));
    final body = tester.widget<Text>(
      find.textContaining('Dizzy works without an account'),
    );

    expect(title.style?.color, theme.colorScheme.onSurface);
    expect(body.style?.color, theme.colorScheme.onSurfaceVariant);
    expect(title.style?.color, isNot(Colors.white));
  });

  testWidgets('recommendation style can be switched and persisted',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NotificationCenterSheet())),
    );

    await tester.scrollUntilVisible(
      find.text('Recommendation style'),
      200,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('Warm'), findsOneWidget);
    expect(find.text('Playful'), findsOneWidget);

    await tester.tap(find.text('Warm'));
    await tester.pump();

    expect(NotificationService.gate.tone, NotificationTone.warm);
    expect(
      (tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Warm'),
          matching: find.byType(ChoiceChip),
        ),
      )).selected,
      isTrue,
    );
  });
}
