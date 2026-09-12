import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/dizzy_tokens.dart';

/// Polish P13 — 10-foot (TV + desktop) rules in ONE place.
///
/// Done rule: Firestick remote se poora app chal jaye.
/// DPAD center/Enter activates, arrows move focus (Flutter traversal),
/// content stays inside overscan-safe margins.
abstract final class TvGate {
  const TvGate._();

  /// Overscan-safe margin — content never hides behind TV edges.
  static const EdgeInsets kOverscan =
      EdgeInsets.all(DizzySpace.lg);

  /// Keys that mean "press the focused thing" on remotes + keyboards.
  static bool isSelectKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.gameButtonA;

  /// DPAD/keyboard arrows (move focus or turn carousel pages).
  static bool isArrowKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown;

  /// Visible focus ring for custom controls (10-foot must SEE focus).
  static BoxDecoration focusRing({required bool focused}) =>
      BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: focused
              ? Colors.white
              : Colors.white.withValues(alpha: 0.2),
          width: focused ? 2.5 : 1.5,
        ),
      );
}
