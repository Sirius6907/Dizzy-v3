import 'package:flutter/material.dart';

import '../../design/dizzy_tactile.dart';
import '../../design/dizzy_tokens.dart';
import '../../services/stats/wrap_year.dart';
import '../../services/theme/app_theme_service.dart';
import '../../widgets/tactile/dizzy_tactile_card.dart';

/// F5 — the shareable card.
///
/// One screen, four numbers, one button. Everything a person reads is
/// [WrapShareCopy]'s wording, so the card and the shared sentence can never
/// tell two different stories about the same year.
///
/// The share goes out through the existing share sheet with a clipboard
/// fallback — a person who cannot share still sees the line on screen.
class WrapCard extends StatelessWidget {
  final YearlyWrap wrap;

  /// Fired when the person taps share. Returns the line that was shared, so
  /// the caller can decide how to confirm it.
  final Future<void> Function(String shareText) onShare;

  const WrapCard({
    super.key,
    required this.wrap,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final shareText = WrapShareCopy.shareText(wrap);

    return DizzyTactileCard(
      padding: const EdgeInsets.all(DizzySpace.md),
      borderColor: palette.primaryColor.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            WrapShareCopy.title(wrap),
            style: const TextStyle(
              color: DizzyVoid.bone,
              fontSize: DizzyType.subtitle,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: DizzySpace.xs),
          Text(
            WrapShareCopy.hoursLine(wrap),
            style: const TextStyle(
              color: DizzyVoid.ash,
              fontSize: DizzyType.body,
            ),
          ),
          const SizedBox(height: DizzySpace.md),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  value: wrap.titlesStarted.toString(),
                  label: 'Titles',
                ),
              ),
              const SizedBox(width: DizzySpace.xs),
              Expanded(
                child: _Tile(
                  value: '${wrap.longestStreakDays}d',
                  label: WrapShareCopy.streakLine(wrap),
                ),
              ),
            ],
          ),
          const SizedBox(height: DizzySpace.xs),
          Text(
            WrapShareCopy.topTypeLine(wrap),
            style: const TextStyle(
              color: DizzyVoid.ash,
              fontSize: DizzyType.caption,
            ),
          ),
          const SizedBox(height: DizzySpace.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => onShare(shareText),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text(
                'Share my wrap',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: DizzySpace.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: DizzyRadius.mdAll,
                ),
              ),
            ),
          ),
          // The exact line is on screen even when sharing fails, so nobody is
          // left wondering what they were about to send.
          const SizedBox(height: DizzySpace.xs),
          Text(
            shareText,
            style: TextStyle(
              color: DizzyVoid.ash.withValues(alpha: 0.8),
              fontSize: DizzyType.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String value;
  final String label;

  const _Tile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DizzySpace.sm),
      decoration: BoxDecoration(
        color: DizzyVoid.voidB,
        borderRadius: DizzyRadius.mdAll,
        border: Border.fromBorderSide(DizzyEdge.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: DizzyVoid.bone,
              fontSize: DizzyType.title,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: DizzyVoid.ash,
              fontSize: DizzyType.caption,
            ),
          ),
        ],
      ),
    );
  }
}
