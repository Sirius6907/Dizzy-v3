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
  /// One light source (top-left), three layers: a crisp rim highlight, a
  /// wide ambient shadow, and a short contact shadow. The old pair of
  /// heavy ±10/22 shadows read as a blue smudge at both corners instead of
  /// a raised object, because the plateau between them was flat.
  static List<BoxShadow> _depth(bool isLight, double scale) {
    final rim = isLight ? const Color(0xFFFFFFFF) : const Color(0x14FFFFFF);
    final ambient = isLight ? const Color(0x1FA0AEC2) : const Color(0x59000000);
    final contact = isLight ? const Color(0x338C99AA) : const Color(0x99000000);
    return [
      BoxShadow(
        color: rim,
        blurRadius: 5 * scale,
        offset: Offset(-2 * scale, -2 * scale),
      ),
      BoxShadow(
        color: ambient,
        blurRadius: 30 * scale,
        spreadRadius: -4 * scale,
        offset: Offset(0, 12 * scale),
      ),
      BoxShadow(
        color: contact,
        blurRadius: 9 * scale,
        offset: Offset(0, 4 * scale),
      ),
    ];
  }

  /// Resting elevation: the same light model, shallower.
  static List<BoxShadow> resting({required bool isLight, double scale = 1.0}) =>
      _depth(isLight, scale * 0.7);

  /// Raised elevation: default card depth.
  static List<BoxShadow> raised({required bool isLight, double scale = 1.0}) =>
      _depth(isLight, scale);

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

  /// Pressed (inset illusion): contact shadow inside the top-left edge and
  /// a rim below the bottom-right edge, plus the gradient flip.
  static List<BoxShadow> pressed({required bool isLight, double scale = 1.0}) {
    final rim = isLight ? const Color(0xE6FFFFFF) : const Color(0x14FFFFFF);
    final inset = isLight ? const Color(0x2E8C99AA) : const Color(0x99000000);
    return [
      BoxShadow(
        color: inset,
        blurRadius: 7 * scale,
        offset: Offset(2 * scale, 2 * scale),
      ),
      BoxShadow(
        color: rim,
        blurRadius: 6 * scale,
        offset: Offset(-2 * scale, -2 * scale),
      ),
    ];
  }

  /// Soft elevation for tiny elements (chips at rest, dots).
  static List<BoxShadow> soft({required bool isLight, double scale = 1.0}) {
    final rim = isLight ? const Color(0xE6FFFFFF) : const Color(0x0FFFFFFF);
    final contact = isLight ? const Color(0x1F8C99AA) : const Color(0x59000000);
    return [
      BoxShadow(
        color: rim,
        blurRadius: 3 * scale,
        offset: Offset(-1 * scale, -1 * scale),
      ),
      BoxShadow(
        color: contact,
        blurRadius: 6 * scale,
        offset: Offset(0, 2 * scale),
      ),
    ];
  }

  /// Hairline top catch — the third shadow part (SPEC §1.1).
  /// Kept to ~2% of the height: a taller band reads as a grey seam on
  /// light clay cards.
  static LinearGradient topHighlight(bool isLight) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.center,
    colors: [
      Colors.white.withValues(alpha: isLight ? 0.35 : 0.05),
      Colors.transparent,
    ],
    stops: const [0.0, 0.02],
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
