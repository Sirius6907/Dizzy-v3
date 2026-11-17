import 'package:dizzy/pages/music/onboarding/music_onboarding_wizard.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('wizard Next advances artist -> style -> mood in edit mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'music_onboarding_complete': true,
    });
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppThemeService.currentPalette.value = AppThemeService.palettes.first;

    await tester.pumpWidget(
      const MaterialApp(home: MusicOnboardingWizard(settingsMode: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Your Music Vibe'), findsOneWidget);
    expect(find.text('Pick your favorite singers'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('What do you listen to?'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Pick your favorite singers'), findsNothing);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('What do you listen to?'), findsOneWidget);
  });
}
