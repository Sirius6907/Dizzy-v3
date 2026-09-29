import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';

import '../../services/theme/glass_settings.dart';
import '../../utils/perf/performance_mode.dart';

/// Styles kept for API compatibility — always resolves to tactile fallback.
/// No liquid_glass_easy GPU shaders.
abstract final class PerformanceGlassStyles {
  static const Map<String, dynamic> dock = {};
  static const Map<String, dynamic> sheet = {};
  static const Map<String, dynamic> menuButton = {};
  static const Map<String, dynamic> menu = {};
}

/// Tactile fallback lens — zero GPU shader overhead.
/// Always uses BoxDecoration + LinearGradient + static borders.
class PerformanceLiquidLens extends StatelessWidget {
  final Object? style; // Preserved for API compatibility, always ignored.
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
        colors: [Color(0xFF181A22), DizzyVoid.voidB],
      ),
      border: Border.all(
        color: const Color(0x1CE2E8F0),
        width: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSettings.enabled,
      child: child,
      builder: (context, enabled, cachedChild) {
        return ValueListenableBuilder<bool>(
          valueListenable: PerformanceMode.glassAllowed,
          builder: (context, perfGlass, __) {
            // Always use tactile fallback — no liquid_glass_easy shaders.
            // PerformanceMode.glassAllowed controls whether ambient GPU
            // effects are allowed; the fallback is static (zero cost).
            return Container(
              clipBehavior: Clip.antiAlias,
              decoration: _fallbackDecoration,
              child: cachedChild,
            );
          },
        );
      },
    );
  }
}
