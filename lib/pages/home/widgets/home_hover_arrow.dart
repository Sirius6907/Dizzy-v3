import 'package:flutter/material.dart';

import '../../../services/theme/app_theme_service.dart';

class HomeHoverArrow extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const HomeHoverArrow({super.key, required this.icon, required this.onTap});

  @override
  State<HomeHoverArrow> createState() => HomeHoverArrowState();
}

class HomeHoverArrowState extends State<HomeHoverArrow> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppThemeService.currentPalette.value.primaryColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isHovering
                ? Colors.white.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: Icon(
            widget.icon,
            color: _isHovering ? primaryColor : Colors.white70,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home loading skeleton (Polish P2) — cold open pe khaali spinner ki jagah
// hero + rows ka shimmer shape. Fail-soft: data aate hi real list replace.
// ─────────────────────────────────────────────────────────────────────────────

