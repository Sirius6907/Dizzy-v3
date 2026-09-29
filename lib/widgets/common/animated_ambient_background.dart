import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/theme/app_theme_service.dart';
import '../../services/theme/custom_background_service.dart';
import '../../services/home/home_page_settings.dart';
import '../../utils/perf/image_caps.dart';
import '../../utils/perf/performance_mode.dart';

/// GPU-free ambient background using animated Container positions.
/// Zero shaders, zero BackdropFilter, zero CustomPaint — pure compositor
/// layers only. Respects user wallpaper ([CustomBackgroundService]),
/// ambient knobs ([HomePageSettings]), and the perf gate
/// ([PerformanceMode.ambientAllowed]).
class AnimatedAmbientBackground extends StatefulWidget {
  final Widget? child;

  const AnimatedAmbientBackground({
    super.key,
    this.child,
  });

  @override
  State<AnimatedAmbientBackground> createState() =>
      _AnimatedAmbientBackgroundState();
}

class _AnimatedAmbientBackgroundState extends State<AnimatedAmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    HomePageSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    CustomBackgroundService.notifier.addListener(_onSettingsChanged);
    PerformanceMode.ambientAllowed.addListener(_onPerfChanged);
    _applyPerfGate();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _applyPerfGate();
  }

  void _onPerfChanged() {
    if (!mounted) return;
    _applyPerfGate();
    setState(() {});
  }

  /// Runs the ticker only while animated lights are actually visible.
  /// Static wallpaper / plain scaffold needs no per-frame ticks.
  void _applyPerfGate() {
    final customBg = CustomBackgroundService.current;
    final showLights = HomePageSettings.enableAmbientLights.value &&
        PerformanceMode.ambientAllowed.value &&
        (!customBg.hasCustomBackground || customBg.blendThemeLights);
    if (showLights) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  /// Wallpaper layer (no blur shader — opacity + theme tint only).
  /// Decode-capped so fullscreen art never blows the RAM budget.
  Widget _buildWallpaper(CustomBackgroundData customBg) {
    Widget imageWidget;
    if (customBg.imagePath != null && customBg.imagePath!.isNotEmpty) {
      imageWidget = Image.file(
        File(customBg.imagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else if (customBg.imageUrl != null && customBg.imageUrl!.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: customBg.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: ImageCaps.kBackdrop,
        maxWidthDiskCache: ImageCaps.kBackdrop,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: customBg.opacity, child: imageWidget),
        // Theme tint so text stays readable over bright photos.
        Container(
          color: AppThemeService.currentPalette.value.scaffoldBackgroundColor
              .withValues(alpha: customBg.themeTintOpacity),
        ),
      ],
    );
  }

  @override
  void dispose() {
    HomePageSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    CustomBackgroundService.notifier.removeListener(_onSettingsChanged);
    PerformanceMode.ambientAllowed.removeListener(_onPerfChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        return ValueListenableBuilder<CustomBackgroundData>(
          valueListenable: CustomBackgroundService.notifier,
          builder: (context, customBg, _) {
            final hasWallpaper = customBg.hasCustomBackground;
            return ValueListenableBuilder<bool>(
              valueListenable: PerformanceMode.ambientAllowed,
              builder: (context, perfAllowed, _) {
                final showLights = HomePageSettings
                        .enableAmbientLights.value &&
                    perfAllowed &&
                    (!hasWallpaper || customBg.blendThemeLights);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: palette.scaffoldBackgroundColor),
                    if (hasWallpaper)
                      Positioned.fill(child: _buildWallpaper(customBg)),
                    // AnimatedBuilder repaints orbs every tick; when the
                    // perf gate closes the whole subtree unmounts (zero cost).
                    if (showLights)
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) {
                            final speed = HomePageSettings
                                .ambientLightSpeed.value;
                            final intensity = HomePageSettings
                                .ambientLightIntensity.value;
                            final pattern = HomePageSettings
                                .ambientLightPattern.value;
                            final t = (_controller.value * speed) % 1.0;
                            return _LightOrbs(
                              t: t,
                              palette: palette,
                              pattern: pattern,
                              intensity: intensity,
                            );
                          },
                        ),
                      ),
                    if (widget.child != null) widget.child!,
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Two drifting radial-glow orbs positioned per user pattern.
/// Pure Container + LinearGradient — no canvas shaders, no blur filters.
class _LightOrbs extends StatelessWidget {
  final double t;
  final AppThemePalette palette;
  final AmbientLightPattern pattern;
  final double intensity;

  const _LightOrbs({
    required this.t,
    required this.palette,
    required this.pattern,
    required this.intensity,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final a = t * 2 * math.pi;
    // Pattern controls drift path; intensity scales glow alpha.
    double x1, y1, x2, y2, s1, s2;
    switch (pattern) {
      case AmbientLightPattern.topAurora:
        x1 = 0.35 + 0.15 * math.sin(a);
        y1 = 0.08 + 0.06 * math.cos(a * 1.3);
        x2 = 0.72 - 0.12 * math.cos(a * 0.9);
        y2 = 0.14 + 0.08 * math.sin(a * 0.7);
        s1 = 0.65;
        s2 = 0.60;
        break;
      case AmbientLightPattern.fullMesh:
        x1 = 0.30 + 0.20 * math.sin(a);
        y1 = 0.40 + 0.12 * math.cos(a * 0.7);
        x2 = 0.70 - 0.20 * math.cos(a * 0.8);
        y2 = 0.50 + 0.12 * math.sin(a);
        s1 = 0.70;
        s2 = 0.70;
        break;
      case AmbientLightPattern.centerPulse:
        final pulse = 0.85 + 0.15 * math.sin(a);
        x1 = 0.50 - 0.275 * pulse;
        y1 = 0.38 - 0.275 * pulse;
        x2 = 0.50 - 0.25 * pulse + 0.05 * math.sin(a * 0.5);
        y2 = 0.42 - 0.25 * pulse;
        s1 = 0.55 * pulse;
        s2 = 0.50 * pulse;
        break;
      case AmbientLightPattern.dualOrbs:
        x1 = 0.22 + 0.12 * math.sin(a) - 0.275;
        y1 = 0.18 + 0.10 * math.cos(a * 0.8) - 0.275;
        x2 = 0.80 - 0.14 * math.cos(a * 0.9) - 0.25;
        y2 = 0.70 + 0.12 * math.sin(a * 0.7) - 0.25;
        s1 = 0.55;
        s2 = 0.50;
        break;
    }
    final primaryAlpha = (0.08 + intensity * 0.35).clamp(0.0, 0.5);
    final accentAlpha = (0.06 + intensity * 0.30).clamp(0.0, 0.45);
    return Stack(
      children: [
        Positioned(
          left: size.width * x1,
          top: size.height * y1,
          child: Container(
            width: size.width * s1,
            height: size.height * s1,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.center,
                colors: [
                  palette.primaryColor.withValues(alpha: primaryAlpha),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          left: size.width * x2,
          top: size.height * y2,
          child: Container(
            width: size.width * s2,
            height: size.height * s2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.center,
                colors: [
                  palette.accentColor.withValues(alpha: accentAlpha),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
