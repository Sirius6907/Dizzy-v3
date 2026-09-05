import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  ];

  static final ValueNotifier<AppThemePalette> currentPalette =
      ValueNotifier<AppThemePalette>(palettes[0]);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_storageKey);
    if (id != null && id != 'amethyst') {
      final found = palettes.firstWhere(
        (p) => p.id == id,
        orElse: () => palettes[0],
      );
      currentPalette.value = found;
    } else {
      currentPalette.value = palettes[0];
      if (id == 'amethyst') {
        await prefs.setString(_storageKey, palettes[0].id);
      }
    }
  }

  static Future<void> setPalette(AppThemePalette palette) async {
    currentPalette.value = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, palette.id);
  }

  static ThemeData createThemeData(AppThemePalette palette) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: palette.scaffoldBackgroundColor,
      useMaterial3: true,
      colorSchemeSeed: palette.primaryColor,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: palette.cardBackgroundColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: palette.isMetallic
                ? const Color(0x1CE2E8F0)
                : const Color(0x14FFFFFF),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.isMetallic
            ? const Color(0x1AE2E8F0)
            : const Color(0x12FFFFFF),
        thickness: 1,
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
