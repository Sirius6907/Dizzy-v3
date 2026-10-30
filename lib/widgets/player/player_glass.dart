import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';

/// Design tokens and glass styling for the modern video player UI.
class PlayerTheme {
  // Backgrounds & Surfaces
  static const Color canvas = DizzyVoid.voidB;
  static const Color elevated = Color(0xF0101622);
  static const Color raised = Color(0x1AFFFFFF); // 10% white
  static const Color surfaceHover = Color(0x22FFFFFF); // 13% white

  // Borders
  static const Color edge = Color(0x1FFFFFFF); // 12% white
  static const Color edgeSoft = Color(0x12FFFFFF); // 7% white

  // Accents
  static const Color accent = Color(0xFF7C5CFF);
  static const Color accentSoft = Color(0x337C5CFF);
  static const Color accentGlow = Color(0x667C5CFF);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  // Typography / Text Colors
  static const Color ink = Colors.white;
  static const Color inkMuted = Color(0xB3FFFFFF); // 70% white
  static const Color inkSubtle = Color(0x66FFFFFF); // 40% white
  static const Color inkDisabled = Color(0x33FFFFFF); // 20% white

  // Shadows
  static const List<BoxShadow> menuShadow = [
    BoxShadow(
      color: Color(0xCC000000),
      offset: Offset(0, 24),
      blurRadius: 60,
      spreadRadius: -18,
    ),
    BoxShadow(
      color: Color(0x40000000),
      offset: Offset(0, 10),
      blurRadius: 30,
      spreadRadius: -5,
    ),
  ];

  static const List<BoxShadow> buttonShadow = [
    BoxShadow(color: Color(0x4D000000), offset: Offset(0, 4), blurRadius: 16),
  ];
}

/// Floating Frosted Glass Card for menus, dialogs, and popovers.
class PlayerGlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Border? border;
  final List<BoxShadow>? shadows;
  final Color? backgroundColor;

  const PlayerGlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = 20,
    this.padding = EdgeInsets.zero,
    this.border,
    this.shadows,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? PlayerTheme.elevated,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(color: PlayerTheme.edge),
        boxShadow: shadows ?? PlayerTheme.menuShadow,
      ),
      child: child,
    );
  }
}

/// Interactive button with smooth hover effects, tooltips, and badges.
class PlayerIconButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool active;
  final Color? activeColor;
  final bool showActiveBadge;
  final Color? badgeColor;
  final Color? backgroundColor;
  final double borderRadius;

  const PlayerIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 44,
    this.iconSize = 22,
    this.active = false,
    this.activeColor,
    this.showActiveBadge = false,
    this.badgeColor,
    this.backgroundColor,
    this.borderRadius = 9999,
  });

  @override
  State<PlayerIconButton> createState() => _PlayerIconButtonState();
}

class _PlayerIconButtonState extends State<PlayerIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    final Color iconColor = !enabled
        ? PlayerTheme.inkDisabled
        : widget.active
        ? (widget.activeColor ?? PlayerTheme.accent)
        : (_hovered ? PlayerTheme.ink : PlayerTheme.inkMuted);

    final Color fill =
        widget.backgroundColor ??
        (widget.active
            ? PlayerTheme.accentSoft
            : (_hovered ? PlayerTheme.surfaceHover : PlayerTheme.raised));

    final Color borderColor = widget.active
        ? PlayerTheme.accent.withValues(alpha: 0.55)
        : PlayerTheme.edgeSoft;

    final iconContent = Stack(
      alignment: Alignment.center,
      children: [
        IconTheme(
          data: IconThemeData(color: iconColor, size: widget.iconSize),
          child: widget.icon,
        ),
        if (widget.showActiveBadge)
          Positioned(
            top: widget.size * 0.18,
            right: widget.size * 0.18,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.badgeColor ?? PlayerTheme.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (widget.badgeColor ?? PlayerTheme.accent).withValues(
                      alpha: 0.8,
                    ),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    final buttonBody = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: fill,
        shape: widget.borderRadius >= widget.size / 2
            ? BoxShape.circle
            : BoxShape.rectangle,
        borderRadius: widget.borderRadius >= widget.size / 2
            ? null
            : BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: PlayerTheme.buttonShadow,
      ),
      child: iconContent,
    );

    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _hovered && enabled ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: buttonBody,
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: const Color(0xE6080C12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PlayerTheme.edgeSoft),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        child: button,
      );
    }

    return button;
  }
}

/// Rounded pill toggle chip for filters and options.
class PlayerToggleChip extends StatelessWidget {
  final bool active;
  final String label;
  final String? count;
  final VoidCallback onClick;
  final bool disabled;

  const PlayerToggleChip({
    super.key,
    required this.active,
    required this.label,
    this.count,
    required this.onClick,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onClick,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: disabled ? 0.35 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: active ? PlayerTheme.accentSoft : PlayerTheme.raised,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: active
                  ? PlayerTheme.accent.withValues(alpha: 0.55)
                  : PlayerTheme.edgeSoft,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? PlayerTheme.ink : PlayerTheme.inkMuted,
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 4),
                Text(
                  count!,
                  style: TextStyle(
                    color: active
                        ? PlayerTheme.ink.withValues(alpha: 0.75)
                        : PlayerTheme.inkSubtle,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
