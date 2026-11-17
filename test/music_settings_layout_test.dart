import 'package:dizzy/pages/settings/appearance/music_settings_page.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final palette in AppThemeService.palettes) {
      testWidgets('${palette.name} music settings fit $width', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppThemeService.currentPalette.value = palette;
        await tester.pumpWidget(const MaterialApp(home: MusicSettingsPage()));
        await tester.pump();
        expect(find.text('Custom Music Player Studio'), findsOneWidget);
        expect(find.text('Your Music Vibe'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });

      // Regression: the custom-player-studio preview header row
      // ('Live Waveform & Controls Preview' + 'Open Full Studio') overflowed
      // by 35px at ~390dp before the header text was made flexible.
      testWidgets(
        '${palette.name} custom studio preview header fits $width',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = Size(width, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          AppThemeService.currentPalette.value = palette;
          await tester.pumpWidget(const MaterialApp(home: MusicSettingsPage()));
          await tester.pump();

          await tester.scrollUntilVisible(
            find.text('Live Waveform & Controls Preview'),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();

          expect(find.text('Live Waveform & Controls Preview'), findsOneWidget);
          expect(find.text('Open Full Studio ➔'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
