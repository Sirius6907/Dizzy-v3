import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/utils/motion/motion_gate.dart';

/// Polish P11: motion scale frozen + reduced-motion respected.
void main() {
  group('DizzyMotion scale (P11 freeze)', () {
    test('ascending through hero', () {
      expect(DizzyMotion.slow, lessThan(DizzyMotion.hero));
      expect(DizzyMotion.hero, const Duration(milliseconds: 700));
    });
  });

  group('MotionGate', () {
    test('normal motion keeps the token', () {
      expect(
        MotionGate.resolve(DizzyMotion.fast, reduceMotion: false),
        DizzyMotion.fast,
      );
      expect(
        MotionGate.page(reduceMotion: false),
        DizzyMotion.slow,
      );
    });

    test('reduced motion snaps to zero', () {
      expect(
        MotionGate.resolve(DizzyMotion.hero, reduceMotion: true),
        Duration.zero,
      );
      expect(MotionGate.micro(reduceMotion: true), Duration.zero);
      expect(MotionGate.page(reduceMotion: true), Duration.zero);
    });
  });
}
