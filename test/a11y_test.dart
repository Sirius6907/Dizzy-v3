import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/utils/a11y/a11y.dart';

/// Polish P12: 200% font safety + 48dp touch targets frozen.
void main() {
  group('DizzyA11y', () {
    test('max text scale is 200%', () {
      expect(DizzyA11y.kMaxTextScale, 2.0);
    });

    test('clampScale keeps readable range', () {
      expect(DizzyA11y.clampScale(1.0), 1.0);
      expect(DizzyA11y.clampScale(1.5), 1.5);
      expect(DizzyA11y.clampScale(2.0), 2.0);
      // Safety rail beyond 200% — layout never breaks.
      expect(DizzyA11y.clampScale(3.0), 2.0);
      // Never shrink below normal.
      expect(DizzyA11y.clampScale(0.5), 1.0);
    });

    test('touch target guideline is 48dp', () {
      expect(DizzyA11y.kMinTouchTarget, 48.0);
      expect(DizzyA11y.meetsTouchTarget(48, 48), isTrue);
      expect(DizzyA11y.meetsTouchTarget(64, 48), isTrue);
      expect(DizzyA11y.meetsTouchTarget(28, 28), isFalse);
    });
  });
}
