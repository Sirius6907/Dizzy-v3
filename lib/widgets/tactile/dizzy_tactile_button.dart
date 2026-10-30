import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';

/// A physical, extruded neo-skeuomorphic tactile button with 0% runtime GPU blur shaders.
/// Uses static dual-shadows and gradient inversion on press for an authentic tactile click.
class DizzyTactileButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Gradient? gradient;
  final Color? glowColor;
  final BorderSide? border;
  final bool isSelected;

  const DizzyTactileButton({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.width,
    this.height,
    this.padding,
    this.borderRadius,
    this.gradient,
    this.glowColor,
    this.border,
    this.isSelected = false,
  });

  @override
  State<DizzyTactileButton> createState() => _DizzyTactileButtonState();
}

class _DizzyTactileButtonState extends State<DizzyTactileButton> {
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
    final radius = widget.borderRadius ?? BorderRadius.circular(DizzyRadius.lg);
    final isInteractive = widget.onTap != null;

    final palette = AppThemeService.currentPalette.value;

    // Prism clay: convex raised vs concave pressed. Custom gradient
    // override still respected (studio previews), glow ring kept.
    final effectiveGradient = _isPressed
        ? PrismShadows.pressedGradient(palette.isLight)
        : (widget.gradient ?? PrismShadows.surfaceGradient(palette.isLight));

    final List<BoxShadow> effectiveShadows = [
      ...(_isPressed
          ? PrismShadows.pressed(isLight: palette.isLight, scale: 0.8)
          : PrismShadows.raised(isLight: palette.isLight, scale: 0.6)),
      if (widget.glowColor != null)
        BoxShadow(
          color: widget.glowColor!.withValues(
            alpha: widget.isSelected ? 0.35 : 0.20,
          ),
          blurRadius: 16,
          offset: Offset.zero,
        ),
    ];

    final effectiveBorder =
        widget.border ??
        (widget.isSelected && widget.glowColor != null
            ? DizzyEdge.neon(widget.glowColor!)
            : null);

    return GestureDetector(
      onTapDown: isInteractive ? _handleTapDown : null,
      onTapUp: isInteractive ? _handleTapUp : null,
      onTapCancel: isInteractive ? _handleTapCancel : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress != null
          ? () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            }
          : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: effectiveGradient,
            border: effectiveBorder == null
                ? null
                : Border.fromBorderSide(effectiveBorder),
            boxShadow: effectiveShadows,
          ),
          child: Center(
            child: Padding(
              padding:
                  widget.padding ??
                  const EdgeInsets.symmetric(
                    horizontal: DizzySpace.md,
                    vertical: DizzySpace.sm,
                  ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
