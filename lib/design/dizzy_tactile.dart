import 'package:flutter/material.dart';

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

abstract final class DizzyEdge {
  /// Subtle 1px physical light-catch border on raised panels.
  static BorderSide get hairline => BorderSide(
        color: Colors.white.withValues(alpha: 0.12),
        width: 1.0,
      );

  /// Focused / active border.
  static BorderSide get hairlineStrong => BorderSide(
        color: Colors.white.withValues(alpha: 0.22),
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
  /// Floating dock physical drop shadow + subtle top edge catch.
  static List<BoxShadow> get dock => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.65),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.08),
          blurRadius: 0,
          offset: const Offset(0, 1),
        ),
      ];

  /// Media card extruded drop shadow.
  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.55),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.07),
          blurRadius: 0,
          offset: const Offset(0, 1),
        ),
      ];

  /// Center Action FAB glowing tactile shadow.
  static List<BoxShadow> fab(Color glowColor) => [
        BoxShadow(
          color: glowColor.withValues(alpha: 0.45),
          blurRadius: 22,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.60),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];

  /// Inset pressed shadow simulation (zero-cost static list).
  static List<BoxShadow> get pressed => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.50),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
}

abstract final class DizzyGradients {
  /// Classic extruded tactile metal bevel (top lighter, bottom darker).
  static const LinearGradient tactileSurface = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [DizzyVoid.surface3, DizzyVoid.surface1],
  );

  /// Inverted carved-in surface for pressed buttons and text fields.
  static const LinearGradient carvedSurface = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0E1017), Color(0xFF181B26)],
  );

  /// Energetic red gradient for action buttons.
  static const LinearGradient emberButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF2E3D), Color(0xFFB50711)],
  );

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
          Colors.white.withValues(alpha: opacity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.40],
      );
}
