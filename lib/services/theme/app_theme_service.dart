import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/dizzy_tokens.dart';

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
  final bool isMetallic;

  const AppThemePalette({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.accentColor,
    this.scaffoldBackgroundColor = const Color(0xFF090A0D),
    this.cardBackgroundColor = const Color(0xFF13151B),
    this.appBarBackgroundColor = const Color(0xFF0D0E13),
    this.silverAccent = const Color(0xFFE2E8F0),
    this.amberAccent = const Color(0xFFF59E0B),
    this.isMetallic = false,
  });

  /// Metallic silver-to-amber gradient matching the Dizzy 3D logo
  LinearGradient get metallicGradient => LinearGradient(
        colors: [silverAccent, primaryColor, amberAccent],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Polished liquid silver shine gradient
  LinearGradient get silverShineGradient => const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0), Color(0xFF94A3B8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Warm golden amber glow gradient
  LinearGradient get amberGlowGradient => const LinearGradient(
        colors: [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFD97706)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Whether this palette is intended for a light anodized-metal surface.
  bool get isLight => scaffoldBackgroundColor.computeLuminance() > 0.5;
}

abstract final class AppThemeService {
  static const _storageKey = 'app_theme_id';

  static const List<AppThemePalette> palettes = [
    AppThemePalette(
      id: 'dizzy_metallic',
      name: 'Dizzy Signature (Silver & Amber)',
      primaryColor: Color(0xFFF59E0B), // Warm Golden Amber Rim Glow
      accentColor: Color(0xFFCBD5E1), // Liquid Silver Chrome
      scaffoldBackgroundColor: Color(0xFF090A0D), // Deep Obsidian Gunmetal
      cardBackgroundColor: Color(0xFF13151B), // Brushed Dark Titanium
      appBarBackgroundColor: Color(0xFF0D0E13), // Obsidian Steel
      silverAccent: Color(0xFFE2E8F0),
      amberAccent: Color(0xFFF59E0B),
      isMetallic: true,
    ),
    AppThemePalette(
      id: 'silver_chrome',
      name: 'Platinum Silver Chrome',
      primaryColor: Color(0xFFE2E8F0), // Liquid Platinum Silver
      accentColor: Color(0xFF94A3B8), // Polished Slate Chrome
      scaffoldBackgroundColor: Color(0xFF0A0B0E),
      cardBackgroundColor: Color(0xFF14161C),
      appBarBackgroundColor: Color(0xFF0F1015),
      silverAccent: Color(0xFFFFFFFF),
      amberAccent: Color(0xFFF59E0B),
      isMetallic: true,
    ),
    AppThemePalette(
      id: 'golden_amber',
      name: 'Royal Golden Amber',
      primaryColor: Color(0xFFD97706), // Rich Amber Gold
      accentColor: Color(0xFFFDE68A), // Champagne Gold
      scaffoldBackgroundColor: Color(0xFF0C0A06),
      cardBackgroundColor: Color(0xFF18150E),
      appBarBackgroundColor: Color(0xFF120F08),
      silverAccent: Color(0xFFE2E8F0),
      amberAccent: Color(0xFFFBBF24),
      isMetallic: true,
    ),
    AppThemePalette(
      id: 'amethyst',
      name: 'Amethyst Violet',
      primaryColor: Color(0xFF7C5CFF),
      accentColor: Color(0xFF00E5FF),
      scaffoldBackgroundColor: Color(0xFF090A0D),
      cardBackgroundColor: Color(0xFF13151B),
      appBarBackgroundColor: Color(0xFF0D0E13),
    ),
    AppThemePalette(
      id: 'cyberpunk',
      name: 'Cyberpunk Neon',
      primaryColor: Color(0xFFFF2A85),
      accentColor: Color(0xFF00F0FF),
      scaffoldBackgroundColor: Color(0xFF0C0812),
      cardBackgroundColor: Color(0xFF160E1E),
      appBarBackgroundColor: Color(0xFF100A17),
    ),
    AppThemePalette(
      id: 'emerald',
      name: 'Emerald Aurora',
      primaryColor: Color(0xFF10B981),
      accentColor: Color(0xFF34D399),
      scaffoldBackgroundColor: Color(0xFF060F0B),
      cardBackgroundColor: Color(0xFF0E1A14),
      appBarBackgroundColor: Color(0xFF09140F),
    ),
    AppThemePalette(
      id: 'sunset',
      name: 'Sunset Crimson',
      primaryColor: Color(0xFFFF3366),
      accentColor: Color(0xFFFF9900),
      scaffoldBackgroundColor: Color(0xFF0F080B),
      cardBackgroundColor: Color(0xFF1A0E13),
      appBarBackgroundColor: Color(0xFF130A0E),
    ),
    AppThemePalette(
      id: 'sapphire',
      name: 'Midnight Sapphire',
      primaryColor: Color(0xFF3B82F6),
      accentColor: Color(0xFF60A5FA),
      scaffoldBackgroundColor: Color(0xFF060B14),
      cardBackgroundColor: Color(0xFF0E1726),
      appBarBackgroundColor: Color(0xFF09101C),
    ),
    AppThemePalette(
      id: 'vampire',
      name: 'Vampire Red',
      primaryColor: Color(0xFFE50914),
      accentColor: Color(0xFFFF4D4D),
      scaffoldBackgroundColor: Color(0xFF0E0607),
      cardBackgroundColor: Color(0xFF1A0C0E),
      appBarBackgroundColor: Color(0xFF14080A),
    ),
    AppThemePalette(
      id: 'barbie',
      name: 'Pink Barbie',
      primaryColor: Color(0xFFFF1493),
      accentColor: Color(0xFFFF80BF),
      scaffoldBackgroundColor: Color(0xFF14050E),
      cardBackgroundColor: Color(0xFF220A18),
      appBarBackgroundColor: Color(0xFF1A0713),
    ),
    AppThemePalette(
      id: 'light_aluminum',
      name: 'Light Anodized Aluminum',
      primaryColor: Color(0xFFB0B8C8),
      accentColor: Color(0xFFE50914),
      scaffoldBackgroundColor: Color(0xFFE8EAED),
      cardBackgroundColor: Color(0xFFFFFFFF),
      appBarBackgroundColor: Color(0xFFD8DADF),
      silverAccent: Color(0xFF1A1D26),
      amberAccent: Color(0xFFFFC107),
      isMetallic: true,
    ),
    AppThemePalette(
      id: 'light_silver',
      name: 'Light Polished Silver',
      primaryColor: Color(0xFF8A93A3),
      accentColor: Color(0xFFE50914),
      scaffoldBackgroundColor: Color(0xFFF5F5F7),
      cardBackgroundColor: Color(0xFFFFFFFF),
      appBarBackgroundColor: Color(0xFFE0E2E6),
      silverAccent: Color(0xFF0A0C10),
      amberAccent: Color(0xFFFFC107),
      isMetallic: true,
    ),
  ];

  static final ValueNotifier<String> currentThemeId =
      ValueNotifier<String>(palettes[0].id);

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
    final id = prefs.getString(_storageKey);
    final palette = id == null
        ? palettes[0]
        : palettes.firstWhere(
            (p) => p.id == id,
            orElse: () => palettes[0],
          );
    _applyPalette(palette);
    if (id == 'amethyst' ||
        (id != null && !palettes.any((p) => p.id == id))) {
      await prefs.setString(_storageKey, palette.id);
    }
  }

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

  /// Toggle between the default obsidian palette and light aluminum.
  static Future<void> toggleTheme() {
    return switchTheme(
      currentPalette.value.isLight ? palettes[0].id : 'light_aluminum',
    );
  }

  static ThemeData createThemeData(AppThemePalette palette) {
    final brightness = palette.isLight ? Brightness.light : Brightness.dark;
    final hairline = palette.isLight
        ? const Color(0xFFB8BEC8)
        : const Color(0x1CE2E8F0);
    final divider = palette.isLight
        ? const Color(0xFFC7CCD4)
        : const Color(0x1AE2E8F0);

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: palette.scaffoldBackgroundColor,
      useMaterial3: true,
      colorSchemeSeed: palette.primaryColor,
      // Global UI font — poora app Poppins pe. Har Text() / AppBar /
      // Button / Dialog automatically isi ko use karta hai jab tak
      // call-site pe explicit fontFamily override na ho.
      fontFamily: DizzyType.fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.appBarBackgroundColor,
        foregroundColor: palette.isLight
            ? palette.silverAccent
            : palette.silverAccent,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: palette.cardBackgroundColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: palette.isMetallic ? hairline : divider,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
      ),
      // Frozen type scale (Polish P1) — har screen yahi sizes use kare.
      // Sab styles Poppins pe lock: display/headline tight tracking (premium
      // feel), body comfortable line-height (Easy English readability).
      textTheme: const TextTheme(
        displayLarge: TextStyle(
            fontFamily: DizzyType.fontFamily,
            fontSize: DizzyType.display,
            fontWeight: DizzyType.wBold,
            letterSpacing: -0.5,
            height: 1.15),
        headlineMedium: TextStyle(
            fontFamily: DizzyType.fontFamily,
            fontSize: DizzyType.headline,
            fontWeight: DizzyType.wBold,
            letterSpacing: -0.3,
            height: 1.2),
        titleLarge: TextStyle(
            fontFamily: DizzyType.fontFamily,
            fontSize: DizzyType.title,
            fontWeight: DizzyType.wSemiBold,
            letterSpacing: -0.1,
            height: 1.25),
        titleMedium: TextStyle(
            fontFamily: DizzyType.fontFamily,
            fontSize: DizzyType.subtitle,
            fontWeight: DizzyType.wMedium,
            letterSpacing: 0.0,
            height: 1.35),
        bodyLarge: TextStyle(
            fontFamily: DizzyType.fontFamily,
            fontSize: DizzyType.body,
            height: 1.5),
        bodyMedium: TextStyle(
            fontFamily: DizzyType.fontFamily,
            fontSize: DizzyType.body,
            height: 1.5),
        bodySmall: TextStyle(
            fontFamily: DizzyType.fontFamily,
            fontSize: DizzyType.caption,
            height: 1.45),
        labelSmall: TextStyle(
            fontFamily: DizzyType.fontFamily,
            fontSize: DizzyType.micro,
            fontWeight: DizzyType.wMedium,
            letterSpacing: 0.4),
      ),
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
