import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/prism_shadows.dart';
import '../../../design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';

/// Prism clay card — raised object on a surface (SPEC §1.1).
///
/// THREE-part shadow: light (top-left) + dark (bottom-right) + 1px inner
/// top highlight overlay. Press sinks (inset illusion + scale .985).
class PrismCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? glowColor;
  final double shadowScale;

  const PrismCard({
    super.key,
    required this.child,
    this.onTap,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.glowColor,
    this.shadowScale = 1.0,
  });

  @override
  State<PrismCard> createState() => _PrismCardState();
}

class _PrismCardState extends State<PrismCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final radius = widget.borderRadius ?? PrismRadius.lgAll;
    final interactive = widget.onTap != null;
    final repoShadows = _pressed
        ? PrismShadows.pressed(
            isLight: palette.isLight,
            scale: widget.shadowScale,
          )
        : PrismShadows.raised(
            isLight: palette.isLight,
            scale: widget.shadowScale,
          );

    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      child: GestureDetector(
        onTapDown: interactive
            ? (_) {
                setState(() => _pressed = true);
                HapticFeedback.lightImpact();
              }
            : null,
        onTapUp: interactive ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: interactive
            ? () => setState(() => _pressed = false)
            : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? PrismMotion.pressedScale : 1.0,
          duration: PrismMotion.micro,
          curve: PrismMotion.curve,
          child: Container(
            padding: widget.padding ?? const EdgeInsets.all(PrismSpace.md),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: _pressed
                  ? PrismShadows.pressedGradient(palette.isLight)
                  : PrismShadows.surfaceGradient(palette.isLight),
              boxShadow: [
                ...repoShadows,
                // Halo only at rest: pressed shadows + glow would stack.
                if (widget.glowColor != null && !_pressed)
                  BoxShadow(
                    color: widget.glowColor!.withValues(alpha: 0.22),
                    blurRadius: 26 * widget.shadowScale,
                    offset: Offset(0, 12 * widget.shadowScale),
                  ),
              ],
              border: widget.glowColor != null
                  ? Border.all(
                      color: widget.glowColor!.withValues(alpha: 0.45),
                      width: 1.1,
                    )
                  : null,
            ),
            child: Stack(
              children: [
                // 1px inner top highlight (third shadow part).
                if (!_pressed)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: PrismShadows.topHighlight(palette.isLight),
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
