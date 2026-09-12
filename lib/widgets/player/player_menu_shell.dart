import 'package:flutter/material.dart';

import '../../design/dizzy_tokens.dart';
import 'player_glass.dart';

/// Polish P4 — every player popover speaks in ONE voice:
/// same glass card, same CAPS title, same close button, same rhythm.
///
/// Quality / Speed / Aspect use this shell. Audio keeps its own header
/// (track-count badge + compact mode) and Subtitles keeps its multi-action
/// header — both already match this visual voice.
class PlayerMenuShell extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Widget child;

  /// Card width before clamping (shell clamps to screen).
  final double width;

  /// Optional widget after the title (e.g. a count badge).
  final Widget? titleTrailing;

  const PlayerMenuShell({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.width = 320,
    this.titleTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return PlayerGlassCard(
      width: width.clamp(DizzySpace.xxl * 5, screenWidth - DizzySpace.md * 2),
      padding: const EdgeInsets.all(DizzySpace.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DizzySpace.xs,
                      vertical: DizzySpace.xxs,
                    ),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: PlayerTheme.inkSubtle,
                        fontSize: DizzyType.captionSm,
                        fontWeight: DizzyType.wBold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if (titleTrailing != null) titleTrailing!,
                ],
              ),
              PlayerIconButton(
                size: 28,
                iconSize: 14,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: DizzySpace.xs - 2),
          child,
        ],
      ),
    );
  }
}
