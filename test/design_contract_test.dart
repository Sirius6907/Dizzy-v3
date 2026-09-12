import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/services/profiles/kids_mode.dart';
import 'package:dizzy/utils/a11y/a11y.dart';
import 'package:dizzy/utils/perf/image_caps.dart';
import 'package:dizzy/utils/tv/tv_gate.dart';

/// Polish P16 — ONE gate for every polish contract (P1–P15).
///
/// Har phase ke baad ye green = visual diff green.
/// Koi token/contract badle to ye sabse pehle chillayega.
void main() {
  group('Design contract (P16 harness)', () {
    test('spacing is a 4-pt grid', () {
      for (final v in [
        DizzySpace.xxs,
        DizzySpace.xs,
        DizzySpace.sm,
        DizzySpace.md,
        DizzySpace.lg,
        DizzySpace.xl,
        DizzySpace.xxl,
      ]) {
        expect(v % 4, 0, reason: 'space $v breaks the grid');
      }
    });

    test('overscan rides the spacing grid (P13)', () {
      expect(TvGate.kOverscan.left, DizzySpace.lg);
    });

    test('P23 image contract holds (P14)', () {
      expect(ImageCaps.kBackdrop, lessThanOrEqualTo(960));
      expect(ImageCaps.kLogo, lessThanOrEqualTo(400));
    });

    test('player auto-hide stays 4s (P4/P11)', () {
      expect(DizzyMotion.controlsAutoHide, const Duration(seconds: 4));
    });

    test('200% font rail stands (P12)', () {
      expect(DizzyA11y.kMaxTextScale, 2.0);
    });

    test('kids accent never equals brand purple (P15)', () {
      expect(KidsMode.kKidsAccent, isNot(DizzyColors.accent));
    });

    test('radii sane: pill huge, rest small (P1)', () {
      expect(DizzyRadius.pill, greaterThan(100));
      expect(DizzyRadius.sm, lessThan(DizzyRadius.md));
      expect(DizzyRadius.md, lessThan(DizzyRadius.lg));
      expect(DizzyRadius.lg, lessThan(DizzyRadius.xl));
    });

    test('breakpoints leave phone room (P1)', () {
      expect(DizzyBreakpoints.mobile, 600.0);
    });
  });
}
