import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import '../common/liquid_dock.dart' show DockItem;

/// A high-performance, 120 FPS Neo-Skeuomorphic Tactile Dock.
/// Replaces heavy BackdropFilter/LiquidGlass shaders with pure-math physical depth.
class DizzyTactileDock extends StatefulWidget {
  final List<DockItem> items;
  final double baseItemSize;
  final double maxItemSize;
  final double maxWidth;
  final int selectedIndex;

  const DizzyTactileDock({
    super.key,
    required this.items,
    this.baseItemSize = 48,
    this.maxItemSize = 64,
    this.maxWidth = 580,
    this.selectedIndex = 0,
  });

  @override
  State<DizzyTactileDock> createState() => _DizzyTactileDockState();
}

class _DizzyTactileDockState extends State<DizzyTactileDock> {
  int? _pressedIndex;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          margin: const EdgeInsets.symmetric(
            horizontal: DizzySpace.md,
            vertical: DizzySpace.sm,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DizzySpace.md,
            vertical: DizzySpace.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [DizzyVoid.surface3, DizzyVoid.surface1],
            ),
            border: Border.fromBorderSide(DizzyEdge.hairline),
            boxShadow: DizzyShadow.dock,
          ),
          child: Stack(
            children: [
              // Top-edge light catch specular line
              Positioned(
                top: 0,
                left: 16,
                right: 16,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final isSelected = index == widget.selectedIndex;
                  final isPressed = _pressedIndex == index;

                  return GestureDetector(
                    onTapDown: (_) {
                      setState(() => _pressedIndex = index);
                      HapticFeedback.lightImpact();
                    },
                    onTapUp: (_) {
                      if (_pressedIndex == index) {
                        setState(() => _pressedIndex = null);
                      }
                    },
                    onTapCancel: () {
                      if (_pressedIndex == index) {
                        setState(() => _pressedIndex = null);
                      }
                    },
                    onTap: () {
                      HapticFeedback.selectionClick();
                      item.onTap();
                    },
                    child: AnimatedScale(
                      scale: isPressed ? 0.92 : 1.0,
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DizzySpace.sm,
                          vertical: DizzySpace.xs,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                // Active glow beacon
                                if (isSelected)
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: DizzyGlow.red.withValues(alpha: 0.16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: DizzyGlow.red.withValues(alpha: 0.35),
                                          blurRadius: 14,
                                        ),
                                      ],
                                    ),
                                  ),
                                Icon(
                                  item.icon,
                                  size: isSelected ? 26 : 22,
                                  color: isSelected
                                      ? DizzyVoid.bone
                                      : DizzyVoid.ash,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Active status dot or label
                            if (isSelected)
                              Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: DizzyGlow.red,
                                ),
                              )
                            else
                              const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
