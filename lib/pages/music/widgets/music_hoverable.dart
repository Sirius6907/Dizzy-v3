import 'package:flutter/material.dart';

class MusicHoverable extends StatefulWidget {
  final Widget child;
  final double scaleFactor;

  const MusicHoverable({
    super.key,
    required this.child,
    this.scaleFactor = 1.04,
  });

  @override
  State<MusicHoverable> createState() => _MusicHoverableState();
}

class _MusicHoverableState extends State<MusicHoverable> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? widget.scaleFactor : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
