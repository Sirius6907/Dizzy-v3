import 'package:flutter/material.dart';

import '../../../design/dizzy_tokens.dart';
class HomeCarouselArrow extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  const HomeCarouselArrow(
      {super.key, required this.icon, required this.onTap, required this.label});

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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringArrow = true),
      onExit: (_) => setState(() => _isHoveringArrow = false),
      // Polish P13: DPAD/keyboard focusable with visible ring + Enter key.
      child: FocusableActionDetector(
        focusNode: _focusNode,
        onShowFocusHighlight: (v) => setState(() => _isFocused = v),
        actions: {ActivateIntent: CallbackAction(onInvoke: (_) {
          widget.onTap();
          return null;
        })},
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
            color: highlight
                ? Colors.black.withOpacity(0.6)
                : Colors.black.withOpacity(0.3),
            border: Border.all(
              color: _isFocused
                  ? Colors.white
                  : highlight
                      ? Colors.white.withOpacity(0.6)
                      : Colors.white.withOpacity(0.2),
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

