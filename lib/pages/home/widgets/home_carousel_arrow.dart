import 'package:flutter/material.dart';

import '../../../design/dizzy_tokens.dart';
import '../../../services/theme/app_theme_service.dart';

class HomeCarouselArrow extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  const HomeCarouselArrow({
    super.key,
    required this.icon,
    required this.onTap,
    required this.label,
  });

  @override
  State<HomeCarouselArrow> createState() => HomeCarouselArrowState();
}

class HomeCarouselArrowState extends State<HomeCarouselArrow> {
  bool _isHoveringArrow = false;
  bool _isFocused = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.label);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlight = _isHoveringArrow || _isFocused;
    // Light needs a slightly stronger scrim over bright hero artwork; dark
    // keeps its pre-existing 0.60 / 0.30 scrim.
    final isLight = AppThemeService.currentPalette.value.isLight;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringArrow = true),
      onExit: (_) => setState(() => _isHoveringArrow = false),
      // Polish P13: DPAD/keyboard focusable with visible ring + Enter key.
      child: FocusableActionDetector(
        focusNode: _focusNode,
        onShowFocusHighlight: (v) => setState(() => _isFocused = v),
        actions: {
          ActivateIntent: CallbackAction(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: Semantics(
            button: true,
            focused: _isFocused,
            label: widget.label,
            child: AnimatedContainer(
              duration: DizzyMotion.fast,
              curve: DizzyMotion.easeOut,
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Over hero artwork: white glyphs need a dark scrim in both modes.
                color: highlight
                    ? Colors.black.withValues(alpha: isLight ? 0.62 : 0.60)
                    : Colors.black.withValues(alpha: isLight ? 0.42 : 0.30),
                border: Border.all(
                  color: _isFocused
                      ? Colors.white
                      : highlight
                      ? Colors.white.withValues(alpha: isLight ? 0.65 : 0.60)
                      : Colors.white.withValues(alpha: isLight ? 0.35 : 0.20),
                  width: _isFocused ? 2.5 : 1.5,
                ),
              ),
              child: Icon(
                widget.icon,
                color: highlight ? Colors.white : Colors.white70,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Slide — a single featured title within the carousel.
// ─────────────────────────────────────────────────────────────────────────────
