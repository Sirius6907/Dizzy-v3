import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/utils/tv/tv_gate.dart';

/// Polish P13: Firestick remote contract frozen.
void main() {
  group('TvGate', () {
    test('overscan margin is 24dp all sides', () {
      expect(TvGate.kOverscan, const EdgeInsets.all(24.0));
    });

    test('select keys: enter, numpad-enter, space, gamepad-A', () {
      expect(TvGate.isSelectKey(LogicalKeyboardKey.enter), isTrue);
      expect(TvGate.isSelectKey(LogicalKeyboardKey.numpadEnter), isTrue);
      expect(TvGate.isSelectKey(LogicalKeyboardKey.space), isTrue);
      expect(TvGate.isSelectKey(LogicalKeyboardKey.gameButtonA), isTrue);
      expect(TvGate.isSelectKey(LogicalKeyboardKey.escape), isFalse);
      expect(TvGate.isSelectKey(LogicalKeyboardKey.arrowLeft), isFalse);
    });

    test('arrow keys detected, others ignored', () {
      expect(TvGate.isArrowKey(LogicalKeyboardKey.arrowLeft), isTrue);
      expect(TvGate.isArrowKey(LogicalKeyboardKey.arrowUp), isTrue);
      expect(TvGate.isArrowKey(LogicalKeyboardKey.enter), isFalse);
      expect(TvGate.isArrowKey(LogicalKeyboardKey.keyA), isFalse);
    });

    test('focus ring brightens when focused', () {
      final on = TvGate.focusRing(focused: true);
      final off = TvGate.focusRing(focused: false);
      expect(on.border!.top.color, Colors.white);
      expect(on.border!.top.width, 2.5);
      expect(off.border!.top.width, 1.5);
    });
  });
}
