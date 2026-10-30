import 'package:flutter/material.dart';

import 'player_glass.dart';

/// Secondary playback controls, collapsed out of the transport bar so the
/// main row keeps only the four actions people reach for constantly.
class PlayerMoreSheet extends StatelessWidget {
  final double playbackRate;
  final bool isQualityManual;
  final bool isSubSyncActive;

  final VoidCallback onToggleAspectMenu;
  final VoidCallback onToggleSpeedMenu;
  final VoidCallback onToggleQualityMenu;
  final VoidCallback onToggleSubSync;

  const PlayerMoreSheet({
    super.key,
    required this.playbackRate,
    required this.isQualityManual,
    required this.isSubSyncActive,
    required this.onToggleAspectMenu,
    required this.onToggleSpeedMenu,
    required this.onToggleQualityMenu,
    required this.onToggleSubSync,
  });

  String get _speedLabel {
    if (playbackRate == 1.0) return 'Normal';
    final text = playbackRate.toStringAsFixed(2);
    return '${text.endsWith('0') ? text.substring(0, text.length - 1) : text}×';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: PlayerTheme.elevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PlayerTheme.edge),
          boxShadow: PlayerTheme.menuShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: PlayerTheme.inkSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _PlayerMoreRow(
              icon: Icons.aspect_ratio_rounded,
              label: 'Aspect ratio',
              onTap: () => _fire(context, onToggleAspectMenu),
            ),
            _PlayerMoreRow(
              icon: Icons.speed_rounded,
              label: 'Playback speed',
              value: _speedLabel,
              highlighted: playbackRate != 1.0,
              onTap: () => _fire(context, onToggleSpeedMenu),
            ),
            _PlayerMoreRow(
              icon: Icons.high_quality_rounded,
              label: 'Quality',
              value: isQualityManual ? 'Manual' : 'Auto',
              highlighted: isQualityManual,
              onTap: () => _fire(context, onToggleQualityMenu),
            ),
            _PlayerMoreRow(
              icon: Icons.tune_rounded,
              label: 'Subtitle sync',
              value: isSubSyncActive ? 'Adjusted' : null,
              highlighted: isSubSyncActive,
              onTap: () => _fire(context, onToggleSubSync),
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  void _fire(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }
}

class _PlayerMoreRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool highlighted;
  final bool isLast;
  final VoidCallback onTap;

  const _PlayerMoreRow({
    required this.icon,
    required this.label,
    this.value,
    this.highlighted = false,
    this.isLast = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? PlayerTheme.accent : PlayerTheme.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: PlayerTheme.edgeSoft)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 21, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (value != null)
                Text(
                  value!,
                  style: TextStyle(
                    color: highlighted
                        ? PlayerTheme.accent
                        : PlayerTheme.inkMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: PlayerTheme.inkSubtle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
