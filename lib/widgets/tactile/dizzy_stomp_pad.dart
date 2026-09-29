import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';

/// Phase 6 — single Boss-style stomp pad.
///
/// Extruded tactile tile: static [BoxShadow] depth, top-edge light
/// catch, mechanical depression (2px translate + carved gradient +
/// accent wash) while held. Raw [GestureDetector] — no [InkWell],
/// no [Material] ink, no GPU blur.
class DizzyStompPad extends StatefulWidget {
  final String? label;
  final Widget? icon;
  final VoidCallback? onTap;
  final bool toggled;
  final Color accent;
  final double? width;
  final double? height;

  const DizzyStompPad({
    super.key,
    this.label,
    this.icon,
    this.onTap,
    this.toggled = false,
    this.accent = DizzyGlow.red,
    this.width,
    this.height = 72.0,
  });

  @override
  State<DizzyStompPad> createState() => _DizzyStompPadState();
}

class _DizzyStompPadState extends State<DizzyStompPad> {
  bool _held = false;

  void _down(TapDownDetails _) {
    if (widget.onTap == null) return;
    setState(() => _held = true);
    HapticFeedback.mediumImpact();
  }

  void _up(TapUpDetails _) {
    if (_held) setState(() => _held = false);
  }

  void _cancel() {
    if (_held) setState(() => _held = false);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _held || widget.toggled;
    final radius = BorderRadius.circular(DizzyRadius.md);
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : _down,
      onTapUp: widget.onTap == null ? null : _up,
      onTapCancel: widget.onTap == null ? null : _cancel,
      onTap: widget.onTap,
      child: Transform.translate(
        offset: pressed ? const Offset(0, 2) : Offset.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: pressed
                ? DizzyGradients.carvedSurface
                : DizzyGradients.tactileSurface,
            border: Border.fromBorderSide(
              pressed
                  ? DizzyEdge.neon(widget.accent)
                  : DizzyEdge.hairline,
            ),
            boxShadow: pressed
                ? DizzyShadow.pressed
                : [
                    const BoxShadow(
                      color: Color(0x8C000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                    const BoxShadow(
                      color: Color(0x14FFFFFF),
                      blurRadius: 0,
                      offset: Offset(0, 1),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              if (!pressed)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: DizzyGradients.topInnerGlow(0.10),
                      ),
                    ),
                  ),
                ),
              if (pressed)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        color: widget.accent.withValues(alpha: 0.20),
                      ),
                    ),
                  ),
                ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) widget.icon!,
                    if (widget.icon != null && widget.label != null)
                      const SizedBox(height: 4),
                    if (widget.label != null)
                      Text(
                        widget.label!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: pressed ? widget.accent : DizzyVoid.bone,
                          fontSize: DizzyType.caption,
                          fontWeight: DizzyType.wSemiBold,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Container(
                      width: 22,
                      height: 5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: pressed
                            ? widget.accent
                            : DizzyVoid.surface3,
                        border: Border.all(
                          color: DizzyVoid.obsidian
                              .withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
