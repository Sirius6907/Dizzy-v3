import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';

void main() {
  setUp(() {
    AppThemeService.currentPalette.value = AppThemeService.palettes.first;
    AppThemeService.currentThemeId.value = AppThemeService.palettes.first.id;
  });

  group('Two-theme switch controller', () {
    test('exposes exactly light clay and dark clay', () {
      expect(AppThemeService.currentThemeId, isA<ValueNotifier<String>>());
      expect(
        AppThemeService.palettes.map((p) => p.id).toList(),
        ['prism_light', 'prism_dark'],
      );
      expect(
        AppThemeService.palettes.firstWhere((p) => p.id == 'prism_light').isLight,
        isTrue,
      );
      expect(
        AppThemeService.palettes.firstWhere((p) => p.id == 'prism_dark').isLight,
        isFalse,
      );
    });

    test('switchTheme updates both notifiers and persists', () async {
      SharedPreferences.setMockInitialValues({});
      await AppThemeService.initialize();
      await AppThemeService.switchTheme('prism_light');

      expect(AppThemeService.currentThemeId.value, 'prism_light');
      expect(AppThemeService.currentPalette.value.id, 'prism_light');
      expect(
        AppThemeService.createThemeData(
          AppThemeService.currentPalette.value,
        ).brightness,
        Brightness.light,
      );
    });
  });

  group('Ink contract', () {
    test('light clay paints black text', () {
      final theme = AppThemeService.createThemeData(
        AppThemeService.palettes.firstWhere((p) => p.id == 'prism_light'),
      );
      expect(theme.colorScheme.onSurface, PrismLight.ink);
      expect(theme.colorScheme.onSurface, const Color(0xFF000000));
      expect(theme.textTheme.bodyMedium?.color, const Color(0xFF000000));
    });

    test('dark clay paints white text', () {
      final theme = AppThemeService.createThemeData(
        AppThemeService.palettes.firstWhere((p) => p.id == 'prism_dark'),
      );
      expect(theme.colorScheme.onSurface, PrismDark.ink);
      expect(theme.colorScheme.onSurface, const Color(0xFFFFFFFF));
      expect(theme.textTheme.bodyMedium?.color, const Color(0xFFFFFFFF));
    });
  });

  group('Legacy palette migration', () {
    test('a retired light id boots into light clay', () async {
      SharedPreferences.setMockInitialValues({
        'app_theme_id': 'light_aluminum',
      });
      await AppThemeService.initialize();
      expect(AppThemeService.currentPalette.value.id, 'prism_light');
    });

    test('a retired dark id boots into dark clay', () async {
      SharedPreferences.setMockInitialValues({'app_theme_id': 'cyberpunk'});
      await AppThemeService.initialize();
      expect(AppThemeService.currentPalette.value.id, 'prism_dark');
    });
  });

  group('Static tactile gradients', () {
    test('dark mode exposes the hardware surface gradients', () {
      AppThemeService.currentThemeId.value = 'prism_dark';
      AppThemeService.currentPalette.value = AppThemeService.palettes
          .firstWhere((p) => p.id == 'prism_dark');

      expect(DizzyGradients.surface.colors, [
        DizzyVoid.surface2,
        DizzyVoid.surface1,
      ]);
      expect(DizzyGradients.raised.colors, [
        DizzyVoid.surface3,
        DizzyVoid.surface2,
      ]);
      expect(DizzyGradients.darkMetal.colors, const [
        Color(0xFF3A3E4A),
        Color(0xFF1C202C),
      ]);
      expect(DizzyGradients.accent.colors, const [
        DizzyGlow.red,
        DizzyGlow.ember,
      ]);
    });

    test('light mode selects the silver-tinted surface gradients', () {
      AppThemeService.currentThemeId.value = 'prism_light';
      AppThemeService.currentPalette.value = AppThemeService.palettes
          .firstWhere((p) => p.id == 'prism_light');

      expect(DizzyGradients.surface.colors, const [
        Color(0xFFFFFFFF),
        Color(0xFFC0C8D4),
      ]);
      expect(DizzyGradients.raised.colors, const [
        Color(0xFFFFFFFF),
        Color(0xFFC0C8D4),
      ]);
    });

    test('pressed is an inverted tactile gradient', () {
      expect(DizzyGradients.pressed.colors, isNotEmpty);
      expect(DizzyGradients.pressed.begin, Alignment.topCenter);
      expect(DizzyGradients.pressed.end, Alignment.bottomCenter);
    });
  });

  group('theme-aware tactile shadows', () {
    test('light mode uses dark drop shadows', () {
      AppThemeService.currentThemeId.value = 'prism_light';
      AppThemeService.currentPalette.value = AppThemeService.palettes
          .firstWhere((p) => p.id == 'prism_light');

      final shadow = DizzyShadow.card.first;
      expect(shadow.color, const Color(0x331A1D26));
      expect(shadow.offset, const Offset(0, 8));
    });

    test('dark mode keeps a subtle light edge catch', () {
      AppThemeService.currentThemeId.value = 'prism_dark';
      AppThemeService.currentPalette.value = AppThemeService.palettes
          .firstWhere((p) => p.id == 'prism_dark');

      expect(DizzyShadow.card.last.color, const Color(0x12FFFFFF));
    });
  });
}
