import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';

/// A physical, extruded neo-skeuomorphic tactile card container.
/// Zero runtime shaders, zero GPU overhead.
class DizzyTactileCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? glowColor;
  final Color? borderColor;
  final Gradient? gradient;

  const DizzyTactileCard({
    super.key,
    required this.child,
    this.onTap,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.glowColor,
    this.borderColor,
    this.gradient,
  });

  @override
  State<DizzyTactileCard> createState() => _DizzyTactileCardState();
}

class _DizzyTactileCardState extends State<DizzyTactileCard> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = true);
    HapticFeedback.lightImpact();
  }

  void _handleTapUp(TapUpDetails _) {
    if (_isPressed) setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    if (_isPressed) setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(DizzyRadius.xl);
    final isInteractive = widget.onTap != null;

    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      child: GestureDetector(
        onTapDown: isInteractive ? _handleTapDown : null,
        onTapUp: isInteractive ? _handleTapUp : null,
        onTapCancel: isInteractive ? _handleTapCancel : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: widget.padding ?? const EdgeInsets.all(DizzySpace.md),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: widget.gradient ??
                  const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [DizzyVoid.surface2, DizzyVoid.surface1],
                  ),
              border: Border.fromBorderSide(
                widget.borderColor != null
                    ? BorderSide(color: widget.borderColor!, width: 1.0)
                    : widget.glowColor != null
                        ? DizzyEdge.neon(widget.glowColor!)
                        : DizzyEdge.hairline,
              ),
              boxShadow: _isPressed ? DizzyShadow.pressed : DizzyShadow.card,
            ),
            child: Stack(
              children: [
                // Top inner specular edge
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: DizzyGradients.topInnerGlow(0.08),
                      ),
                    ),
                  ),
                ),
                widget.child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
