import 'package:flutter/material.dart';

import '../../../design/prism_tokens.dart';
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
    final palette = AppThemeService.currentPalette.value;
    final primaryColor = palette.primaryColor;

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
            color: palette.isLight
                ? PrismLight.raisedTop.withValues(
                    alpha: _isHovering ? 1.0 : 0.7,
                  )
                : Colors.white.withValues(alpha: _isHovering ? 0.15 : 0.05),
            border: Border.all(
              color: palette.isLight
                  ? PrismLight.borderSubtle
                  : Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Icon(
            widget.icon,
            color: palette.isLight
                ? (_isHovering ? PrismLight.ink : PrismLight.inkSoft)
                : (_isHovering ? primaryColor : Colors.white70),
            size: 22,
          ),
        ),
      ),
    );
  }
}
