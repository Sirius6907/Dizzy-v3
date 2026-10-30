import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';
import 'package:dizzy/widgets/prism/prism_button.dart';

/// Prism v2 foundation — SPEC §2 locked tokens + elevation ladder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrismShadows', () {
    test('resting returns dual shadows (light + dark)', () {
      final shadows = PrismShadows.resting(isLight: true);
      expect(shadows, hasLength(2));
    });

    test('raised returns dual shadows', () {
      expect(PrismShadows.raised(isLight: false), hasLength(2));
    });

    test('floating adds halo (3 shadows)', () {
      final shadows = PrismShadows.floating(
        isLight: true,
        halo: PrismAccent.accent,
      );
      expect(shadows, hasLength(3));
    });

    test('floating without halo returns 2 shadows', () {
      expect(PrismShadows.floating(isLight: true), hasLength(2));
    });

    test('pressed returns dual shadows', () {
      expect(PrismShadows.pressed(isLight: true), hasLength(2));
    });

    test('soft returns dual shadows', () {
      expect(PrismShadows.soft(isLight: false), hasLength(2));
    });

    test('scale multiplies blur radius', () {
      final soft = PrismShadows.raised(isLight: true, scale: 0.5);
      final deep = PrismShadows.raised(isLight: true, scale: 1.5);
      expect(deep[0].blurRadius, greaterThan(soft[0].blurRadius));
    });

    test('poster frame adds glow only when hovered', () {
      final plain = PrismFrame.poster(isLight: true);
      final hovered = PrismFrame.poster(
        isLight: true,
        hovered: true,
        glow: PrismAccent.accent,
      );
      expect(plain, hasLength(2));
      expect(hovered, hasLength(3));
    });
  });

  group('Prism palettes', () {
    test('light prism is default for fresh installs', () async {
      SharedPreferences.setMockInitialValues({});
      await AppThemeService.initialize();
      expect(AppThemeService.currentPalette.value.id, 'prism_light');
      expect(AppThemeService.currentPalette.value.isLight, isTrue);
    });

    test('saved dark prism survives restart', () async {
      SharedPreferences.setMockInitialValues({'app_theme_id': 'prism_dark'});
      await AppThemeService.initialize();
      expect(AppThemeService.currentPalette.value.id, 'prism_dark');
    });

    test('legacy light id migrates to prism light', () async {
      SharedPreferences.setMockInitialValues({'app_theme_id': 'light_silver'});
      await AppThemeService.initialize();
      expect(AppThemeService.currentPalette.value.id, 'prism_light');
    });

    test('legacy dark id (amethyst) migrates to prism dark', () async {
      SharedPreferences.setMockInitialValues({'app_theme_id': 'amethyst'});
      await AppThemeService.initialize();
      expect(AppThemeService.currentPalette.value.id, 'prism_dark');
      expect(AppThemeService.currentPalette.value.isLight, isFalse);
      expect(AppThemeService.currentThemeId.value, 'prism_dark');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_id'), 'prism_dark');
    });

    test('second initialize keeps an already-migrated id', () async {
      SharedPreferences.setMockInitialValues({'app_theme_id': 'amethyst'});
      await AppThemeService.initialize();
      expect(AppThemeService.currentPalette.value.id, 'prism_dark');

      // Restart with 'prism_dark' already on disk: the migration must be a
      // no-op (never re-run, never flip a Prism id back to another palette).
      await AppThemeService.initialize();
      expect(AppThemeService.currentPalette.value.id, 'prism_dark');
      expect(AppThemeService.currentThemeId.value, 'prism_dark');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_id'), 'prism_dark');
    });
  });

  group('PrismIconButton hit area', () {
    testWidgets('the 48dp ring around the visual circle is tappable', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PrismIconButton(
                icon: Icons.add,
                size: 40,
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(PrismIconButton));
      expect(rect.width, PrismSpace.giant);
      expect(rect.height, PrismSpace.giant);

      // Corner of the 48dp box: outside the 40dp visual circle, inside the
      // transparent ring. This failed when the ring sat outside the gesture.
      await tester.tapAt(rect.topLeft + const Offset(2, 2));
      expect(taps, 1);
    });

    testWidgets('a disabled icon button does not take taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const PrismIconButton(icon: Icons.add, size: 40),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PrismIconButton));
      // The card-level tap fires; no recognizer of the disabled button claims
      // the pointer first.
      expect(taps, 1);
    });
  });
}
