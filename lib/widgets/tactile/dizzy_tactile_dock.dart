import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import '../../services/music/music_player_controller.dart';
import '../common/dock_item.dart';

/// A high-performance, 120 FPS Neo-Skeuomorphic Tactile Dock.
/// Pure-math physical depth — no BackdropFilter / liquid-glass shaders.
///
/// v1.2.1 parity notes (bottom-navbar compare fix):
/// - Horizontal scroll + chevron arrows jab items narrow screen pe fit na
///   hon (v1.2.1 LiquidDock jaisa) — koi overflow stripes nahi, har tab
///   reachable.
/// - Tooltip har item pe (label), Music icon pe live pulse dot jab gaana
///   baj raha ho.
/// - Mobile pe compact sizing.
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
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (_scrollController.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildItem(int index, {required bool compact}) {
    final item = widget.items[index];
    final isSelected = index == widget.selectedIndex;
    final isPressed = _pressedIndex == index;

    return Tooltip(
      message: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
          HapticFeedback.mediumImpact();
          item.onTap();
        },
        child: AnimatedScale(
          scale: isPressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? DizzySpace.xs : DizzySpace.sm,
              vertical: DizzySpace.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
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
                      size: isSelected
                          ? (compact ? 24 : 26)
                          : (compact ? 20 : 22),
                      color: isSelected ? DizzyVoid.bone : DizzyVoid.ash,
                    ),
                    // Live music pulse dot (v1.2.1 parity)
                    if (item.label == 'Music')
                      Positioned(
                        right: -2,
                        top: -2,
                        child: ListenableBuilder(
                          listenable: MusicPlayerController.instance,
                          builder: (context, _) {
                            if (!MusicPlayerController.instance.isPlaying) {
                              return const SizedBox.shrink();
                            }
                            return Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: DizzyGlow.volt,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Active status dot or label spacer
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 600;
    // v1.2.1 jaisa available-width math — isse zyada items hon to
    // scroll + arrows, warna normal centered row. Overflow kabhi nahi.
    // NOTE: available me outer margin (32) already minus hai. Outer
    // Container ka apna horizontal padding (DizzySpace.md*2 = 32) + dono
    // chevron (30+30 = 60) bhi minus karna zaroori hai, warna Row parent
    // se ~24-26px bahar nikalta hai (narrow 400dp pe RIGHT OVERFLOWED).
    final available = math.min(widget.maxWidth, screenWidth - 32);
    const itemExtent = 58.0;
    const outerPadding = 32.0; // Container horizontal padding
    const arrowWidth = 60.0; // dono chevron 30+30
    const safety = 8.0;
    final contentWidth = widget.items.length * itemExtent + 32;
    final needsScrolling = contentWidth + outerPadding > available;
    final scrollAreaWidth = needsScrolling
        ? math.max(60.0, available - outerPadding - arrowWidth - safety)
        : contentWidth;

    Widget dockContent;
    if (!needsScrolling) {
      dockContent = Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          widget.items.length,
          (index) => _buildItem(index, compact: compact),
        ),
      );
    } else {
      dockContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: () => _scrollBy(-180),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: scrollAreaWidth),
            child: ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                scrollbars: false,
                overscroll: false,
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    widget.items.length,
                    (index) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildItem(index, compact: compact),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            height: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: () => _scrollBy(180),
            ),
          ),
        ],
      );
    }

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
              dockContent,
            ],
          ),
        ),
      ),
    );
  }
}
