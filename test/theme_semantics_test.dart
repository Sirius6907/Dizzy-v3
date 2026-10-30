import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';

void main() {
  AppThemePalette byId(String id) =>
      AppThemeService.palettes.firstWhere((p) => p.id == id);

  group('Prism clay theme surface contract', () {
    for (final id in ['prism_light', 'prism_dark']) {
      test('$id paints every Material surface from clay tokens', () {
        final palette = byId(id);
        final theme = AppThemeService.createThemeData(palette);
        final ink = palette.isLight ? PrismLight.ink : PrismDark.ink;

        expect(theme.brightness, palette.isLight
            ? Brightness.light
            : Brightness.dark);
        expect(theme.scaffoldBackgroundColor, palette.scaffoldBackgroundColor);
        expect(theme.colorScheme.surface, palette.scaffoldBackgroundColor);
        expect(theme.colorScheme.onSurface, ink);
        expect(theme.colorScheme.surfaceTint, Colors.transparent);
        expect(theme.colorScheme.primary, palette.primaryColor);
      });

      test('$id dialogs, sheets and menus reuse one raised clay tone', () {
        final theme = AppThemeService.createThemeData(byId(id));
        final raised = theme.dialogTheme.backgroundColor;
        expect(raised, isNotNull);
        expect(theme.bottomSheetTheme.modalBackgroundColor, raised);
        expect(theme.popupMenuTheme.color, raised);
        expect(
          theme.dialogTheme.surfaceTintColor,
          Colors.transparent,
          reason: 'M3 elevation tint would recolour the clay surface',
        );
      });

      test('$id dividers and outlines come from the palette, not the seed', () {
        final theme = AppThemeService.createThemeData(byId(id));
        expect(theme.dividerTheme.color, theme.colorScheme.outlineVariant);
        expect(theme.colorScheme.outline, isNot(theme.colorScheme.primary));
      });
    }

    test('light ink stays readable on light clay', () {
      final a = PrismLight.ink.computeLuminance() + 0.05;
      final b = PrismLight.bg.computeLuminance() + 0.05;
      final ratio = a > b ? a / b : b / a;
      expect(ratio, greaterThan(7.0));
    });
  });
}
