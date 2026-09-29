import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tactile.dart';

/// Phase 32 — Single vertical EQ fader with tactile drag + haptic feedback.
class DizzyEqFader extends StatefulWidget {
  final double value;
  final String? label;
  final double height;
  final ValueChanged<double>? onChanged;

  const DizzyEqFader({
    super.key,
    required this.value,
    this.label,
    this.height = 140,
    this.onChanged,
  });

  @override
  State<DizzyEqFader> createState() => _DizzyEqFaderState();
}

class _DizzyEqFaderState extends State<DizzyEqFader> {
  late double _current;

  @override
  void initState() {
    super.initState();
    _current = widget.value.clamp(-12.0, 12.0);
  }

  @override
  void didUpdateWidget(covariant DizzyEqFader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _current = widget.value.clamp(-12.0, 12.0);
    }
  }

  double _thumbProgress(double gain) {
    final double clamped = gain.clamp(-12.0, 12.0);
    return (clamped + 12.0) / 24.0;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                widget.label!,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                final Size size = box.size;
                final double delta = -details.delta.dy / size.height;
                setState(() {
                  _current = (_current + delta * 12.0).clamp(-12.0, 12.0);
                });
                widget.onChanged?.call(_current);
                HapticFeedback.lightImpact();
              },
              onVerticalDragEnd: (_) {
                HapticFeedback.mediumImpact();
              },
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _current = 0.0;
                });
                widget.onChanged?.call(_current);
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 6,
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Positioned(
                    left: -13,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 40),
                      width: 30,
                      height: widget.height * _thumbProgress(_current),
                      decoration: BoxDecoration(
                        gradient: DizzyGradients.accent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: DizzyShadow.card,
                      ),
                    ),
                  ),
                  Positioned(
                    left: -13,
                    bottom: 0,
                    child: IgnorePointer(
                      child: SizedBox(
                        width: 30,
                        height: widget.height,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: DizzyGlow.beam,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.20),
                                      width: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.label != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _current.toStringAsFixed(1),
                style: const TextStyle(
                    color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
