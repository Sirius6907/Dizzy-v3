import '../../../services/music/music_service.dart';
import 'package:flutter/material.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';

class MusicAudioSourceSelectorButton extends StatelessWidget {
  const MusicAudioSourceSelectorButton({super.key});

  @override
  Widget build(BuildContext context) {
    final player = MusicPlayerController.instance;

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final isFlac = player.audioSource == MusicAudioSource.flac;

        return MusicHoverable(
          scaleFactor: 1.05,
          child: InkWell(
            onTap: () => showAudioSourceDialog(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isFlac
                    ? const Color(0xFF00D2EF).withValues(alpha: 0.12)
                    : const Color(0xFFFF3366).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isFlac
                      ? const Color(0xFF00D2EF).withValues(alpha: 0.4)
                      : const Color(0xFFFF3366).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFlac ? Icons.diamond_rounded : Icons.play_circle_fill_rounded,
                    color: isFlac ? const Color(0xFF00D2EF) : const Color(0xFFFF3366),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isFlac ? 'FLAC' : 'YouTube',
                    style: TextStyle(
                      color: isFlac ? const Color(0xFF00D2EF) : const Color(0xFFFF6688),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    color: isFlac ? const Color(0xFF00D2EF) : const Color(0xFFFF6688),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void showAudioSourceDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final player = MusicPlayerController.instance;

        return ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final isFlac = player.audioSource == MusicAudioSource.flac;

            return PerformanceLiquidLens(
              style: PerformanceGlassStyles.sheet,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F111D).withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.tune_rounded, color: Color(0xFF7C5CFF), size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Audio Source & Quality',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Choose your preferred music extraction engine',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sourceOptionCard(
                      title: 'FLAC Lossless (Qobuz Hi-Res)',
                      subtitle: 'Studio master quality up to 24-bit/192kHz with zero compression',
                      icon: Icons.diamond_rounded,
                      iconColor: const Color(0xFF00D2EF),
                      isSelected: isFlac,
                      badge: 'LOSSLESS',
                      badgeColor: const Color(0xFF00D2EF),
                      onTap: () {
                        player.setAudioSource(MusicAudioSource.flac);
                        Navigator.pop(ctx);
                      },
                    ),
                    const SizedBox(height: 12),
                    _sourceOptionCard(
                      title: 'YouTube Audio',
                      subtitle: 'High-speed audio extraction with intelligent track & duration matching',
                      icon: Icons.play_circle_fill_rounded,
                      iconColor: const Color(0xFFFF3366),
                      isSelected: !isFlac,
                      badge: 'FAST',
                      badgeColor: const Color(0xFFFF3366),
                      onTap: () {
                        player.setAudioSource(MusicAudioSource.youtube);
                        Navigator.pop(ctx);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _sourceOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required String badge,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return MusicHoverable(
      scaleFactor: 1.02,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? iconColor.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? iconColor.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: iconColor, size: 22)
              else
                const Icon(Icons.radio_button_unchecked_rounded, color: Colors.white30, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

