// Player lock mode — when locked, all touch/gesture/pointer input on the
// video area is swallowed; only the unlock button responds. Prevents
// accidental taps (pocket play, kids mode, bed watching).

import 'dart:async';

import 'package:flutter/material.dart';

/// Player lock button — pure Material, no theme-service dependency.

class PlayerLockButton extends StatefulWidget {
  final bool isLocked;
  final VoidCallback onToggle;

  const PlayerLockButton({
    super.key,
    required this.isLocked,
    required this.onToggle,
  });

  @override
  State<PlayerLockButton> createState() => _PlayerLockButtonState();
}

class _PlayerLockButtonState extends State<PlayerLockButton> {
  bool _confirming = false;
  Timer? _confirmTimer;

  void _tap() {
    if (widget.isLocked) {
      // When locked: first tap arms the unlock button for 3s,
      // second tap within that window unlocks.
      if (_confirming) {
        _confirmTimer?.cancel();
        _confirming = false;
        widget.onToggle();
      } else {
        _confirming = true;
        _confirmTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _confirming = false);
        });
      }
      setState(() {});
    } else {
      widget.onToggle();
    }
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final armed = widget.isLocked && _confirming;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: armed
            ? Colors.redAccent.withValues(alpha: 0.35)
            : Colors.black.withValues(alpha: 0.35),
        border: Border.all(
          color: armed ? Colors.redAccent : Colors.white.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Tooltip(
        message: widget.isLocked
            ? (armed ? 'Tap again to unlock' : 'Locked')
            : 'Lock player',
        child: InkWell(
          onTap: _tap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              widget.isLocked
                  ? (armed ? Icons.lock_open_rounded : Icons.lock_rounded)
                  : Icons.lock_outline_rounded,
              color: armed ? Colors.white : Colors.white.withValues(alpha: 0.85),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
