import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Chrome ramp shared by the wordmark, the halo and the sign-off rule.
///
/// Cool greys with a blown-out specular band in the middle: the "metal catches
/// the light" look, done with a gradient instead of an image so it costs
/// nothing at runtime and scales to any resolution.
const List<Color> _chromeColors = <Color>[
  Color(0xFF59606D),
  Color(0xFFC7D1E2),
  Color(0xFFFFFFFF),
  Color(0xFF8A94A5),
  Color(0xFFF8FBFF),
  Color(0xFF444B58),
];

const List<double> _chromeStops = <double>[0.0, 0.20, 0.38, 0.58, 0.78, 1.0];

/// Eased 0→1 ramp for one slice of the master timeline.
///
/// `t` is the controller value, `begin`/`end` are normalised times. Everything
/// in the intro is expressed this way so the whole sequence can be retimed by
/// editing numbers, never by rewriting animation code.
double _seg(
  double t,
  double begin,
  double end, {
  Curve curve = Curves.easeOutCubic,
}) {
  if (t <= begin) return 0;
  if (t >= end) return 1;
  return curve.transform((t - begin) / (end - begin));
}

/// Mounts the brand moment above every route, once per process launch.
///
/// The child is built and laid out immediately — the intro is an overlay, not a
/// gate — so a slow first frame can never be mistaken for a hung boot. A tap
/// anywhere dismisses it, and it never replays for the life of the process
/// (a theme change or a hot reload must not re-run it, a cold start must).
class BrandIntroHost extends StatefulWidget {
  const BrandIntroHost({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<BrandIntroHost> createState() => _BrandIntroHostState();
}

class _BrandIntroHostState extends State<BrandIntroHost> {
  static bool _playedThisLaunch = false;

  late bool _visible;

  @override
  void initState() {
    super.initState();
    _visible = widget.enabled && !_playedThisLaunch;
    if (_visible) _playedThisLaunch = true;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (_visible)
          DizzyBrandIntro(
            onFinished: () {
              if (mounted) setState(() => _visible = false);
            },
          ),
      ],
    );
  }
}

/// The Dizzy cold-start signature.
///
/// Beat sheet (full motion, ~3.1s):
///   0.00–0.45  black lifts into an accent bloom
///   0.02–0.34  a chrome halo draws itself around the wordmark
///   0.10–0.46  letters converge out of a blur, each one a beat later
///   0.20–0.74  a specular band sweeps across the chrome
///   0.36–0.54  a hairline rule opens from the centre
///   0.46–0.66  the tagline tracks in
///   0.56–0.78  the bottom sign-off lands
///   0.84–1.00  the whole frame lifts, softens and clears
///
/// Reduced motion collapses this to a single 620ms fade with no blur or travel.
class DizzyBrandIntro extends StatefulWidget {
  const DizzyBrandIntro({
    super.key,
    required this.onFinished,
    this.accent,
    this.signOffLabel = 'BY SIRIUS',
  });

  final VoidCallback onFinished;

  /// Falls back to the brand red when the theme palette is unavailable.
  final Color? accent;

  final String signOffLabel;

  @override
  State<DizzyBrandIntro> createState() => _DizzyBrandIntroState();
}

class _DizzyBrandIntroState extends State<DizzyBrandIntro>
    with SingleTickerProviderStateMixin {
  static const Duration _fullDuration = Duration(milliseconds: 3150);
  static const Duration _reducedDuration = Duration(milliseconds: 620);

  late final AnimationController _controller;
  bool _started = false;
  bool _reducedMotion = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _fullDuration)
      ..addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final data = MediaQuery.maybeOf(context);
    _reducedMotion = (data?.disableAnimations ?? false) ||
        (data?.accessibleNavigation ?? false);
    _controller.duration = _reducedMotion ? _reducedDuration : _fullDuration;
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  void _skip() {
    if (_finished) return;
    _controller.animateTo(
      1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? const Color(0xFFFF4D4D);
    return Semantics(
      label: 'Dizzy. One app. Everything.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _buildFrame(accent, _controller.value),
        ),
      ),
    );
  }

  Widget _buildFrame(Color accent, double t) {
    final bloom = _seg(t, 0.0, 0.45);
    final halo = _seg(t, 0.02, 0.34);
    final rise = _seg(t, 0.10, 0.46, curve: Curves.easeOutQuint);
    final sweep = _seg(t, 0.20, 0.74, curve: Curves.easeInOutCubic);
    final rule = _seg(t, 0.36, 0.54);
    final tagline = _seg(t, 0.46, 0.66);
    final signOff = _seg(t, 0.56, 0.78);
    final exit = _seg(t, 0.84, 1.0, curve: Curves.easeInCubic);

    final contentOpacity = (1 - exit).clamp(0.0, 1.0);
    final blurSigma = _reducedMotion
        ? 0.0
        : (14 * (1 - rise) + 10 * exit);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 420.0;
        final wordSize = math.min(width * 0.235, 150.0);
        final haloSize = math.min(width * 0.92, wordSize * 3.4);

        return ColoredBox(
          color: const Color(0xFF04050A),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Accent bloom: the room lights coming up.
              Opacity(
                opacity: (bloom * contentOpacity).clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.12),
                      radius: 0.85,
                      colors: <Color>[
                        accent.withValues(alpha: 0.22),
                        accent.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                      stops: const <double>[0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              // Vignette keeps the edges from feeling flat.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.05),
                    radius: 1.25,
                    colors: <Color>[Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
              ),
              Opacity(
                opacity: contentOpacity,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Center(
                      child: Transform.scale(
                        scale: 1 + 0.05 * exit,
                        // Halo and type share one centre: the ring is the
                        // backdrop, the lockup sits inside it.
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            SizedBox.square(
                              dimension: haloSize,
                              child: CustomPaint(
                                painter: _HaloPainter(
                                  progress: halo,
                                  diameter: haloSize,
                                  rotation: -math.pi / 2 + 0.28 * sweep,
                                  opacity: 0.9,
                                  tint: accent,
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                _buildWordmark(
                                  t: t,
                                  size: wordSize,
                                  rise: rise,
                                  sweep: sweep,
                                  blur: blurSigma,
                                ),
                                SizedBox(height: wordSize * 0.24),
                                _buildRule(rule, accent),
                                SizedBox(height: wordSize * 0.16),
                                Opacity(
                                  opacity: tagline.clamp(0.0, 1.0),
                                  child: Text(
                                    'ONE APP · EVERYTHING',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 3.4 + 7.0 * (1 - tagline),
                                      color: Colors.white.withValues(
                                        alpha: 0.62,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 44,
                      child: DizzyBrandSignOff(
                        progress: signOff,
                        label: widget.signOffLabel,
                        accent: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWordmark({
    required double t,
    required double size,
    required double rise,
    required double sweep,
    required double blur,
  }) {
    const letters = <String>['D', 'i', 'z', 'z', 'y'];
    final style = TextStyle(
      fontSize: size,
      height: 1.0,
      fontWeight: FontWeight.w200,
      fontStyle: FontStyle.italic,
      color: Colors.white,
      letterSpacing: 0,
    );

    // Tracking pulls in as the letters land: 0.10em → 0.014em.
    final gap = size * (0.10 - 0.086 * rise);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        for (var i = 0; i < letters.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: gap),
          Builder(
            builder: (context) {
              final p = _seg(
                t,
                0.10 + i * 0.03,
                0.36 + i * 0.03,
                curve: Curves.easeOutQuint,
              );
              return Transform.translate(
                offset: Offset(0, (1 - p) * size * 0.26),
                child: Opacity(
                  opacity: p.clamp(0.0, 1.0),
                  child: Text(letters[i], style: style),
                ),
              );
            },
          ),
        ],
      ],
    );

    final masked = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _chromeColors,
        stops: _chromeStops,
        transform: _SweepTransform(sweep),
      ).createShader(bounds),
      child: row,
    );

    final softened = blur <= 0.15
        ? masked
        : ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: masked,
          );

    return Opacity(
      opacity: rise.clamp(0.0, 1.0),
      child: softened,
    );
  }

  Widget _buildRule(double p, Color accent) {
    return SizedBox(
      height: 2,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 126 * p,
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.55),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Container(
            width: 34 * p,
            height: 1.6,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  accent.withValues(alpha: 0),
                  accent,
                  accent.withValues(alpha: 0),
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-anchored brand sign-off: rule — label — rule.
///
/// Public because the intro is not the only place the brand should sign off;
/// onboarding and the "about" sheet can reuse it with their own progress value.
class DizzyBrandSignOff extends StatelessWidget {
  const DizzyBrandSignOff({
    super.key,
    this.progress = 1,
    this.label = 'BY SIRIUS',
    this.accent,
  });

  final double progress;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return const SizedBox.shrink();
    final tint = accent ?? const Color(0xFFFF4D4D);

    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - p)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _hair(p, tint),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 3.2,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
            const SizedBox(width: 12),
            _hair(p, tint),
          ],
        ),
      ),
    );
  }

  Widget _hair(double p, Color tint) {
    return Container(
      width: 26 * p,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.transparent,
            tint.withValues(alpha: 0.45),
          ],
        ),
      ),
    );
  }
}

/// Slides the chrome ramp across the glyphs, so the specular band travels
/// instead of the whole gradient flashing at once.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.t);

  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (t * 1.6 - 0.8), 0, 0);
  }
}

/// A single hairline ring that draws itself, then drifts as the chrome sweeps.
class _HaloPainter extends CustomPainter {
  const _HaloPainter({
    required this.progress,
    required this.diameter,
    required this.rotation,
    required this.opacity,
    required this.tint,
  });

  final double progress;
  final double diameter;
  final double rotation;
  final double opacity;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || opacity <= 0) return;

    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: diameter,
      height: diameter,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: <Color>[
          tint.withValues(alpha: 0.04 * opacity),
          Colors.white.withValues(alpha: 0.42 * opacity),
          tint.withValues(alpha: 0.10 * opacity),
          Colors.white.withValues(alpha: 0.28 * opacity),
          tint.withValues(alpha: 0.04 * opacity),
        ],
        stops: const <double>[0.0, 0.25, 0.5, 0.75, 1.0],
        transform: GradientRotation(rotation),
      ).createShader(rect);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.progress != progress ||
      old.diameter != diameter ||
      old.rotation != rotation ||
      old.opacity != opacity ||
      old.tint != tint;
}
