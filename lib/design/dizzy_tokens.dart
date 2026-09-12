import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dizzy design tokens — SINGLE SOURCE OF TRUTH (Polish P1 freeze).
//
// Rule: koi naya hard-coded color / font-size / spacing / radius / duration
// add mat karo — yahi se lo. Ye values theme-agnostic dark baseline hain;
// brand-tinted colors (primary/accent) hamesha AppThemeService.currentPalette
// se aate hain, yahan se nahi.
// ─────────────────────────────────────────────────────────────────────────────

/// Spacing scale (4-pt grid).
abstract final class DizzySpace {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

/// Corner radii.
abstract final class DizzyRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double pill = 999.0;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
}

/// Type scale (sizes only — color/weight call-site pe).
abstract final class DizzyType {
  static const double display = 32.0;
  static const double headline = 24.0;
  static const double title = 20.0;
  static const double subtitle = 16.0;
  static const double body = 14.0;
  static const double caption = 12.0;
  static const double captionSm = 10.5;
  static const double micro = 10.0;

  static const FontWeight wRegular = FontWeight.w400;
  static const FontWeight wMedium = FontWeight.w500;
  static const FontWeight wSemiBold = FontWeight.w600;
  static const FontWeight wBold = FontWeight.w700;
}

/// Motion system — durations + curves. Sab animation yahi se.
abstract final class DizzyMotion {
  static const Duration instant = Duration(milliseconds: 150);
  static const Duration fast = Duration(milliseconds: 250);
  static const Duration standard = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 600);
  static const Duration hero = Duration(milliseconds: 700);

  /// Player controls auto-hide delay (P4 unify — sab player isi ko use kare).
  static const Duration controlsAutoHide = Duration(seconds: 4);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve snappy = Curves.fastOutSlowIn;
}

/// Semantic dark-baseline colors. Brand color KABHI yahan hard-code mat karo.
abstract final class DizzyColors {
  static const bg = Color(0xFF0B0D12);
  static const surface = Color(0xFF15171F);
  static const accent = Color(0xFFE50914);
  static const accentDim = Color(0xFF9A0710);
  static const gold = Color(0xFFFFC107);

  /// Fallback avatar gradients (deterministic pick by name hash).
  static const avatarPairs = [
    [Color(0xFF3A1C71), Color(0xFFD76D77)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFF1F4037), Color(0xFF99F2C8)],
    [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
    [Color(0xFF614385), Color(0xFF516395)],
    [Color(0xFF232526), Color(0xFF6E6E6E)],
  ];

  /// Cinematic scrim tint used over backdrops (details hero, player).
  static const scrim = Color(0xFF1A1D26);
}

/// Responsive breakpoints (hero heights, desktop layouts).
abstract final class DizzyBreakpoints {
  static const double mobile = 600.0;
  static const double tablet = 1100.0;
}
