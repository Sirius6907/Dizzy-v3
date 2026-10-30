import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/prism_shadows.dart';
import '../../../design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';

/// Prism chips (SPEC §3): selected = accent fill with white text
/// OR inset-sunken ([inset] = true).
class PrismChip extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool inset;
  final VoidCallback? onTap;

  const PrismChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.inset = false,
    this.onTap,
  });

  @override
  State<PrismChip> createState() => _PrismChipState();
}

class _PrismChipState extends State<PrismChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final enabled = widget.onTap != null;
    final accent = palette.primaryColor;
    final soft = isLight ? PrismLight.inkSoft : PrismDark.inkSoft;
    final accentSelected = widget.selected && !widget.inset;
    final disabledFill = isLight
        ? PrismLight.inkFaint.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.06);

    final Color labelColor;
    if (!enabled) {
      labelColor = soft;
    } else if (accentSelected) {
      labelColor = Colors.white;
    } else if (widget.selected) {
      // Inset-selected sits on clay: accent text token for AA (12px).
      labelColor = PrismAccent.text(isLight);
    } else {
      labelColor = soft;
    }

    final pill = AnimatedScale(
      scale: _pressed ? PrismMotion.pressedScale : 1.0,
      duration: PrismMotion.micro,
      curve: PrismMotion.curve,
      child: AnimatedContainer(
        duration: PrismMotion.micro,
        curve: PrismMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: PrismSpace.md,
          vertical: PrismSpace.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: PrismRadius.pillAll,
          color: !enabled ? disabledFill : (accentSelected ? accent : null),
          gradient: !enabled || accentSelected
              ? null
              : ((widget.selected || _pressed)
                    ? PrismShadows.pressedGradient(isLight)
                    : PrismShadows.surfaceGradient(isLight)),
          boxShadow: !enabled
              ? null
              : (accentSelected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : ((widget.selected || _pressed)
                          ? PrismShadows.pressed(isLight: isLight, scale: 0.8)
                          : PrismShadows.soft(isLight: isLight))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 15, color: labelColor),
              const SizedBox(width: PrismSpace.xxs),
            ],
            Text(
              widget.label,
              style: TextStyle(
                fontSize: PrismType.caption,
                fontWeight: widget.selected
                    ? PrismType.wBold
                    : PrismType.wMedium,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled
            ? (_) {
                setState(() => _pressed = true);
                if (PrismHaptics.enabled) HapticFeedback.selectionClick();
              }
            : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        // 48dp hit target; the visible pill stays compact.
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: PrismSpace.giant,
            minHeight: PrismSpace.giant,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [pill]),
        ),
      ),
    );
  }
}

/// Prism toggle — clay track, knob pops with spring easing (SPEC §1.6).
class PrismToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  const PrismToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final ink = palette.isLight ? PrismLight.ink : PrismDark.ink;
    final knob = activeColor ?? palette.primaryColor;

    return Semantics(
      button: true,
      toggled: value,
      enabled: onChanged != null,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: PrismMotion.standard,
          curve: PrismMotion.curve,
          width: 52,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PrismRadius.pill),
            gradient: value
                ? null
                : PrismShadows.pressedGradient(palette.isLight),
            color: value ? knob : null,
            boxShadow: value
                ? [
                    BoxShadow(
                      color: knob.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : PrismShadows.pressed(isLight: palette.isLight),
          ),
          child: AnimatedAlign(
            duration: PrismMotion.standard,
            curve: PrismMotion.curve,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: PrismShadows.surfaceGradient(palette.isLight),
                boxShadow: PrismShadows.soft(isLight: palette.isLight),
              ),
              child: value
                  ? Icon(Icons.check_rounded, size: 14, color: ink)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Prism settings row — clay tile, icon medallion, [PrismToggle]/switch.
class PrismToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const PrismToggleRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final ink = palette.isLight ? PrismLight.ink : PrismDark.ink;
    final soft = palette.isLight ? PrismLight.inkSoft : PrismDark.inkSoft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: PrismRadius.lgAll,
        gradient: PrismShadows.surfaceGradient(palette.isLight),
        boxShadow: PrismShadows.raised(isLight: palette.isLight, scale: 0.7),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: PrismShadows.pressedGradient(palette.isLight),
              boxShadow: PrismShadows.pressed(
                isLight: palette.isLight,
                scale: 0.8,
              ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: value ? palette.primaryColor : soft,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: PrismType.wBold,
                    color: ink,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: soft, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
          PrismToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
