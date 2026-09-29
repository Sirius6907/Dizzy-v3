import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';

/// Phase 5 — hardware 7-segment LED numeric display.
///
/// Digits 0-9 (plus `-` and blank) rendered with raw [Path] segments —
/// no [Text] widget, so the look stays authentic OLED hardware.
/// Active segments glow in [activeColor], off segments sit dark on
/// [DizzyVoid.obsidian].
class Dizzy7Segment extends StatelessWidget {
  final String value;
  final int digits;
  final double digitWidth;
  final double digitHeight;
  final Color activeColor;
  final Color offColor;
  final double segmentThickness;

  const Dizzy7Segment({
    super.key,
    required this.value,
    this.digits = 2,
    this.digitWidth = 30.0,
    this.digitHeight = 56.0,
    this.activeColor = DizzyGlow.red,
    this.offColor = const Color(0xFF1E1214),
    this.segmentThickness = 5.0,
  });

  @override
  Widget build(BuildContext context) {
    final chars = value.padLeft(digits, ' ').split('').reversed.take(digits).toList().reversed.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: DizzyVoid.obsidian,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < chars.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            RepaintBoundary(
              child: CustomPaint(
                size: Size(digitWidth, digitHeight),
                painter: _DigitPainter(
                  char: chars[i],
                  active: activeColor,
                  off: offColor,
                  thickness: segmentThickness,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Segment layout: a(top) b(top-right) c(bottom-right) d(bottom)
//                e(bottom-left) f(top-left) g(middle)
const Map<String, List<bool>> _segmentMap = {
  '0': [true, true, true, true, true, true, false],
  '1': [false, true, true, false, false, false, false],
  '2': [true, true, false, true, true, false, true],
  '3': [true, true, true, true, false, false, true],
  '4': [false, true, true, false, false, true, true],
  '5': [true, false, true, true, false, true, true],
  '6': [true, false, true, true, true, true, true],
  '7': [true, true, true, false, false, false, false],
  '8': [true, true, true, true, true, true, true],
  '9': [true, true, true, true, false, true, true],
  '-': [false, false, false, false, false, false, true],
  ' ': [false, false, false, false, false, false, false],
};

class _DigitPainter extends CustomPainter {
  final String char;
  final Color active;
  final Color off;
  final double thickness;

  const _DigitPainter({
    required this.char,
    required this.active,
    required this.off,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final on = _segmentMap[char] ?? _segmentMap[' ']!;
    final w = size.width;
    final h = size.height;
    final t = thickness;
    final mid = h / 2;

    Path horiz(double x, double y, double len) {
      final hh = t / 2;
      return Path()
        ..moveTo(x + hh, y)
        ..lineTo(x + len - hh, y)
        ..lineTo(x + len - t, y + hh)
        ..lineTo(x + len - hh, y + t)
        ..lineTo(x + hh, y + t)
        ..lineTo(x + t, y + hh)
        ..close();
    }

    Path vert(double x, double y, double len) {
      final hh = t / 2;
      return Path()
        ..moveTo(x, y + hh)
        ..lineTo(x + hh, y + t)
        ..lineTo(x + t, y + len - hh)
        ..lineTo(x + hh, y + len - t)
        ..lineTo(x, y + len - hh)
        ..lineTo(x - hh + t / 2, y + len / 2)
        ..close();
    }

    final segs = <Path>[
      horiz(t, 0, w - 2 * t), // a
      vert(w - t, t + 1, mid - t - 2), // b
      vert(w - t, mid + 1, mid - t - 2), // c
      horiz(t, h - t, w - 2 * t), // d
      vert(0, mid + 1, mid - t - 2), // e
      vert(0, t + 1, mid - t - 2), // f
      horiz(t, mid - t / 2, w - 2 * t), // g
    ];

    for (int i = 0; i < 7; i++) {
      final isOn = i < on.length && on[i];
      // Flat LED fill + brighter core when on (two static paints).
      canvas.drawPath(
        segs[i],
        Paint()
          ..style = PaintingStyle.fill
          ..color = isOn ? active.withValues(alpha: 0.32) : off,
      );
      if (isOn) {
        canvas.drawPath(
          segs[i],
          Paint()
            ..style = PaintingStyle.fill
            ..color = active,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DigitPainter old) =>
      old.char != char ||
      old.active != active ||
      old.off != off ||
      old.thickness != thickness;
}
