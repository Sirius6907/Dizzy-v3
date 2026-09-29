import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';

void main() {
  setUp(() {
    AppThemeService.currentPalette.value = AppThemeService.palettes.first;
    AppThemeService.currentThemeId.value = AppThemeService.palettes.first.id;
  });

  group('Phase 7 theme switch controller', () {
    test('exposes a reactive theme id and light/dark palettes', () {
      expect(AppThemeService.currentThemeId, isA<ValueNotifier<String>>());
      expect(AppThemeService.palettes.any((p) => p.id == 'light_aluminum'), isTrue);
      expect(AppThemeService.palettes.any((p) => p.id == 'light_silver'), isTrue);
      expect(
        AppThemeService.palettes
            .firstWhere((p) => p.id == 'light_aluminum')
            .isLight,
        isTrue,
      );
    });

    test('switchTheme updates both notifiers and creates a light ThemeData', () async {
      SharedPreferences.setMockInitialValues({});
      await AppThemeService.initialize();
      await AppThemeService.switchTheme('light_aluminum');

      expect(AppThemeService.currentThemeId.value, 'light_aluminum');
      expect(AppThemeService.currentPalette.value.id, 'light_aluminum');
      expect(AppThemeService.currentPalette.value.isLight, isTrue);
      expect(
        AppThemeService.createThemeData(AppThemeService.currentPalette.value).brightness,
        Brightness.light,
      );
    });
  });

  group('Phase 8 static tactile gradients', () {
    test('dark mode exposes the hardware surface and metal gradients', () {
      AppThemeService.currentPalette.value =
          AppThemeService.palettes.firstWhere((p) => p.id == 'dizzy_metallic');
      AppThemeService.currentThemeId.value = 'dizzy_metallic';

      expect(DizzyGradients.surface.colors, [DizzyVoid.surface2, DizzyVoid.surface1]);
      expect(DizzyGradients.raised.colors, [DizzyVoid.surface3, DizzyVoid.surface2]);
      expect(DizzyGradients.darkMetal.colors, const [
        Color(0xFF3A3E4A),
        Color(0xFF1C202C),
      ]);
      expect(DizzyGradients.accent.colors, const [
        DizzyGlow.red,
        DizzyGlow.ember,
      ]);
    });

    test('light mode selects anodized silver gradients', () {
      final light = AppThemeService.palettes.firstWhere((p) => p.id == 'light_aluminum');
      AppThemeService.currentPalette.value = light;
      AppThemeService.currentThemeId.value = light.id;

      expect(DizzyGradients.surface.colors, const [
        Color(0xFFFFFFFF),
        Color(0xFFC0C8D4),
      ]);
      expect(DizzyGradients.raised.colors, const [
        Color(0xFFFFFFFF),
        Color(0xFFC0C8D4),
      ]);
      expect(DizzyGradients.silver.colors, const [
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
    test('light mode uses dark drop shadows on aluminum surfaces', () {
      final light = AppThemeService.palettes.firstWhere((p) => p.id == 'light_aluminum');
      AppThemeService.currentPalette.value = light;
      AppThemeService.currentThemeId.value = light.id;

      final shadow = DizzyShadow.card.first;
      expect(shadow.color, const Color(0x331A1D26));
      expect(shadow.offset, const Offset(0, 8));
    });

    test('dark mode keeps a subtle light edge catch', () {
      AppThemeService.currentPalette.value = AppThemeService.palettes.first;
      AppThemeService.currentThemeId.value = AppThemeService.palettes.first.id;

      expect(DizzyShadow.card.last.color, const Color(0x12FFFFFF));
    });
  });
}
