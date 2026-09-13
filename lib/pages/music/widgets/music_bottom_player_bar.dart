import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../services/music/music_settings.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import '../../../widgets/music/music_interactive_physics_button.dart';
import 'music_quality_badge.dart';

class MusicBottomPlayerBar extends StatelessWidget {
  final MusicPlayerController playerController;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final VoidCallback onExpandTap;
  final VoidCallback onQueueTap;
  final VoidCallback onLyricsTap;
  final VoidCallback onAddToPlaylist;

  const MusicBottomPlayerBar({
    super.key,
    required this.playerController,
    required this.isSaved,
    required this.onToggleSave,
    required this.onExpandTap,
    required this.onQueueTap,
    required this.onLyricsTap,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final track = playerController.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final palette = AppThemeService.currentPalette.value;
    final preset = MusicSettings.selectedMiniPreset.value;

    return GestureDetector(
      onTap: onExpandTap,
      child: PerformanceLiquidLens(
        style: PerformanceGlassStyles.dock,
        child: _buildPresetContainer(preset, palette, isMobile, track),
      ),
    );
  }

  Widget _buildPresetContainer(MusicMiniPlayerPreset preset, AppThemePalette palette, bool isMobile, MusicTrack track) {
    if (preset == MusicMiniPlayerPreset.compactPill) {
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F121C).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.primaryColor.withValues(alpha: 0.4), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildArtwork(track, size: 38, radius: 19),
            const SizedBox(width: 10),
            Expanded(child: _buildTrackInfo(track, isMobile, palette)),
            _buildControls(isMobile, palette, mini: true),
          ],
        ),
      );
    }

    if (preset == MusicMiniPlayerPreset.gradientWave) {
      return Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.primaryColor.withValues(alpha: 0.28),
              const Color(0xFF10131E).withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.primaryColor.withValues(alpha: 0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.3),
              blurRadius: 26,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildArtwork(track, size: 44, radius: 12),
            const SizedBox(width: 12),
            Expanded(child: _buildTrackInfo(track, isMobile, palette)),
            _buildControls(isMobile, palette),
          ],
        ),
      );
    }

    if (preset == MusicMiniPlayerPreset.minimalistLine) {
      return Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D14).withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            _buildArtwork(track, size: 34, radius: 6),
            const SizedBox(width: 10),
            Expanded(child: _buildTrackInfo(track, isMobile, palette, compact: true)),
            _buildControls(isMobile, palette, mini: true),
          ],
        ),
      );
    }

    if (preset == MusicMiniPlayerPreset.customStudio) {
      final order = MusicSettings.componentOrderMini.value;
      return Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF131522).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.primaryColor.withValues(alpha: 0.4), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: order.map((key) {
            switch (key) {
              case 'artwork':
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildArtwork(track, size: 44, radius: 10),
                    const SizedBox(width: 12),
                  ],
                );
              case 'trackInfo':
                return Expanded(child: _buildTrackInfo(track, isMobile, palette));
              case 'mainControls':
                return _buildControls(isMobile, palette);
              case 'extraActions':
                return !isMobile
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: isSaved ? const Color(0xFFFF4B72) : Colors.white60,
                              size: 20,
                            ),
                            onPressed: onToggleSave,
                          ),
                        ],
                      )
                    : const SizedBox.shrink();
              default:
                return const SizedBox.shrink();
            }
          }).toList(),
        ),
      );
    }

    // Default: Floating Glass Island
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF131522).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.primaryColor.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: palette.primaryColor.withValues(alpha: 0.2),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        children: [
          _buildArtwork(track, size: 44, radius: 10),
          const SizedBox(width: 12),
          Expanded(child: _buildTrackInfo(track, isMobile, palette)),
          _buildControls(isMobile, palette),
        ],
      ),
    );
  }

  Widget _buildArtwork(MusicTrack track, {required double size, required double radius}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: track.coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // P12: decode-capped (was full-res).
        memCacheWidth: ImageCaps.kCardW,
        maxWidthDiskCache: ImageCaps.kCardW,
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          color: const Color(0xFF1A1D2E),
          child: const Icon(Icons.music_note_rounded, color: Colors.white54, size: 20),
        ),
      ),
    );
  }

  Widget _buildTrackInfo(MusicTrack track, bool isMobile, AppThemePalette palette, {bool compact = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: compact ? 12 : 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                track.artist,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (MusicSettings.showLosslessBadge.value) ...[
              const SizedBox(width: 6),
              const MusicQualityBadge(
                fontSize: 8.5,
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildControls(bool isMobile, AppThemePalette palette, {bool mini = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isMobile) ...[
          IconButton(
            icon: Icon(
              isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isSaved ? const Color(0xFFFF4B72) : Colors.white60,
              size: 20,
            ),
            onPressed: onToggleSave,
          ),
          IconButton(
            icon: const Icon(Icons.format_quote_rounded, color: Colors.white60, size: 20),
            onPressed: onLyricsTap,
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
            onPressed: playerController.playPrevious,
          ),
        ],
        _buildPlayPauseButton(palette, mini: mini),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
          onPressed: playerController.playNext,
        ),
        if (!isMobile)
          IconButton(
            icon: const Icon(Icons.queue_music_rounded, color: Colors.white60, size: 20),
            onPressed: onQueueTap,
          ),
      ],
    );
  }

  Widget _buildPlayPauseButton(AppThemePalette palette, {bool mini = false}) {
    final hoverEffect = MusicSettings.customHoverEffect.value;
    final playBtnStyle = MusicSettings.customPlayButtonStyle.value;

    return MusicInteractivePhysicsButton(
      effect: hoverEffect,
      glowColor: palette.primaryColor,
      borderRadius: BorderRadius.circular(mini ? 16 : 22),
      onTap: playerController.togglePlayPause,
      child: playerController.isLoading
          ? SizedBox(
              width: mini ? 24 : 32,
              height: mini ? 24 : 32,
              child: CircularProgressIndicator(
                color: palette.primaryColor,
                strokeWidth: 2.5,
              ),
            )
          : _buildPlayButtonIcon(playBtnStyle, palette, mini),
    );
  }

  Widget _buildPlayButtonIcon(MusicPlayButtonStyle style, AppThemePalette palette, bool mini) {
    final isPlaying = playerController.isPlaying;
    final icon = isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
    final size = mini ? 32.0 : 40.0;
    final iconSize = mini ? 20.0 : 26.0;

    if (style == MusicPlayButtonStyle.liquidGlassNeo) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: palette.primaryColor.withValues(alpha: 0.25),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      );
    }

    if (style == MusicPlayButtonStyle.neonSquare) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(mini ? 8 : 12),
          gradient: LinearGradient(colors: [palette.primaryColor, palette.accentColor]),
          boxShadow: [
            BoxShadow(color: palette.primaryColor.withValues(alpha: 0.5), blurRadius: 12),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      );
    }

    // Default: Circle Glow
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [palette.primaryColor, palette.accentColor]),
        boxShadow: [
          BoxShadow(color: palette.primaryColor.withValues(alpha: 0.55), blurRadius: 14),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}

