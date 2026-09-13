import 'dart:math';
import 'package:flutter/material.dart';

class MusicAudioVisualizer extends StatefulWidget {
  final bool isPlaying;
  final int barCount;
  final double height;
  final Color? color;
  final Gradient? gradient;

  const MusicAudioVisualizer({
    super.key,
    required this.isPlaying,
    this.barCount = 28,
    this.height = 42,
    this.color,
    this.gradient,
  });

  @override
  State<MusicAudioVisualizer> createState() => _MusicAudioVisualizerState();
}

class _MusicAudioVisualizerState extends State<MusicAudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  late List<double> _targetHeights;
  late List<double> _currentHeights;

  @override
  void initState() {
    super.initState();
    _targetHeights = List.generate(widget.barCount, (_) => 0.15);
    _currentHeights = List.generate(widget.barCount, (_) => 0.15);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    )..addListener(_updateHeights);

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MusicAudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        for (int i = 0; i < widget.barCount; i++) {
          _currentHeights[i] = 0.12;
        }
      });
    }
  }

  void _updateHeights() {
    if (!mounted || !widget.isPlaying) return;
    setState(() {
      for (int i = 0; i < widget.barCount; i++) {
        if (_controller.value > 0.8) {
          // Bell curve weighting in center
          final center = widget.barCount / 2;
          final distFromCenter = (i - center).abs() / center;
          final weight = 1.0 - (distFromCenter * 0.45);
          _targetHeights[i] = (_random.nextDouble() * 0.85 + 0.15) * weight;
        }
        // Smooth interpolation
        _currentHeights[i] += (_targetHeights[i] - _currentHeights[i]) * 0.35;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        painter: _VisualizerPainter(
          heights: _currentHeights,
          color: widget.color ?? const Color(0xFF7C5CFF),
          gradient: widget.gradient,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final List<double> heights;
  final Color color;
  final Gradient? gradient;

  _VisualizerPainter({
    required this.heights,
    required this.color,
    this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (heights.isEmpty) return;

    final barWidth = (size.width / heights.length) * 0.65;
    final spacing = (size.width - (barWidth * heights.length)) / (heights.length + 1);

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < heights.length; i++) {
      final x = spacing + i * (barWidth + spacing);
      final barH = (heights[i] * size.height).clamp(3.0, size.height);
      final y = size.height - barH;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barH),
        const Radius.circular(3),
      );

      if (gradient != null) {
        paint.shader = gradient!.createShader(Rect.fromLTWH(x, y, barWidth, barH));
      } else {
        paint.color = color;
      }

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) => true;
}
