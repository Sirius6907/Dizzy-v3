/// Polish P12 — accessibility rails in ONE place.
///
/// Done rule: 200% font pe koi toot-foot nahi.
/// Layouts must survive up to [kMaxTextScale]; beyond that the app root
/// clamps (safety rail, not a restriction — TalkBack/focus order
/// unaffected).
abstract final class DizzyA11y {
  const DizzyA11y._();

  /// Max text scale the layouts guarantee (200%).
  static const double kMaxTextScale = 2.0;

  /// Min touch target (Material guideline, dp).
  static const double kMinTouchTarget = 48.0;

  /// Clamp a text scale factor into the guaranteed range.
  static double clampScale(double scale) =>
      scale.clamp(1.0, kMaxTextScale).toDouble();

  /// True when a control's hit box meets the 48dp guideline.
  static bool meetsTouchTarget(double width, double height) =>
      width >= kMinTouchTarget && height >= kMinTouchTarget;
}
