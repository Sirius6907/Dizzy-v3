import 'package:flutter/material.dart';

import 'watch_style.dart';

class WatchShimmerCard extends StatefulWidget {
  const WatchShimmerCard({super.key});

  @override
  State<WatchShimmerCard> createState() => WatchShimmerCardState();
}

class WatchShimmerCardState extends State<WatchShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: WatchColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
          ),
          child: Row(
            children: [
              _shimmerBox(40, 40, 10),
              const SizedBox(width: WatchSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(double.infinity, 12, 4),
                    const SizedBox(height: 8),
                    _shimmerBox(180, 10, 4),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _shimmerBox(40, 16, 4),
                        const SizedBox(width: 4),
                        _shimmerBox(50, 16, 4),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: WatchSpace.xs),
              _shimmerBox(36, 36, 18),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBox(double width, double height, double radius) {
    final shimmerValue = _controller.value;
    final gradientStart = shimmerValue - 0.3;
    final gradientEnd = shimmerValue + 0.3;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            WatchColors.surfaceLight.withValues(alpha: 0.5),
            WatchColors.surfaceLight.withValues(alpha: 0.8),
            WatchColors.surfaceLight.withValues(alpha: 0.5),
          ],
          stops: [
            (gradientStart).clamp(0.0, 1.0),
            (shimmerValue).clamp(0.0, 1.0),
            (gradientEnd).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }
}

