import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';

/// Phase 3 — Boss Pocket GT style rotary dial.
///
/// Pure [CustomPainter] brushed-metal knob. Zero [BackdropFilter],
/// zero [ShaderMask], zero GPU blur — only [Paint], [Rect], [Path],
/// [LinearGradient] (as static color stops) and static [BoxShadow].
///
/// Touch angle is derived from `atan2` around the dial centre and
/// snapped to [segments] detents. [HapticFeedback.lightImpact] fires
/// once per detent crossing.
class DizzyRotaryDial extends StatefulWidget {
  final double min;
  final double max;
  final double value;
  final ValueChanged<double>? onChanged;
  final int segments;
  final double size;
  final Color accent;
  final String? label;

  const DizzyRotaryDial({
    super.key,
    this.min = 0.0,
    this.max = 100.0,
    required this.value,
    this.onChanged,
    this.segments = 12,
    this.size = 96.0,
    this.accent = DizzyGlow.red,
    this.label,
  });

  @override
  State<DizzyRotaryDial> createState() => _DizzyRotaryDialState();
}

class _DizzyRotaryDialState extends State<DizzyRotaryDial> {
  int _lastDetent = -1;

  double get _range => (widget.max - widget.min) <= 0 ? 1.0 : widget.max - widget.min;

  double get _normalized =>
      ((widget.value - widget.min) / _range).clamp(0.0, 1.0);

  double get _sweepAngle => _normalized * 270.0; // -135° .. +135°

  double _stepValue() => _range / math.max(1, widget.segments);

  void _updateFromOffset(Offset local, double dialRadius) {
    if (widget.onChanged == null) return;
    // Angle of finger relative to centre. 0 rad = +x axis.
    final dx = local.dx - dialRadius;
    final dy = local.dy - dialRadius;
    var angleDeg = math.atan2(dy, dx) * 180.0 / math.pi; // -180..180
    // Map so that top (-90°) is centre of travel.
    // Sweep runs from -135°..+135° around the top dead zone at bottom.
    var travel = angleDeg + 90.0; // -90°(left-down)... 0(top) ...+90
    if (travel < -135.0) travel += 360.0;
    if (travel > 135.0) {
      // Bottom dead-zone: clamp to nearest end instead of wrapping.
      travel = travel > 180.0 ? -135.0 : 135.0;
    }
    travel = travel.clamp(-135.0, 135.0);
    final normalized = (travel + 135.0) / 270.0;
    final raw = widget.min + normalized * _range;
    // Snap to detents.
    final step = _stepValue();
    final snapped =
        (widget.min + ((raw - widget.min) / step).round() * step)
            .clamp(widget.min, widget.max);
    final detent = ((snapped - widget.min) / step).round();
    if (detent != _lastDetent) {
      _lastDetent = detent;
      HapticFeedback.lightImpact();
    }
    if ((snapped - widget.value).abs() > 1e-9) {
      widget.onChanged!(snapped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final radius = size / 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            // GestureDetector wraps the dial box only (first child), so
            // translate global -> dial-local by subtracting label offset is
            // unnecessary: use local position directly via details.localPosition
            // is not available on PanDown in this path — fall back to global.
            final local = box.globalToLocal(d.globalPosition);
            _updateFromOffset(local, radius);
          },
          onPanUpdate: (d) => _updateFromOffset(d.localPosition, radius),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: DizzyGradients.tactileSurface,
              border: Border.fromBorderSide(DizzyEdge.hairline),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x8C000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
                BoxShadow(
                  color: Color(0x14FFFFFF),
                  blurRadius: 0,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RotaryDialPainter(
                  sweepAngle: _sweepAngle,
                  segments: widget.segments,
                  accent: widget.accent,
                ),
              ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: DizzySpace.xs),
          Text(
            widget.label!,
            style: const TextStyle(
              color: DizzyVoid.ash,
              fontSize: DizzyType.caption,
              fontWeight: DizzyType.wMedium,
            ),
          ),
        ],
      ],
    );
  }
}

class _RotaryDialPainter extends CustomPainter {
  final double sweepAngle; // 0..270
  final int segments;
  final Color accent;

  const _RotaryDialPainter({
    required this.sweepAngle,
    required this.segments,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Brushed-metal concentric rings (static alpha bands, no shaders).
    final ringPaint = Paint()..style = PaintingStyle.stroke;
    const ringColors = [
      Color(0xFF3A3E4A),
      Color(0xFF2A2E3A),
      Color(0xFF343845),
      DizzyVoid.surface3,
      Color(0xFF2E323E),
    ];
    for (int i = 0; i < ringColors.length; i++) {
      ringPaint
        ..color = ringColors[i]
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, r - 6 - i * ((r - 14) / ringColors.length), ringPaint);
    }

    // Tick marks around the outer bezel: -135°..+135° measured from top.
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final tickCount = math.max(2, segments + 1);
    for (int i = 0; i < tickCount; i++) {
      final t = i / (tickCount - 1); // 0..1
      final angleDeg = -135.0 + t * 270.0;
      final rad = (angleDeg - 90.0) * math.pi / 180.0;
      final isMajor = i % math.max(1, (tickCount / 4).round()) == 0 ||
          i == 0 ||
          i == tickCount - 1;
      final inner = r - (isMajor ? 12.0 : 9.0);
      final outer = r - 4.0;
      final active = (t * 270.0) <= sweepAngle + 0.001;
      tickPaint
        ..color = active ? accent : const Color(0xFF6B7080)
        ..strokeWidth = isMajor ? 2.2 : 1.2;
      canvas.drawLine(
        center + Offset(math.cos(rad) * inner, math.sin(rad) * inner),
        center + Offset(math.cos(rad) * outer, math.sin(rad) * outer),
        tickPaint,
      );
    }

    // Knob cap.
    final capR = r * 0.62;
    final capPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = DizzyVoid.surface2;
    canvas.drawCircle(center, capR, capPaint);
    final capEdge = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.14)
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, capR, capEdge);

    // Pointer line: angle measured from top.
    final pointerRad = (sweepAngle - 135.0 - 90.0) * math.pi / 180.0;
    final pointerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = accent
      ..strokeWidth = 3.0;
    canvas.drawLine(
      center + Offset(math.cos(pointerRad) * (capR * 0.25), math.sin(pointerRad) * (capR * 0.25)),
      center + Offset(math.cos(pointerRad) * (capR - 4), math.sin(pointerRad) * (capR - 4)),
      pointerPaint,
    );

    // Centre dot.
    canvas.drawCircle(
      center,
      3.0,
      Paint()
        ..style = PaintingStyle.fill
        ..color = DizzyVoid.ash,
    );
  }

  @override
  bool shouldRepaint(covariant _RotaryDialPainter old) =>
      old.sweepAngle != sweepAngle ||
      old.segments != segments ||
      old.accent != accent;
}
