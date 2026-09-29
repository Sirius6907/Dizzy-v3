import 'package:flutter/material.dart';

import '../../../services/theme/app_theme_service.dart';
import 'home_hover_arrow.dart';

class HomeScrollTrack extends StatefulWidget {
  final ScrollController controller;

  const HomeScrollTrack({super.key, required this.controller});

  @override
  State<HomeScrollTrack> createState() => HomeScrollTrackState();
}

class HomeScrollTrackState extends State<HomeScrollTrack> {
  double _thumbFraction = 0.0;
  bool _isHovering = false;
  bool _isDragging = false;
  final double _trackHeight = 300.0;
  final double _thumbHeight = 60.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateThumbFromScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateThumbFromScroll);
    super.dispose();
  }

  void _updateThumbFromScroll() {
    if (!widget.controller.hasClients || _isDragging) return;
    final max = widget.controller.position.maxScrollExtent;
    if (max <= 0) return;

    setState(() {
      _thumbFraction = (widget.controller.position.pixels / max).clamp(
        0.0,
        1.0,
      );
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.controller.hasClients) return;
    final max = widget.controller.position.maxScrollExtent;
    if (max <= 0) return;

    final usableTrack = _trackHeight - _thumbHeight;
    setState(() {
      _thumbFraction += details.delta.dy / usableTrack;
      _thumbFraction = _thumbFraction.clamp(0.0, 1.0);
    });

    widget.controller.jumpTo(_thumbFraction * max);
  }

  void _scroll(double direction) {
    if (!widget.controller.hasClients) return;
    final target = widget.controller.position.pixels + (direction * 400);
    widget.controller.animateTo(
      target.clamp(0.0, widget.controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbPosition = _thumbFraction * (_trackHeight - _thumbHeight);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedOpacity(
        opacity: _isHovering || _isDragging ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xF01A1D27),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HomeHoverArrow(
                icon: Icons.keyboard_arrow_up_rounded,
                onTap: () => _scroll(-1),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => setState(() => _isDragging = true),
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: (_) => setState(() => _isDragging = false),
                onVerticalDragCancel: () => setState(() => _isDragging = false),
                child: Container(
                  height: _trackHeight,
                  width: 24, // Wider hit area for easy grabbing
                  alignment: Alignment.center,
                  child: Container(
                    height: _trackHeight,
                    width: 6, // Visual track
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: thumbPosition,
                          left:
                              -2, // To make the thumb slightly wider than the track
                          right: -2,
                          child: Container(
                            height: _thumbHeight,
                            decoration: BoxDecoration(
                              color: AppThemeService
                                  .currentPalette
                                  .value
                                  .primaryColor,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: AppThemeService
                                      .currentPalette
                                      .value
                                      .primaryColor
                                      .withOpacity(0.6),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              HomeHoverArrow(
                icon: Icons.keyboard_arrow_down_rounded,
                onTap: () => _scroll(1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

