import 'package:flutter/material.dart';

import '../../design/dizzy_tokens.dart';

/// Polish P11 — motion in ONE voice (60fps, no motion sickness).
///
/// Single gate every animation goes through:
/// - OS reduced-motion ON → [Duration.zero] (snap, no animation).
/// - Otherwise → the frozen token duration.
///
/// Pure [resolve] is unit-tested; widgets read the OS flag via
/// [MediaQuery.disableAnimationsOf] and pass it in.
abstract final class MotionGate {
  const MotionGate._();

  /// Token duration, or zero when reduced motion is requested.
  static Duration resolve(Duration token, {required bool reduceMotion}) =>
      reduceMotion ? Duration.zero : token;

  /// Convenience: micro-interaction default (press/hover).
  static Duration micro({required bool reduceMotion}) =>
      resolve(DizzyMotion.fast, reduceMotion: reduceMotion);

  /// Convenience: page-transition default (push).
  static Duration page({required bool reduceMotion}) =>
      resolve(DizzyMotion.slow, reduceMotion: reduceMotion);
}
