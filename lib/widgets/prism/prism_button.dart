import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/prism_shadows.dart';
import '../../../design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';

/// Prism buttons (SPEC §3 — Sheet & dialog row):
/// Accept = accent fill, Cancel/secondary = neumorphic clay.
class PrismButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool accent;
  final bool small;
  final bool expanded;

  const PrismButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.accent = false,
    this.small = false,
    this.expanded = false,
  });

  @override
  State<PrismButton> createState() => _PrismButtonState();
}

class _PrismButtonState extends State<PrismButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final enabled = widget.onPressed != null;
    final ink = isLight ? PrismLight.ink : PrismDark.ink;
    final soft = isLight ? PrismLight.inkSoft : PrismDark.inkSoft;
    final accent = palette.primaryColor;

    final disabledFill = isLight
        ? PrismLight.inkFaint.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.06);

    final Color labelColor;
    if (!enabled) {
      labelColor = soft;
    } else {
      labelColor = widget.accent ? Colors.white : ink;
    }

    final List<BoxShadow>? shadows;
    if (!enabled) {
      shadows = null;
    } else if (widget.accent) {
      shadows = [
        BoxShadow(
          color: accent.withValues(alpha: 0.4),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
    } else {
      shadows = _pressed
          ? PrismShadows.pressed(isLight: isLight)
          : PrismShadows.raised(isLight: isLight);
    }

    final btn = GestureDetector(
      onTapDown: enabled
          ? (_) {
              setState(() => _pressed = true);
              if (PrismHaptics.enabled) HapticFeedback.lightImpact();
            }
          : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? PrismMotion.pressedScale : 1.0,
        duration: PrismMotion.micro,
        curve: PrismMotion.curve,
        child: Container(
          constraints: const BoxConstraints(minHeight: PrismSpace.giant),
          padding: widget.small
              ? const EdgeInsets.symmetric(
                  horizontal: PrismSpace.md,
                  vertical: PrismSpace.xs,
                )
              : const EdgeInsets.symmetric(
                  horizontal: PrismSpace.lg,
                  vertical: PrismSpace.sm,
                ),
          decoration: BoxDecoration(
            borderRadius: PrismRadius.pillAll,
            color: !enabled ? disabledFill : (widget.accent ? accent : null),
            gradient: !enabled || widget.accent
                ? null
                : (_pressed
                      ? PrismShadows.pressedGradient(isLight)
                      : PrismShadows.surfaceGradient(isLight)),
            boxShadow: shadows,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: widget.small ? 16 : 18,
                  color: labelColor,
                ),
                const SizedBox(width: PrismSpace.xxs),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.small ? PrismType.caption : PrismType.body,
                  fontWeight: PrismType.wBold,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final accessible = Semantics(button: true, enabled: enabled, child: btn);
    if (widget.expanded) {
      return SizedBox(
        width: double.infinity,
        child: Center(child: accessible),
      );
    }
    return accessible;
  }
}

/// Circular clay icon button.
class PrismIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? tint;
  final String? tooltip;

  const PrismIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.tint,
    this.tooltip,
  });

  @override
  State<PrismIconButton> createState() => _PrismIconButtonState();
}

class _PrismIconButtonState extends State<PrismIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final ink = palette.isLight ? PrismLight.ink : PrismDark.ink;
    final enabled = widget.onPressed != null;

    final hitSize = widget.size < PrismSpace.giant
        ? PrismSpace.giant
        : widget.size;

    final visual = AnimatedScale(
      scale: _pressed ? 0.92 : 1.0,
      duration: PrismMotion.micro,
      curve: PrismMotion.curve,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _pressed
              ? PrismShadows.pressedGradient(palette.isLight)
              : PrismShadows.surfaceGradient(palette.isLight),
          boxShadow: _pressed
              ? PrismShadows.pressed(isLight: palette.isLight)
              : PrismShadows.raised(isLight: palette.isLight),
        ),
        child: Icon(
          widget.icon,
          size: widget.size * 0.45,
          color: enabled
              ? (widget.tint ?? ink)
              : (palette.isLight ? PrismLight.inkFaint : PrismDark.inkFaint),
        ),
      ),
    );

    // 48dp hit target even when the visible circle is smaller. The transparent
    // ring must live INSIDE the gesture layer (opaque hit test) or it would be
    // dead space while still reserving 48dp of layout.
    final btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled
          ? (_) {
              setState(() => _pressed = true);
              if (PrismHaptics.enabled) HapticFeedback.lightImpact();
            }
          : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onPressed,
      child: SizedBox(
        width: hitSize,
        height: hitSize,
        child: Center(child: visual),
      ),
    );

    final accessible = Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: btn,
    );
    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: accessible);
    }
    return accessible;
  }
}
