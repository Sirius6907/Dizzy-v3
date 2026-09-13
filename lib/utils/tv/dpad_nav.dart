import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// UX9 — D-Pad / TV / gamepad + desktop keyboard navigation.
///
/// - Wraps any screen: arrow keys + Enter move focus visibly.
/// - Glowing focus ring so TV users always SEE where they are.
/// - Desktop shortcuts: Space play/pause, M mute, F fullscreen, J/L seek.
class DpadNavScope extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPlayPause;
  final VoidCallback? onMute;
  final VoidCallback? onFullscreen;
  final VoidCallback? onSeekBack;
  final VoidCallback? onSeekForward;

  const DpadNavScope({
    super.key,
    required this.child,
    this.onPlayPause,
    this.onMute,
    this.onFullscreen,
    this.onSeekBack,
    this.onSeekForward,
  });

  static bool isSelectKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.gameButtonA;

  static bool isArrowKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.keyM) {
          onMute?.call();
          return onMute == null
              ? KeyEventResult.ignored
              : KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyF) {
          onFullscreen?.call();
          return onFullscreen == null
              ? KeyEventResult.ignored
              : KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyJ) {
          onSeekBack?.call();
          return onSeekBack == null
              ? KeyEventResult.ignored
              : KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyL) {
          onSeekForward?.call();
          return onSeekForward == null
              ? KeyEventResult.ignored
              : KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.space) {
          onPlayPause?.call();
          return onPlayPause == null
              ? KeyEventResult.ignored
              : KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// UX9 — glowing focus border for TV/gamepad users.
class DpadFocusRing extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;

  const DpadFocusRing({super.key, required this.child, this.onSelect});

  @override
  State<DpadFocusRing> createState() => _DpadFocusRingState();
}

class _DpadFocusRingState extends State<DpadFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter):
            ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter):
            ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA):
            ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect?.call();
            return null;
          },
        ),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused
                ? const Color(0xFF00E5FF)
                : Colors.transparent,
            width: _focused ? 2.5 : 1.5,
          ),
          boxShadow: _focused
              ? [
                  const BoxShadow(
                    color: Color(0x5500E5FF),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
