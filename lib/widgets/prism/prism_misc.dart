import 'package:flutter/material.dart';

import '../../../design/prism_shadows.dart';
import '../../../design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';

/// Prism avatar — gradient ring, initials fallback (SPEC §3).
class PrismAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;

  const PrismAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final initials = name.trim().isEmpty
        ? 'D'
        : name
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [palette.primaryColor, palette.accentColor],
        ),
        boxShadow: PrismShadows.soft(isLight: palette.isLight),
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _fallback(initials, palette.primaryColor),
              )
            : _fallback(initials, palette.primaryColor),
      ),
    );
  }

  Widget _fallback(String initials, Color color) {
    return Container(
      alignment: Alignment.center,
      color: color,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: PrismType.wBold,
          fontSize: 14,
        ),
      ),
    );
  }
}

/// Prism badges — LIVE (pulsing dot), HD/4K, NEW, VIP (SPEC §3).
class PrismBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool pulse;

  const PrismBadge({
    super.key,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  factory PrismBadge.live({Key? key}) => PrismBadge(
    key: key,
    label: 'LIVE',
    color: PrismAccent.danger,
    pulse: true,
  );

  factory PrismBadge.hd({Key? key}) =>
      PrismBadge(key: key, label: 'HD', color: PrismAccent.success);

  factory PrismBadge.k4({Key? key}) =>
      PrismBadge(key: key, label: '4K', color: PrismAccent.warning);

  factory PrismBadge.neu({Key? key, required String label}) =>
      PrismBadge(key: key, label: label, color: PrismAccent.warning);

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    // Semantic color as a 15% tint under an 11px label measured 1.3–2.7:1.
    // Keep the color for identity — on the dot and the hairline — and paint
    // the label in `ink` on a neutral clay surface (9.2:1 light / 12.9:1 dark).
    final surface = isLight ? PrismLight.raisedTop : PrismDark.raisedTop;
    final ink = isLight ? PrismLight.ink : PrismDark.ink;
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulse) _PulseDot(color: color) else dot,
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: PrismType.wBold,
              letterSpacing: 0.8,
              color: ink,
            ),
          ),
        ],
      ),
    );
    return badge;
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
      _ctrl.value = 0.0;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.3).animate(_ctrl),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
      ),
    );
  }
}

/// Prism skeleton — clay block with slow sheen sweep 1.6s (SPEC §3).
class PrismSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const PrismSkeleton({super.key, this.width, this.height, this.borderRadius});

  @override
  State<PrismSkeleton> createState() => _PrismSkeletonState();
}

class _PrismSkeletonState extends State<PrismSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
      _ctrl.value = 0.5;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? PrismRadius.mdAll,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + _ctrl.value * 2, 0),
              end: Alignment(0.0 + _ctrl.value * 2, 0),
              colors: [
                (palette.isLight
                        ? PrismLight.raisedBottom
                        : PrismDark.raisedBottom)
                    .withValues(alpha: 0.6),
                (palette.isLight ? PrismLight.raisedTop : PrismDark.raisedTop)
                    .withValues(alpha: 0.9),
                (palette.isLight
                        ? PrismLight.raisedBottom
                        : PrismDark.raisedBottom)
                    .withValues(alpha: 0.6),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            boxShadow: PrismShadows.soft(isLight: palette.isLight),
          ),
        );
      },
    );
  }
}
