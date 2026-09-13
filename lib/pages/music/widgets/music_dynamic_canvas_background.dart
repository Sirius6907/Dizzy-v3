import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_artwork_palette_service.dart';
import '../../../utils/perf/performance_mode.dart';

class MusicDynamicCanvasBackground extends StatefulWidget {
  final MusicTrack track;
  final Widget? child;

  const MusicDynamicCanvasBackground({
    super.key,
    required this.track,
    this.child,
  });

  @override
  State<MusicDynamicCanvasBackground> createState() => _MusicDynamicCanvasBackgroundState();
}

class _MusicDynamicCanvasBackgroundState extends State<MusicDynamicCanvasBackground>
    with SingleTickerProviderStateMixin {
  late MusicTrackPalette _palette;
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _palette = MusicArtworkPaletteService.instance.getFastPalette(widget.track);
    _loadRealPalette();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    if (PerformanceMode.ambientAllowed.value) {
      _animController.repeat(reverse: true);
    }

    PerformanceMode.ambientAllowed.addListener(_onPerfChanged);
  }

  void _onPerfChanged() {
    if (!mounted) return;
    if (PerformanceMode.ambientAllowed.value) {
      if (!_animController.isAnimating) _animController.repeat(reverse: true);
    } else {
      _animController.stop();
    }
  }

  Future<void> _loadRealPalette() async {
    final real = await MusicArtworkPaletteService.instance.extractPalette(widget.track);
    if (mounted) {
      setState(() {
        _palette = real;
      });
    }
  }

  @override
  void didUpdateWidget(covariant MusicDynamicCanvasBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _palette = MusicArtworkPaletteService.instance.getFastPalette(widget.track);
      _loadRealPalette();
    }
  }

  @override
  void dispose() {
    PerformanceMode.ambientAllowed.removeListener(_onPerfChanged);
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        final t = _animController.value;
        final shiftX = math.sin(t * math.pi) * 0.15;
        final shiftY = math.cos(t * math.pi) * 0.15;

        return TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          tween: ColorTween(begin: _palette.primary, end: _palette.primary),
          builder: (context, primaryColor, _) {
            final primary = primaryColor ?? _palette.primary;
            final secondary = _palette.secondary;
            final bg = _palette.background;

            return DecoratedBox(
              decoration: BoxDecoration(
                color: bg,
                gradient: RadialGradient(
                  center: Alignment(-0.6 + shiftX, -0.6 + shiftY),
                  radius: 1.35,
                  colors: [
                    primary.withValues(alpha: 0.38),
                    secondary.withValues(alpha: 0.18),
                    bg.withValues(alpha: 0.95),
                    const Color(0xFF07090F),
                  ],
                  stops: const [0.0, 0.45, 0.80, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  // Floating secondary glow at bottom-right
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0.7 - shiftX, 0.7 - shiftY),
                          radius: 1.1,
                          colors: [
                            secondary.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.7],
                        ),
                      ),
                    ),
                  ),

                  // Soft dark vignette overlay for crisp contrast
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),

                  if (widget.child != null) widget.child!,
                ],
              ),
            );
          },
        );
      },
    );
  }
}
