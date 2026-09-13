import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../services/music/music_service.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';

class MusicQualityBadge extends StatelessWidget {
  final bool interactive;
  final double fontSize;
  final EdgeInsets padding;

  const MusicQualityBadge({
    super.key,
    this.interactive = true,
    this.fontSize = 10.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  });

  static void showQualitySelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MusicQualitySelectorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayerController.instance;
    final isLossless = controller.isCurrentTrackLossless;
    final label = controller.currentQualityLabel;

    final badge = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isLossless
            ? const Color(0xFFFFB300).withValues(alpha: 0.15)
            : const Color(0xFF7C5CFF).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLossless
              ? const Color(0xFFFFB300).withValues(alpha: 0.6)
              : const Color(0xFF7C5CFF).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLossless ? Icons.album_rounded : Icons.graphic_eq_rounded,
            size: fontSize + 2,
            color: isLossless ? const Color(0xFFFFB300) : const Color(0xFFB57CFF),
          ),
          const SizedBox(width: 4),
          Text(
            isLossless ? 'LOSSLESS' : 'HQ AUDIO',
            style: TextStyle(
              color: isLossless ? const Color(0xFFFFD54F) : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: fontSize,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );

    if (!interactive) return badge;

    return Tooltip(
      message: 'Audio Quality: $label (Tap to change)',
      child: MusicHoverable(
        scaleFactor: 1.06,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            showQualitySelector(context);
          },
          borderRadius: BorderRadius.circular(8),
          child: badge,
        ),
      ),
    );
  }
}

class _MusicQualitySelectorSheet extends StatefulWidget {
  const _MusicQualitySelectorSheet();

  @override
  State<_MusicQualitySelectorSheet> createState() => _MusicQualitySelectorSheetState();
}

class _MusicQualitySelectorSheetState extends State<_MusicQualitySelectorSheet> {
  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayerController.instance;
    final activeSource = controller.audioSource;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F121C).withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.high_quality_rounded, color: Color(0xFF00D2EF), size: 22),
                SizedBox(width: 10),
                Text(
                  'Streaming Audio Quality',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Option 1: FLAC Hi-Res Lossless
            _buildQualityTile(
              title: 'FLAC Hi-Res Lossless',
              subtitle: 'Studio Master quality (up to 24-bit / 192kHz). Bit-perfect audio.',
              icon: Icons.album_rounded,
              accentColor: const Color(0xFFFFB300),
              badgeText: 'HI-RES',
              isSelected: activeSource == MusicAudioSource.flac,
              onTap: () {
                HapticFeedback.mediumImpact();
                controller.setAudioSource(MusicAudioSource.flac);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 10),

            // Option 2: High Quality Stereo
            _buildQualityTile(
              title: 'YouTube HQ Audio (320 kbps)',
              subtitle: 'Optimized high bitrate stereo. Instant stream buffering & rich bass.',
              icon: Icons.graphic_eq_rounded,
              accentColor: const Color(0xFF7C5CFF),
              badgeText: 'HQ 320K',
              isSelected: activeSource == MusicAudioSource.youtube,
              onTap: () {
                HapticFeedback.mediumImpact();
                controller.setAudioSource(MusicAudioSource.youtube);
                Navigator.pop(context);
              },
            ),

            const SizedBox(height: 14),
            Center(
              child: Text(
                'Active Stream: ${controller.currentQualityLabel}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accentColor.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: accentColor, size: 22),
          ],
        ),
      ),
    );
  }
}
