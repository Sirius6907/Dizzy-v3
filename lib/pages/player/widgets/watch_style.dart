import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';

/// Watch palette + spacing (moved from watch_screen.dart P5 — single source).
abstract final class WatchColors {
  static const bg = DizzyColors.bg;
  static const surface = DizzyVoid.surface1;
  static const surfaceLight = DizzyColors.scrim;
  static const accent = Color(0xFF7C5CFF);
  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFFAAAAAF);
  static const textTertiary = Color(0xFF66666B);
  static const gold = DizzyGlow.gold;
}

abstract final class WatchSpace {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
}

