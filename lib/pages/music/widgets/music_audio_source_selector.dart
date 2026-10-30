import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../../services/music/music_service.dart';
import 'package:flutter/material.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../widgets/prism/prism_sheet.dart';
import 'music_hoverable.dart';

class MusicAudioSourceSelectorButton extends StatelessWidget {
  const MusicAudioSourceSelectorButton({super.key});

  @override
  Widget build(BuildContext context) {
    final player = MusicPlayerController.instance;

    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) => ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final isFlac = player.audioSource == MusicAudioSource.flac;
          final isLight = palette.isLight;
          final accent = isFlac
              ? const Color(0xFF00D2EF)
              : const Color(0xFFFF3366);
          // Cyan/coral are unreadable on the clay header (~1.4:1 / 2.3:1);
          // light mode uses ink, dark keeps the source identity colours.
          final iconColor = isLight ? PrismLight.ink : accent;
          final labelColor = isLight
              ? PrismLight.ink
              : (isFlac ? const Color(0xFF00D2EF) : const Color(0xFFFF6688));
          final chevronColor = isLight
              ? PrismLight.inkSoft
              : (isFlac ? const Color(0xFF00D2EF) : const Color(0xFFFF6688));

          return MusicHoverable(
            scaleFactor: 1.05,
            child: InkWell(
              onTap: () => showAudioSourceDialog(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isLight ? 0.10 : 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLight
                        ? PrismLight.borderSubtle
                        : accent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFlac
                          ? Icons.diamond_rounded
                          : Icons.play_circle_fill_rounded,
                      color: iconColor,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isFlac ? 'FLAC' : 'YouTube',
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: chevronColor,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static void showAudioSourceDialog(BuildContext context) {
    PrismSheet.show(
      context,
      maxHeightFactor: 0.72,
      child: ListenableBuilder(
        listenable: MusicPlayerController.instance,
        builder: (ctx, _) {
          final player = MusicPlayerController.instance;
          final isFlac = player.audioSource == MusicAudioSource.flac;

          return ValueListenableBuilder<AppThemePalette>(
            valueListenable: AppThemeService.currentPalette,
            builder: (ctx, palette, _) {
              final isLight = palette.isLight;
              final ink = isLight ? PrismLight.ink : PrismDark.ink;
              final inkSoft = isLight ? PrismLight.inkSoft : PrismDark.inkSoft;
              final border = isLight
                  ? PrismLight.borderSubtle
                  : PrismDark.borderSubtle;
              final tileBase = isLight
                  ? PrismLight.raisedTop
                  : PrismDark.raisedTop;
              // #00D2EF / #FF3366 are identity colours, not text colours on
              // clay — light mode darkens them to AA-passing counterparts.
              const flacTint = Color(0xFF00D2EF);
              final flacInk = isLight ? const Color(0xFF0E7490) : flacTint;
              const ytTint = Color(0xFFFF3366);
              final ytInk = isLight
                  ? PrismAccent.accentTextLight
                  : const Color(0xFFFF6688);

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: palette.primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            color: PrismAccent.text(isLight),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Audio source & quality',
                                style: TextStyle(
                                  color: ink,
                                  fontSize: PrismType.section,
                                  fontWeight: PrismType.wBold,
                                ),
                              ),
                              const SizedBox(height: PrismSpace.xxs),
                              Text(
                                'Choose your preferred music extraction engine',
                                style: TextStyle(
                                  color: inkSoft,
                                  fontSize: PrismType.caption,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: PrismSpace.lg),
                    _sourceOptionCard(
                      title: 'FLAC Lossless (Qobuz Hi-Res)',
                      subtitle:
                          'Studio master quality up to 24-bit/192kHz with zero compression',
                      icon: Icons.diamond_rounded,
                      tint: flacTint,
                      accentInk: flacInk,
                      isSelected: isFlac,
                      badge: 'LOSSLESS',
                      base: tileBase,
                      border: border,
                      ink: ink,
                      inkSoft: inkSoft,
                      isLight: isLight,
                      onTap: () {
                        player.setAudioSource(MusicAudioSource.flac);
                        Navigator.pop(ctx);
                      },
                    ),
                    const SizedBox(height: PrismSpace.sm),
                    _sourceOptionCard(
                      title: 'YouTube Audio',
                      subtitle:
                          'High-speed audio extraction with intelligent track & duration matching',
                      icon: Icons.play_circle_fill_rounded,
                      tint: ytTint,
                      accentInk: ytInk,
                      isSelected: !isFlac,
                      badge: 'FAST',
                      base: tileBase,
                      border: border,
                      ink: ink,
                      inkSoft: inkSoft,
                      isLight: isLight,
                      onTap: () {
                        player.setAudioSource(MusicAudioSource.youtube);
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  static Widget _sourceOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color tint,
    required Color accentInk,
    required bool isSelected,
    required String badge,
    required Color base,
    required Color border,
    required Color ink,
    required Color inkSoft,
    required bool isLight,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: title,
      child: MusicHoverable(
        scaleFactor: 1.02,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PrismRadius.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: PrismSpace.giant),
            padding: const EdgeInsets.all(PrismSpace.md),
            decoration: BoxDecoration(
              color: isSelected
                  ? tint.withValues(alpha: isLight ? 0.10 : 0.14)
                  : base,
              borderRadius: BorderRadius.circular(PrismRadius.md),
              border: Border.all(
                color: isSelected
                    ? tint.withValues(alpha: isLight ? 0.45 : 0.5)
                    : border,
                width: isSelected ? 1.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? null
                  : PrismShadows.soft(isLight: isLight),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(PrismSpace.sm),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(PrismRadius.md),
                  ),
                  child: Icon(icon, color: accentInk, size: 24),
                ),
                const SizedBox(width: PrismSpace.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ink,
                                fontSize: PrismType.cardTitle,
                                fontWeight: PrismType.wBold,
                              ),
                            ),
                          ),
                          const SizedBox(width: PrismSpace.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tint.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                PrismRadius.sm - 4,
                              ),
                              border: Border.all(
                                color: tint.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                color: accentInk,
                                fontSize: PrismType.micro,
                                fontWeight: PrismType.wBold,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: PrismSpace.xxs),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: inkSoft,
                          fontSize: PrismType.caption,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: PrismSpace.xs),
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? accentInk : inkSoft,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
