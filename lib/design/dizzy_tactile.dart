import 'package:flutter/material.dart';

import '../../services/theme/app_theme_service.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Dizzy Tactile Neo-Skeuomorphic & Vibrant OLED Tokens
///
/// Pure-math physical depth: LinearGradients + Bevel Highlights + Static BoxShadows.
/// ZERO runtime GPU shader overhead, zero BackdropFilter, rock-solid 60-120 FPS.
/// ─────────────────────────────────────────────────────────────────────────────

abstract final class DizzyVoid {
  /// True OLED pitch black — screen pixels turn physically OFF. Saves ~18% battery.
  static const Color obsidian = Color(0xFF000000);

  /// Deep void scaffold background (replaces washed out dark grays).
  static const Color voidA = Color(0xFF05060A);

  /// Secondary void for section backdrops and card containers.
  static const Color voidB = Color(0xFF0C0E15);

  /// Surface tier 1: Base surface bottom falloff.
  static const Color surface1 = Color(0xFF14161E);

  /// Surface tier 2: Base surface top light catch.
  static const Color surface2 = Color(0xFF1C202C);

  /// Surface tier 3: Raised tactile elements, dock, floating FABs.
  static const Color surface3 = Color(0xFF242834);

  /// High-contrast bone typography token — razor-sharp readability without eye fatigue.
  static const Color bone = Color(0xFFF5F7FF);

  /// Subtitle / metadata ash token (always >= 4.5:1 contrast against void).
  static const Color ash = Color(0xFF9AA0B4);
}

bool _isLightTheme() {
  final id = AppThemeService.currentThemeId.value;
  final palette = AppThemeService.palettes.firstWhere(
    (candidate) => candidate.id == id,
    orElse: () => AppThemeService.currentPalette.value,
  );
  return palette.isLight;
}

abstract final class DizzyEdge {
  /// Subtle 1px physical light-catch border on raised panels.
  static BorderSide get hairline => BorderSide(
        color: _isLightTheme() ? const Color(0xFFB8BEC8) : const Color(0x1FE2E8F0),
        width: 1.0,
      );

  /// Focused / active border.
  static BorderSide get hairlineStrong => BorderSide(
        color: _isLightTheme() ? const Color(0xFF8A93A3) : const Color(0x38E2E8F0),
        width: 1.2,
      );

  /// Laser-cut neon border for active states, speaking indicators, and badges.
  static BorderSide neon(Color color, {double width = 1.2}) => BorderSide(
        color: color.withValues(alpha: 0.65),
        width: width,
      );
}

abstract final class DizzyGlow {
  /// Primary action, playback, and live streaming indicator.
  static const Color red = Color(0xFFE50914);

  /// Hot ember for active records, live rooms, urgent highlights.
  static const Color ember = Color(0xFFFF3D2E);

  /// Volt green for working scrapers, online friends, speaking presence rings.
  static const Color volt = Color(0xFF00E676);

  /// Cyber cyan for in-app DMs, active sync status, and media card links.
  static const Color beam = Color(0xFF00C2FF);

  /// Solar gold for binge streaks, anime ratings, and VIP status.
  static const Color gold = Color(0xFFFFC107);

  /// Violet for Manga, Anime, and creative hubs.
  static const Color violet = Color(0xFF8B5CF6);
}

abstract final class DizzyShadow {
  static const List<BoxShadow> _darkDock = [
    BoxShadow(
      color: Color(0xA6000000),
      blurRadius: 28,
      offset: Offset(0, 14),
    ),
    BoxShadow(
      color: Color(0x14FFFFFF),
      blurRadius: 0,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> _lightDock = [
    BoxShadow(
      color: Color(0x331A1D26),
      blurRadius: 28,
      offset: Offset(0, 14),
    ),
    BoxShadow(
      color: Color(0x1A1A1D26),
      blurRadius: 0,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> _darkCard = [
    BoxShadow(
      color: Color(0x8C000000),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x12FFFFFF),
      blurRadius: 0,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> _lightCard = [
    BoxShadow(
      color: Color(0x331A1D26),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x141A1D26),
      blurRadius: 0,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> _darkPressed = [
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> _lightPressed = [
    BoxShadow(
      color: Color(0x241A1D26),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Floating dock physical drop shadow + subtle top edge catch.
  static List<BoxShadow> get dock => _isLightTheme() ? _lightDock : _darkDock;

  /// Media card extruded drop shadow.
  static List<BoxShadow> get card => _isLightTheme() ? _lightCard : _darkCard;

  /// Center Action FAB glowing tactile shadow.
  static List<BoxShadow> fab(Color glowColor) => [
        BoxShadow(
          color: glowColor.withValues(alpha: 0.45),
          blurRadius: 22,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: _isLightTheme() ? const Color(0x331A1D26) : const Color(0x99000000),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];

  /// Inset pressed shadow simulation (zero-cost static list).
  static List<BoxShadow> get pressed =>
      _isLightTheme() ? _lightPressed : _darkPressed;
}

abstract final class DizzyGradients {
  static const LinearGradient _darkSurface = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [DizzyVoid.surface2, DizzyVoid.surface1],
  );

  static const LinearGradient _lightSurface = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFC0C8D4)],
  );

  static const LinearGradient _darkRaised = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [DizzyVoid.surface3, DizzyVoid.surface2],
  );

  static const LinearGradient _lightRaised = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFC0C8D4)],
  );

  /// Brushed aluminum silver for light anodized-metal surfaces.
  static const LinearGradient silver = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFC0C8D4)],
  );

  /// Gunmetal metallic gradient for dark hardware panels.
  static const LinearGradient darkMetal = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3A3E4A), Color(0xFF1C202C)],
  );

  /// Ember red primary-action gradient.
  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [DizzyGlow.red, DizzyGlow.ember],
  );

  static const LinearGradient _darkPressed = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0E1017), Color(0xFF181B26)],
  );

  static const LinearGradient _lightPressed = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFC0C8D4), Color(0xFFFFFFFF)],
  );

  /// Card-body gradient; automatically selects dark metal or light aluminum.
  static LinearGradient get surface => _isLightTheme() ? _lightSurface : _darkSurface;

  /// Floating control gradient; automatically selects the active theme tier.
  static LinearGradient get raised => _isLightTheme() ? _lightRaised : _darkRaised;

  /// Inverted tactile gradient for depressed button states.
  static LinearGradient get pressed =>
      _isLightTheme() ? _lightPressed : _darkPressed;

  /// Classic extruded tactile metal bevel (backward-compatible alias).
  static LinearGradient get tactileSurface => surface;

  /// Inverted carved-in surface for pressed buttons and text fields.
  static LinearGradient get carvedSurface => pressed;

  /// Energetic red gradient for action buttons (backward-compatible alias).
  static LinearGradient get emberButton => accent;

  /// Cyber cyan gradient for active sync elements and chat.
  static const LinearGradient beamButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF26D0FF), Color(0xFF007CA3)],
  );

  /// Top-edge inner highlight simulation without shaders.
  static LinearGradient topInnerGlow([double opacity = 0.12]) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          (_isLightTheme() ? const Color(0xFF1A1D26) : Colors.white)
              .withValues(alpha: opacity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.40],
      );
}
