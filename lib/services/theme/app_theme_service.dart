import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/dizzy_tokens.dart';
import '../../design/prism_tokens.dart';

class AppThemePalette {
  final String id;
  final String name;
  final Color primaryColor;
  final Color accentColor;
  final Color scaffoldBackgroundColor;
  final Color cardBackgroundColor;
  final Color appBarBackgroundColor;
  final Color silverAccent;
  final Color amberAccent;

  const AppThemePalette({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.accentColor,
    this.scaffoldBackgroundColor = const Color(0xFF171B26),
    this.cardBackgroundColor = const Color(0xFF1C2130),
    this.appBarBackgroundColor = const Color(0xFF171B26),
    this.silverAccent = const Color(0xFFFFFFFF),
    this.amberAccent = const Color(0xFFF59E0B),
  });

  /// Light clay is the only palette above 50% luminance.
  bool get isLight => scaffoldBackgroundColor.computeLuminance() > 0.5;
}

/// Two themes. Not a theme engine — light clay and dark clay, nothing else.
abstract final class AppThemeService {
  static const _storageKey = 'app_theme_id';

  static const List<AppThemePalette> palettes = [
    AppThemePalette(
      id: 'prism_light',
      name: 'Light Clay',
      primaryColor: Color(0xFFE50914),
      accentColor: Color(0xFFFF4D4D),
      scaffoldBackgroundColor: Color(0xFFE9EDF4),
      cardBackgroundColor: Color(0xFFF4F7FC),
      appBarBackgroundColor: Color(0xFFE9EDF4),
      silverAccent: Color(0xFF000000),
      amberAccent: Color(0xFFF59E0B),
    ),
    AppThemePalette(
      id: 'prism_dark',
      name: 'Dark Clay',
      primaryColor: Color(0xFFE50914),
      accentColor: Color(0xFFFF4D4D),
      scaffoldBackgroundColor: Color(0xFF171B26),
      cardBackgroundColor: Color(0xFF1C2130),
      appBarBackgroundColor: Color(0xFF171B26),
      silverAccent: Color(0xFFFFFFFF),
      amberAccent: Color(0xFFF59E0B),
    ),
  ];

  static final ValueNotifier<String> currentThemeId = ValueNotifier<String>(
    palettes[0].id,
  );

  static final ValueNotifier<AppThemePalette> currentPalette =
      ValueNotifier<AppThemePalette>(palettes[0]);

  static bool _syncingTheme = false;

  static bool _themeWatchersInstalled = false;

  static void ensureThemeWatchers() {
    if (_themeWatchersInstalled) return;
    _themeWatchersInstalled = true;
    currentPalette.addListener(_syncThemeIdFromPalette);
    currentThemeId.addListener(_syncPaletteFromThemeId);
  }

  static void _syncThemeIdFromPalette() {
    if (_syncingTheme) return;
    _syncingTheme = true;
    try {
      final id = currentPalette.value.id;
      if (currentThemeId.value != id) currentThemeId.value = id;
    } finally {
      _syncingTheme = false;
    }
  }

  static void _syncPaletteFromThemeId() {
    if (_syncingTheme) return;
    _syncingTheme = true;
    try {
      final palette = palettes.firstWhere(
        (p) => p.id == currentThemeId.value,
        orElse: () => currentPalette.value,
      );
      if (currentPalette.value.id != palette.id) {
        currentPalette.value = palette;
      }
    } finally {
      _syncingTheme = false;
    }
  }

  static void _applyPalette(AppThemePalette palette) {
    if (currentPalette.value != palette) currentPalette.value = palette;
    if (currentThemeId.value != palette.id) currentThemeId.value = palette.id;
  }

  static Future<void> initialize() async {
    ensureThemeWatchers();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);

    // Only two ids exist now. A saved id from the retired palette set is
    // mapped once by brightness so the app never boots into a dead palette.
    String targetId;
    if (saved == null) {
      targetId = 'prism_light';
    } else if (saved == 'prism_dark') {
      targetId = 'prism_dark';
    } else if (saved == 'prism_light' || _legacyLightIds.contains(saved)) {
      targetId = 'prism_light';
    } else {
      targetId = 'prism_dark';
    }

    final palette = palettes.firstWhere((p) => p.id == targetId);
    _applyPalette(palette);
    if (saved != targetId) {
      await prefs.setString(_storageKey, targetId);
    }
  }

  /// The legacy light palettes, kept only to migrate a saved id once.
  static const Set<String> _legacyLightIds = {
    'light_aluminum',
    'light_silver',
  };

  static Future<void> setPalette(AppThemePalette palette) async {
    _applyPalette(palette);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, palette.id);
  }

  /// Switch by palette id and persist it after the reactive notifiers update.
  static Future<void> switchTheme(String id) async {
    final palette = palettes.firstWhere(
      (p) => p.id == id,
      orElse: () => currentPalette.value,
    );
    await setPalette(palette);
  }

  static Future<void> toggleTheme() {
    return switchTheme(
      currentPalette.value.isLight ? 'prism_dark' : 'prism_light',
    );
  }

  static ThemeData createThemeData(AppThemePalette palette) {
    final isLight = palette.isLight;
    final brightness = isLight ? Brightness.light : Brightness.dark;
    final hairline = isLight
        ? const Color(0xFFB8BEC8)
        : const Color(0x1CE2E8F0);
    final divider = isLight
        ? const Color(0xFFC7CCD4)
        : const Color(0x1AE2E8F0);

    final clay = palette.scaffoldBackgroundColor;
    final raised = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final sunken = isLight ? const Color(0xFFDDE3EC) : PrismDark.sunken;
    // Absolute ink rule: black on light clay, white on dark clay.
    final ink = isLight ? PrismLight.ink : PrismDark.ink;
    final inkSoft = isLight ? PrismLight.inkSoft : PrismDark.inkSoft;
    final onPrimary = palette.primaryColor.computeLuminance() > 0.6
        ? const Color(0xFF15171F)
        : Colors.white;
    final onSecondary = palette.accentColor.computeLuminance() > 0.6
        ? const Color(0xFF15171F)
        : Colors.white;

    // Explicit clay scheme: a seed-derived M3 scheme tints every dialog,
    // menu and sheet pink/red, which reads as off-palette next to the
    // neutral clay surfaces. These values are the palette itself.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.primaryColor,
      onPrimary: onPrimary,
      primaryContainer: isLight
          ? palette.primaryColor.withValues(alpha: 0.14)
          : palette.primaryColor.withValues(alpha: 0.22),
      onPrimaryContainer: ink,
      secondary: palette.accentColor,
      onSecondary: onSecondary,
      secondaryContainer: isLight
          ? palette.accentColor.withValues(alpha: 0.16)
          : palette.accentColor.withValues(alpha: 0.24),
      onSecondaryContainer: ink,
      tertiary: isLight ? PrismAccent.accentTextLight : PrismAccent.accentTextDark,
      onTertiary: Colors.white,
      error: PrismAccent.danger,
      onError: Colors.white,
      errorContainer: PrismAccent.danger.withValues(alpha: 0.18),
      onErrorContainer: ink,
      surface: clay,
      onSurface: ink,
      onSurfaceVariant: inkSoft,
      surfaceContainerLowest: clay,
      surfaceContainerLow: raised,
      surfaceContainer: raised,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: sunken,
      outline: hairline,
      outlineVariant: divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isLight ? Colors.black : Colors.white,
      onInverseSurface: isLight ? Colors.white : Colors.black,
      inversePrimary: isLight ? PrismAccent.accentTextLight : PrismAccent.accentTextDark,
      surfaceTint: Colors.transparent,
    );

    const type = TextTheme(
      displayLarge: TextStyle(
        fontFamily: DizzyType.fontFamily,
        fontSize: DizzyType.display,
        fontWeight: DizzyType.wBold,
        letterSpacing: -0.5,
        height: 1.15,
      ),
      headlineMedium: TextStyle(
        fontFamily: DizzyType.fontFamily,
        fontSize: DizzyType.headline,
        fontWeight: DizzyType.wBold,
        letterSpacing: -0.3,
        height: 1.2,
      ),
      titleLarge: TextStyle(
        fontFamily: DizzyType.fontFamily,
        fontSize: DizzyType.title,
        fontWeight: DizzyType.wSemiBold,
        letterSpacing: -0.1,
        height: 1.25,
      ),
      titleMedium: TextStyle(
        fontFamily: DizzyType.fontFamily,
        fontSize: DizzyType.subtitle,
        fontWeight: DizzyType.wMedium,
        letterSpacing: 0.0,
        height: 1.35,
      ),
      bodyLarge: TextStyle(
        fontFamily: DizzyType.fontFamily,
        fontSize: DizzyType.body,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontFamily: DizzyType.fontFamily,
        fontSize: DizzyType.body,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontFamily: DizzyType.fontFamily,
        fontSize: DizzyType.caption,
        height: 1.45,
      ),
      labelSmall: TextStyle(
        fontFamily: DizzyType.fontFamily,
        fontSize: DizzyType.micro,
        fontWeight: DizzyType.wMedium,
        letterSpacing: 0.4,
      ),
    );

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: clay,
      useMaterial3: true,
      colorScheme: scheme,
      // Global UI font — poora app Poppins pe. Har Text() / AppBar /
      // Button / Dialog automatically isi ko use karta hai jab tak
      // call-site pe explicit fontFamily override na ho.
      fontFamily: DizzyType.fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.appBarBackgroundColor,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: ink),
        titleTextStyle: TextStyle(
          fontFamily: DizzyType.fontFamily,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: raised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: divider, width: 1),
          borderRadius: BorderRadius.circular(PrismRadius.lg),
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1),
      // Component surfaces follow the clay palette instead of M3 defaults,
      // so a dialog/menu/sheet never sits on a foreign (seed-tinted) tone.
      dialogTheme: DialogThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PrismRadius.lg),
        ),
        titleTextStyle: TextStyle(
          fontFamily: DizzyType.fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        contentTextStyle: TextStyle(
          fontFamily: DizzyType.fontFamily,
          fontSize: 14,
          height: 1.5,
          color: inkSoft,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: raised,
        modalBackgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.55),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PrismRadius.xl),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PrismRadius.md),
        ),
        textStyle: TextStyle(
          fontFamily: DizzyType.fontFamily,
          fontSize: 14,
          color: ink,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? Colors.black : raised,
        contentTextStyle: const TextStyle(
          fontFamily: DizzyType.fontFamily,
          fontSize: 13.5,
          color: Colors.white,
        ),
        actionTextColor: isLight ? PrismAccent.accentTextDark : palette.accentColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PrismRadius.md),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isLight ? Colors.black : const Color(0xFF2A3145),
          borderRadius: BorderRadius.circular(PrismRadius.sm),
        ),
        textStyle: const TextStyle(
          fontFamily: DizzyType.fontFamily,
          fontSize: 12,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sunken,
        hintStyle: TextStyle(color: inkSoft, fontSize: 14),
        labelStyle: TextStyle(color: inkSoft, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PrismSpace.md,
          vertical: PrismSpace.sm + 2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PrismRadius.md),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PrismRadius.md),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PrismRadius.md),
          borderSide: BorderSide(color: palette.primaryColor, width: 1.6),
        ),
      ),
      iconTheme: IconThemeData(color: inkSoft),
      listTileTheme: ListTileThemeData(
        iconColor: inkSoft,
        textColor: ink,
        titleTextStyle: TextStyle(
          fontFamily: DizzyType.fontFamily,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: DizzyType.fontFamily,
          fontSize: 12.5,
          color: inkSoft,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.primaryColor,
        selectionColor: palette.primaryColor.withValues(alpha: 0.28),
        selectionHandleColor: palette.primaryColor,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primaryColor,
        linearTrackColor: sunken,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          inkSoft.withValues(alpha: 0.45),
        ),
        radius: const Radius.circular(PrismRadius.pill),
        thickness: const WidgetStatePropertyAll(5),
      ),
      // Frozen type scale (Polish P1) — har screen yahi sizes use kare.
      // Sab styles Poppins pe lock: display/headline tight tracking (premium
      // feel), body comfortable line-height (Easy English readability).
      // Colors are applied explicitly so every unstyled Text inherits the
      // black-on-light / white-on-dark rule.
      textTheme: type.apply(bodyColor: ink, displayColor: ink),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
