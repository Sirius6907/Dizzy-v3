import 'package:dizzy/pages/music/widgets/music_top_header.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final palette in AppThemeService.palettes) {
      testWidgets('${palette.name} search remains usable at $width', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        AppThemeService.currentPalette.value = palette;
        var query = '';
        var settingsOpened = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: MusicTopHeader(
                  isDesktop: width >= 1000,
                  searchController: controller,
                  searchFocusNode: focus,
                  isSearching: false,
                  onSearchChanged: (value) => query = value,
                  onClearSearch: controller.clear,
                  onSettingsTap: () => settingsOpened = true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final field = find.byKey(const ValueKey('music-search-field'));
        expect(field, findsOneWidget);
        final decoration =
            tester.widget<Container>(field).decoration! as BoxDecoration;
        expect(decoration.border, isNotNull);
        expect(decoration.borderRadius, BorderRadius.circular(14));
        expect(
          tester.getSize(find.byType(TextField)).width,
          greaterThanOrEqualTo(140),
        );
        await tester.enterText(find.byType(TextField), 'Paani Waala Dance');
        expect(query, 'Paani Waala Dance');
        expect(controller.text, query);
        if (width < 600) {
          await tester.tap(find.byTooltip('Music options'));
          await tester.pumpAndSettle();
          expect(find.text('Audio source'), findsOneWidget);
          expect(find.text('Music Atmosphere Settings'), findsOneWidget);
          await tester.tap(find.text('App Settings'));
          await tester.pumpAndSettle();
        } else {
          await tester.tap(find.byTooltip('App Settings'));
        }
        expect(settingsOpened, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
