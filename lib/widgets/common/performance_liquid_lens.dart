import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../services/theme/glass_settings.dart';
import '../../utils/perf/performance_mode.dart';

/// Reusable styles keep the package render object from receiving a new
/// style identity and repainting when an unrelated parent rebuilds.
abstract final class PerformanceGlassStyles {
  static LiquidGlassStyle get dock => GlassSettings.createDockGlassStyle();
  static LiquidGlassStyle get sheet => GlassSettings.createSheetGlassStyle();
  static LiquidGlassStyle get menuButton => GlassSettings.createButtonGlassStyle();
  static LiquidGlassStyle get menu => GlassSettings.createSheetGlassStyle();
}

/// A deliberately constrained use of the package's real lens.
class PerformanceLiquidLens extends StatelessWidget {
  final LiquidGlassStyle? style;
  final Widget child;
  final bool visible;

  const PerformanceLiquidLens({
    super.key,
    this.style,
    required this.child,
    this.visible = true,
  });

  BoxDecoration get _fallbackDecoration {
    return BoxDecoration(
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xF0181A22), Color(0xF00E1015)],
      ),
      border: Border.all(
        color: const Color(0x1CE2E8F0),
        width: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSettings.enabled,
      child: child,
      builder: (context, enabled, cachedChild) {
        // P2: governor / Smooth Mode forces the cheap flat fallback —
        // a live backdrop-blur lens repaints every frame underneath.
        return ValueListenableBuilder<bool>(
          valueListenable: PerformanceMode.glassAllowed,
          builder: (context, perfGlass, __) {
            if (!enabled || !perfGlass) {
              return Container(
                clipBehavior: Clip.antiAlias,
                decoration: _fallbackDecoration,
                child: cachedChild,
              );
            }
            return ValueListenableBuilder<int>(
              valueListenable: GlassSettings.styleRevision,
              builder: (context, _, ___) {
                final effectiveStyle = style ?? PerformanceGlassStyles.dock;
                return RepaintBoundary(
                  child: LiquidGlassLens(
                    style: effectiveStyle,
                    visibility: visible,
                    useImpellerBackdrop: true,
                    child: cachedChild,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
