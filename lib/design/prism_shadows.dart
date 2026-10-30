import 'package:flutter/material.dart';

import 'prism_tokens.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Prism elevation ladder (SPEC §2) — one light source: top-left, never flip.
///
/// resting / raised / floating / pressed(inset-illusion) / soft.
/// Every raised surface = THREE parts: light shadow (top-left) + dark shadow
/// (bottom-right) + 1px inner top highlight ([topHighlight]).
/// Zero shaders, zero BackdropFilter — 60-120 FPS safe.
/// ─────────────────────────────────────────────────────────────────────────────
abstract final class PrismShadows {
  /// Resting elevation: -6/-6/14 light + 6/6/14 dark.
  static List<BoxShadow> resting({required bool isLight, double scale = 1.0}) {
    final light = isLight ? PrismLight.neuLight : PrismDark.neuLight;
    final dark = isLight ? PrismLight.neuDark : PrismDark.neuDark;
    return [
      BoxShadow(
        color: light,
        blurRadius: 14 * scale,
        offset: Offset(-6 * scale, -6 * scale),
      ),
      BoxShadow(
        color: dark,
        blurRadius: 14 * scale,
        offset: Offset(6 * scale, 6 * scale),
      ),
    ];
  }

  /// Raised elevation: -10/-10/22 + 10/10/22. Default card depth.
  static List<BoxShadow> raised({required bool isLight, double scale = 1.0}) {
    final light = isLight ? PrismLight.neuLight : PrismDark.neuLight;
    final dark = isLight ? PrismLight.neuDark : PrismDark.neuDark;
    return [
      BoxShadow(
        color: light,
        blurRadius: 22 * scale,
        offset: Offset(-10 * scale, -10 * scale),
      ),
      BoxShadow(
        color: dark,
        blurRadius: 22 * scale,
        offset: Offset(10 * scale, 10 * scale),
      ),
    ];
  }

  /// Floating elevation (dock, dialogs, sheets): raised + accent halo.
  static List<BoxShadow> floating({
    required bool isLight,
    double scale = 1.0,
    Color? halo,
  }) {
    return [
      ...raised(isLight: isLight, scale: scale * 1.15),
      if (halo != null)
        BoxShadow(
          color: halo.withValues(alpha: 0.22),
          blurRadius: 26 * scale,
          offset: Offset(0, 12 * scale),
        ),
    ];
  }

  /// Pressed (inset illusion): tighter reversed pair + gradient flip
  /// (see [pressedGradient]). Reads carved-in.
  static List<BoxShadow> pressed({required bool isLight, double scale = 1.0}) {
    final light = isLight ? PrismLight.neuLight : PrismDark.neuLight;
    final dark = isLight ? PrismLight.neuDark : PrismDark.neuDark;
    return [
      BoxShadow(
        color: dark,
        blurRadius: 12 * scale,
        spreadRadius: 2 * scale,
        offset: Offset(3 * scale, 3 * scale),
      ),
      BoxShadow(
        color: light,
        blurRadius: 12 * scale,
        offset: Offset(-3 * scale, -3 * scale),
      ),
    ];
  }

  /// Soft elevation for tiny elements (chips at rest, dots).
  static List<BoxShadow> soft({required bool isLight, double scale = 1.0}) {
    final light = isLight ? PrismLight.neuLight : PrismDark.neuLight;
    final dark = isLight ? PrismLight.neuDark : PrismDark.neuDark;
    return [
      BoxShadow(
        color: light,
        blurRadius: 6 * scale,
        offset: Offset(-2 * scale, -2 * scale),
      ),
      BoxShadow(
        color: dark,
        blurRadius: 6 * scale,
        offset: Offset(2 * scale, 2 * scale),
      ),
    ];
  }

  /// 1px inner top highlight — the third shadow part (SPEC §1.1).
  /// Lay over the surface via [PrismCard]'s highlight overlay.
  static LinearGradient topHighlight(bool isLight) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.center,
    colors: [
      (isLight ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF)).withValues(
        alpha: isLight ? 0.9 : 0.07,
      ),
      Colors.transparent,
    ],
    stops: const [0.0, 0.12],
  );

  /// Clay surface gradient (subtle top-catch → base).
  static LinearGradient surfaceGradient(bool isLight) {
    final top = isLight ? PrismLight.raisedTop : PrismDark.raisedTop;
    final bottom = isLight ? PrismLight.raisedBottom : PrismDark.raisedBottom;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [top, bottom],
    );
  }

  /// Inverted gradient for pressed surfaces.
  static LinearGradient pressedGradient(bool isLight) {
    final top = isLight ? PrismLight.raisedTop : PrismDark.raisedTop;
    final bottom = isLight ? PrismLight.raisedBottom : PrismDark.raisedBottom;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [bottom, top],
    );
  }
}

/// Poster frame shadows: clay raised + optional accent hover glow.
abstract final class PrismFrame {
  static List<BoxShadow> poster({
    required bool isLight,
    double scale = 1.0,
    bool hovered = false,
    Color? glow,
  }) {
    return [
      ...(hovered
          ? PrismShadows.raised(isLight: isLight, scale: scale)
          : PrismShadows.resting(isLight: isLight, scale: scale)),
      if (hovered && glow != null)
        BoxShadow(
          color: glow.withValues(alpha: 0.35),
          blurRadius: 30,
          spreadRadius: 1,
          offset: const Offset(0, 8),
        ),
    ];
  }
}
