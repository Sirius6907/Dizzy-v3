import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Prism v2 design tokens — LOCKED (proto SPEC §2, do not redesign).
///
/// Light is DEFAULT. Dark is equally crafted, not inverted.
/// Same 4pt grid, radii, Poppins scale as the running app.
/// ─────────────────────────────────────────────────────────────────────────────

/// Spacing scale (4-pt grid, SPEC §2).
abstract final class PrismSpace {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 28.0;
  static const double xxxl = 32.0;
  static const double huge = 40.0;
  static const double giant = 48.0;
  static const double mega = 64.0;
}

/// Corner radii (SPEC §2).
abstract final class PrismRadius {
  static const double sm = 10.0;
  static const double md = 14.0;
  static const double lg = 22.0;
  static const double xl = 28.0;
  static const double pill = 999.0;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

/// Type scale — Poppins, headings tracking -0.02em, hero numerals -0.04em.
abstract final class PrismType {
  static const String fontFamily = 'Poppins';

  static const double display = 32.0;
  static const double headline = 24.0;
  static const double title = 20.0;
  static const double section = 18.0;
  static const double subtitle = 16.0;
  static const double cardTitle = 15.0;
  static const double body = 14.0;
  static const double caption = 12.0;
  static const double micro = 11.0;

  static const FontWeight wRegular = FontWeight.w400;
  static const FontWeight wMedium = FontWeight.w500;
  static const FontWeight wSemiBold = FontWeight.w600;
  static const FontWeight wBold = FontWeight.w700;
}

/// Motion budget (SPEC §1.7): 150 / 250 / 350ms, ease-out cubic.
abstract final class PrismMotion {
  static const Duration micro = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);

  static const Curve curve = Curves.easeOutCubic;
  static const double pressedScale = 0.985;
}

/// Accent + semantic colors — identical in both modes (SPEC §2).
abstract final class PrismAccent {
  static const Color accent = Color(0xFFE50914);
  static const Color accentHover = Color(0xFFC10710);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  /// Accent red for readable *text* on clay. [accent] (#E50914) is 4.1:1 on
  /// light clay and 3.6:1 on dark clay — fine for fills/icons, below AA for
  /// small text. These pass AA everywhere the app puts accent text:
  /// #C10710 on #E9EDF4 = 5.4:1 (4.9:1 on the darkest clay gradient stop),
  /// #FF8A8A on #171B26 = 7.6:1 (6.4:1 on the lightest).
  static const Color accentTextLight = Color(0xFFC10710);
  static const Color accentTextDark = Color(0xFFFF8A8A);

  /// Ink that sits on top of an accent fill (white works on #E50914 at 4.8:1
  /// in both themes; the accent gradients never go lighter than that).
  static const Color onAccent = Color(0xFFFFFFFF);

  /// Amber that stays legible as *text/icon* on light clay (5.1:1 on #E9EDF4,
  /// 4.6:1 on the #DDE3EC gradient stop). The vivid gold fails at ~1.9:1.
  static const Color starTextLight = Color(0xFF8A5A00);

  /// "Done / watched" green for text and icons on light clay (4.7:1 on
  /// #E9EDF4). The #00D294 status green is a dark-surface accent only.
  static const Color successTextLight = Color(0xFF047857);

  static Color text(bool isLight) => isLight ? accentTextLight : accentTextDark;

  static Color accentGhost(bool isLight) =>
      isLight ? const Color(0x26E50914) : const Color(0x33E50914);
}

/// Light clay (DEFAULT per SPEC §5).
abstract final class PrismLight {
  static const Color bg = Color(0xFFE9EDF4);
  static const Color surface = Color(0xFFE9EDF4);
  static const Color raised = Color(0xFFE9EDF4);
  static const Color sunken = Color(0xFFE9EDF4);
  static const Color glass = Color(0xC7E9EDF4);

  static const Color borderSubtle = Color(0x40A3B1C6);

  /// Body ink on light clay is black by design: the clay is pale, so any
  /// grey here reads washed out on a bright window.
  static const Color ink = Color(0xFF000000);

  /// Secondary text — still black-family (17:1 on [bg]), just lighter in
  /// weight so hierarchy survives without losing contrast.
  static const Color inkSoft = Color(0xFF33383F);

  /// Decorative only (dividers, disabled fills, hairlines). Never readable
  /// text: it is below AA on [bg].
  static const Color inkFaint = Color(0xFF5E6674);

  static const Color neuLight = Color(0xF2FFFFFF);
  static const Color neuDark = Color(0x8CA3B1C6);

  // Raised top-catch for clay gradient (same-hue lift).
  static const Color raisedTop = Color(0xFFF4F7FC);
  static const Color raisedBottom = Color(0xFFDDE3EC);
}

/// Dark clay — re-tuned, not inverted (SPEC §1.10).
abstract final class PrismDark {
  static const Color bg = Color(0xFF171B26);
  static const Color surface = Color(0xFF171B26);
  static const Color raised = Color(0xFF1C2130);
  static const Color sunken = Color(0xFF12151F);
  static const Color glass = Color(0xD1171B26);

  static const Color borderSubtle = Color(0x0FFFFFFF);

  /// Body ink on dark clay is white by design.
  static const Color ink = Color(0xFFFFFFFF);
  static const Color inkSoft = Color(0xFFC6CDDB);

  /// Decorative only — see [PrismLight.inkFaint].
  static const Color inkFaint = Color(0xFF8B93A5);

  static const Color neuLight = Color(0x0FFFFFFF);
  static const Color neuDark = Color(0xA6000000);

  static const Color raisedTop = Color(0xFF232939);
  static const Color raisedBottom = Color(0xFF141824);
}

/// Ink for copy rendered straight on the page backdrop (not on a dark card).
/// Black on light clay, white on dark clay.
abstract final class PrismInk {
  static Color primary(bool isLight) =>
      isLight ? PrismLight.ink : PrismDark.ink;
  static Color soft(bool isLight) =>
      isLight ? PrismLight.inkSoft : PrismDark.inkSoft;
  static Color faint(bool isLight) =>
      isLight ? PrismLight.inkFaint : PrismDark.inkFaint;
}

/// Layout constants (SPEC §2): header 56px, content pad 20px.
///
/// Dock height is exact: 8 top pad + 46 icon + 4 gap + 11 label + 6
/// indicator slot + 8 bottom pad = 83.
abstract final class PrismLayout {
  static const double headerHeight = 56.0;
  static const double dockHeight = 83.0;
  static const double dockTopGap = 12.0;
  static const double dockBottomGap = 16.0;
  static const double contentPad = 20.0;
  static const double cardGap = 16.0;
  static const double desktopMaxWidth = 430.0;

  /// Clear space a scrolling page must leave below its last item.
  static double dockClearance(BuildContext c) =>
      dockTopGap + dockHeight + MediaQuery.paddingOf(c).bottom + dockBottomGap;

  /// Clear space a scrolling page must leave under the floating home app bar.
  /// Bar height = 10 top pad + 48 control row + 14 bottom pad = 72; the extra
  /// 8 keeps the first item off the bar's shadow.
  static double homeAppBarClearance(BuildContext c) =>
      MediaQuery.paddingOf(c).top + 72 + 8;
}

/// Haptics exist on touch platforms only; desktop calls are dead weight.
abstract final class PrismHaptics {
  static bool get enabled =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
