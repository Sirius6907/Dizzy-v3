import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// P6 — desktop wheel wrapper: vertical mouse-wheel ko horizontal
/// rail scroll me badlo. Har horizontal rail pe lagao taaki desktop
/// pe wheel se rail chale (bina Shift dabaye).
class HorizontalWheelScroll extends StatelessWidget {
  final ScrollController controller;
  final Widget child;

  /// Wheel se kitna tez scroll ho (1.0 = normal, zyada = tez).
  final double speed;

  const HorizontalWheelScroll({
    super.key,
    required this.controller,
    required this.child,
    this.speed = 1.2,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent &&
            controller.hasClients) {
          final dy = pointerSignal.scrollDelta.dy;
          final dx = pointerSignal.scrollDelta.dx;
          final delta = dy != 0 ? dy : dx;
          if (delta != 0) {
            final target = (controller.offset + delta * speed)
                .clamp(0.0, controller.position.maxScrollExtent);
            controller.jumpTo(target);
          }
        }
      },
      child: child,
    );
  }
}
