import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/design/dizzy_tokens.dart';

/// Polish P1: design tokens freeze — scale order + legacy value parity.
/// Koi token badle to ye test chillayega (deliberate change = test update).
void main() {
  group('DizzySpace (4-pt grid, ascending)', () {
    test('xs < sm < md < lg < xl < xxl', () {
      expect(DizzySpace.xs, lessThan(DizzySpace.sm));
      expect(DizzySpace.sm, lessThan(DizzySpace.md));
      expect(DizzySpace.md, lessThan(DizzySpace.lg));
      expect(DizzySpace.lg, lessThan(DizzySpace.xl));
      expect(DizzySpace.xl, lessThan(DizzySpace.xxl));
    });
  });

  group('DizzyType (sizes descending)', () {
    test('display > headline > title > subtitle > body > caption > micro', () {
      expect(DizzyType.display, greaterThan(DizzyType.headline));
      expect(DizzyType.headline, greaterThan(DizzyType.title));
      expect(DizzyType.title, greaterThan(DizzyType.subtitle));
      expect(DizzyType.subtitle, greaterThan(DizzyType.body));
      expect(DizzyType.body, greaterThan(DizzyType.caption));
      expect(DizzyType.caption, greaterThan(DizzyType.micro));
    });
  });

  group('DizzyMotion', () {
    test('controls auto-hide stays 4s (player + docs contract)', () {
      expect(DizzyMotion.controlsAutoHide, const Duration(seconds: 4));
    });

    test('durations ascending instant < fast < standard < slow', () {
      expect(DizzyMotion.instant, lessThan(DizzyMotion.fast));
      expect(DizzyMotion.fast, lessThan(DizzyMotion.standard));
      expect(DizzyMotion.standard, lessThan(DizzyMotion.slow));
    });
  });

  group('DizzyColors (legacy details-page parity)', () {
    test('dark baseline values unchanged', () {
      expect(DizzyColors.bg, const Color(0xFF0B0D12));
      expect(DizzyColors.surface, const Color(0xFF15171F));
      expect(DizzyColors.accent, const Color(0xFFE50914));
      expect(DizzyColors.accentDim, const Color(0xFF9A0710));
      expect(DizzyColors.gold, const Color(0xFFFFC107));
      expect(DizzyColors.avatarPairs, hasLength(6));
    });
  });

  group('DizzyBreakpoints', () {
    test('mobile < tablet', () {
      expect(DizzyBreakpoints.mobile, lessThan(DizzyBreakpoints.tablet));
    });
  });
}
