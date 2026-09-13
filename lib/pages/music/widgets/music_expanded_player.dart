import 'dart:ui';
import 'music_audio_source_selector.dart';
import 'music_dynamic_canvas_background.dart';
import 'music_quality_badge.dart';
import 'music_equalizer_modal.dart';
import 'music_sleep_timer_modal.dart';
import 'music_audio_visualizer.dart';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../services/music/music_settings.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import '../../../widgets/music/music_interactive_physics_button.dart';
import '../../../widgets/music/music_waveform_seekbar.dart';
import 'music_hoverable.dart';

class MusicExpandedPlayer extends StatefulWidget {
  final MusicPlayerController playerController;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final VoidCallback onCollapse;
  final VoidCallback onQueueTap;
  final VoidCallback? onLyricsTap;
  final VoidCallback onAddToPlaylist;

  const MusicExpandedPlayer({
    super.key,
    required this.playerController,
    required this.isSaved,
    required this.onToggleSave,
    required this.onCollapse,
    required this.onQueueTap,
    this.onLyricsTap,
    required this.onAddToPlaylist,
  });

  @override
  State<MusicExpandedPlayer> createState() => _MusicExpandedPlayerState();
}

class _MusicExpandedPlayerState extends State<MusicExpandedPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _discAnimController;

  @override
  void initState() {
    super.initState();
    _discAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.playerController.isPlaying) {
      _discAnimController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MusicExpandedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playerController.isPlaying && !_discAnimController.isAnimating) {
      _discAnimController.repeat();
    } else if (!widget.playerController.isPlaying && _discAnimController.isAnimating) {
      _discAnimController.stop();
    }
  }

  @override
  void dispose() {
    _discAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.playerController.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final palette = AppThemeService.currentPalette.value;
    final preset = MusicSettings.selectedFullscreenPreset.value;
    final seekStyle = MusicSettings.customSeekbarStyle.value;
    final artStyle = MusicSettings.customArtworkStyle.value;
    final order = MusicSettings.componentOrderFullscreen.value;

    final screenSize = MediaQuery.sizeOf(context);
    final isDesktop = screenSize.width >= 800;
    final artSize = isDesktop
        ? 230.0
        : math.min(screenSize.width * 0.75, screenSize.height * 0.38);

    final playerBody = Column(
      children: [
        // Top Navigation & Actions Bar
        Row(
          children: [
            MusicHoverable(
              scaleFactor: 1.1,
              child: IconButton(
                icon: Icon(
                  isDesktop ? Icons.close_rounded : Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: isDesktop ? 24 : 32,
                ),
                onPressed: widget.onCollapse,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () => MusicAudioSourceSelectorButton.showAudioSourceDialog(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.playerController.isCurrentTrackLossless
                      ? const Color(0xFF00D2EF).withValues(alpha: 0.15)
                      : const Color(0xFFFF3366).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.playerController.isCurrentTrackLossless
                        ? const Color(0xFF00D2EF).withValues(alpha: 0.4)
                        : const Color(0xFFFF3366).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.playerController.isCurrentTrackLossless
                          ? Icons.diamond_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 13,
                      color: widget.playerController.isCurrentTrackLossless
                          ? const Color(0xFF00D2EF)
                          : const Color(0xFFFF6688),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      widget.playerController.currentQualityLabel.toUpperCase(),
                      style: TextStyle(
                        color: widget.playerController.isCurrentTrackLossless
                            ? const Color(0xFF00D2EF)
                            : const Color(0xFFFF6688),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 16,
                      color: widget.playerController.isCurrentTrackLossless
                          ? const Color(0xFF00D2EF)
                          : const Color(0xFFFF6688),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            MusicHoverable(
              scaleFactor: 1.1,
              child: IconButton(
                icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                onPressed: widget.onAddToPlaylist,
              ),
            ),
          ],
        ),
        if (!isDesktop) const Spacer() else const SizedBox(height: 12),

        // Preset-based or Custom Arranged Body
        if (preset == MusicFullscreenPreset.customStudio)
          ...order.map((key) => _buildCustomComponent(key, track, palette, seekStyle, artStyle, artSize))
        else
          ..._buildPresetBody(preset, track, palette, seekStyle, artSize),

        if (!isDesktop) const Spacer() else const SizedBox(height: 12),
      ],
    );

    if (isDesktop) {
      return Stack(
        alignment: Alignment.center,
        children: [
          // Dismissible Scrim with blur
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onCollapse,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                ),
              ),
            ),
          ),
          // Floating Modal Card
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 540,
                maxHeight: math.min(740, screenSize.height * 0.88),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0D14),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.75),
                      blurRadius: 40,
                      spreadRadius: 8,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: MusicDynamicCanvasBackground(
                    track: track,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                      child: playerBody,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 280) {
          HapticFeedback.lightImpact();
          widget.onCollapse();
        }
      },
      child: MusicDynamicCanvasBackground(
        track: track,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
            child: playerBody,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPresetBody(
    MusicFullscreenPreset preset,
    MusicTrack track,
    AppThemePalette palette,
    MusicSeekbarStyle seekStyle,
    double artSize,
  ) {
    return [
      // Artwork Section with Gestures
      if (preset == MusicFullscreenPreset.vinylStudio)
        _wrapArtworkGestures(_buildVinylDiscArtwork(track, artSize, palette), artSize)
      else if (preset == MusicFullscreenPreset.cyberWaveform)
        _wrapArtworkGestures(_buildCyberWaveArtwork(track, artSize, palette), artSize)
      else if (preset == MusicFullscreenPreset.liquidGlassNeo)
        _wrapArtworkGestures(_buildLiquidGlassArtwork(track, artSize, palette), artSize)
      else
        _wrapArtworkGestures(_buildCinematicArtwork(track, artSize), artSize),

      const SizedBox(height: 24),

      // Track & Artist Title Row with Like Button
      _buildTitleRow(track),

      const SizedBox(height: 16),

      // Scrubber Canvas
      MusicWaveformSeekbar(
        position: widget.playerController.position,
        duration: widget.playerController.duration,
        isPlaying: widget.playerController.isPlaying,
        style: preset == MusicFullscreenPreset.cyberWaveform
            ? MusicSeekbarStyle.waveformEqualizer
            : (preset == MusicFullscreenPreset.liquidGlassNeo
                ? MusicSeekbarStyle.liquidGlassSlider
                : seekStyle),
        onSeek: (pos) => widget.playerController.seekTo(pos),
      ),

      const SizedBox(height: 16),

      // Main Controls
      _buildPlaybackControlsRow(palette),

      const SizedBox(height: 8),

      // Live Spectrum Audio Visualizer
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: MusicAudioVisualizer(
          isPlaying: widget.playerController.isPlaying,
          barCount: 26,
          height: 24,
          gradient: LinearGradient(
            colors: [
              palette.primaryColor.withValues(alpha: 0.7),
              palette.accentColor.withValues(alpha: 0.9),
            ],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
        ),
      ),
    ];
  }

  Widget _buildCustomComponent(
    String key,
    MusicTrack track,
    AppThemePalette palette,
    MusicSeekbarStyle seekStyle,
    MusicArtworkStyle artStyle,
    double artSize,
  ) {
    switch (key) {
      case 'artwork':
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildCustomArtworkByStyle(track, artSize, palette, artStyle),
        );
      case 'title':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildTitleRow(track),
        );
      case 'qualityBadge':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF00D2EF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF00D2EF).withValues(alpha: 0.4)),
            ),
            child: Text(
              '${widget.playerController.currentQualityLabel.toUpperCase()} • HI-RES LOSSLESS AUDIO',
              style: const TextStyle(color: Color(0xFF00D2EF), fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6),
            ),
          ),
        );
      case 'seekbar':
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: MusicWaveformSeekbar(
            position: widget.playerController.position,
            duration: widget.playerController.duration,
            isPlaying: widget.playerController.isPlaying,
            style: seekStyle,
            onSeek: (pos) => widget.playerController.seekTo(pos),
          ),
        );
      case 'mainControls':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildPlaybackControlsRow(palette),
        );
      case 'secondaryControls':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Karaoke Lyrics',
                icon: const Icon(Icons.format_quote_rounded, color: Colors.white70, size: 22),
                onPressed: widget.onLyricsTap ?? widget.onCollapse,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Equalizer & 3D Spatial Audio',
                icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 22),
                onPressed: () => MusicEqualizerModal.show(context),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Queue & Up Next',
                icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 22),
                onPressed: widget.onQueueTap,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Sleep Timer',
                icon: const Icon(Icons.bedtime_rounded, color: Colors.white70, size: 22),
                onPressed: () => MusicSleepTimerModal.show(context),
              ),
            ],
          ),
        );
      case 'extraActions':
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: widget.onQueueTap,
                icon: Icon(Icons.queue_music_rounded, color: palette.primaryColor, size: 16),
                label: const Text('Playing Queue', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: palette.primaryColor.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTitleRow(MusicTrack track) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                track.artist,
                style: const TextStyle(color: Colors.white60, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              const MusicQualityBadge(),
            ],
          ),
        ),
        MusicInteractivePhysicsButton(
          effect: MusicSettings.customHoverEffect.value,
          glowColor: const Color(0xFFFF4B72),
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onToggleSave,
          child: Padding(
            padding: const EdgeInsets.all(6.0),
            child: Icon(
              widget.isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: widget.isSaved ? const Color(0xFFFF4B72) : Colors.white70,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControlsRow(AppThemePalette palette) {
    final hoverEffect = MusicSettings.customHoverEffect.value;
    final playBtnStyle = MusicSettings.customPlayButtonStyle.value;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: palette.primaryColor,
          borderRadius: BorderRadius.circular(14),
          onTap: widget.playerController.toggleShuffle,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.shuffle_rounded,
              color: widget.playerController.isShuffle ? palette.primaryColor : Colors.white38,
              size: 24,
            ),
          ),
        ),
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: palette.primaryColor,
          borderRadius: BorderRadius.circular(14),
          onTap: widget.playerController.playPrevious,
          child: const Padding(
            padding: EdgeInsets.all(8.0),
            child: Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
          ),
        ),
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: palette.primaryColor,
          borderRadius: BorderRadius.circular(32),
          onTap: widget.playerController.togglePlayPause,
          child: widget.playerController.isLoading
              ? SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(color: palette.primaryColor, strokeWidth: 3),
                )
              : _buildExpandedPlayButtonIcon(playBtnStyle, palette),
        ),
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: palette.primaryColor,
          borderRadius: BorderRadius.circular(14),
          onTap: widget.playerController.playNext,
          child: const Padding(
            padding: EdgeInsets.all(8.0),
            child: Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
          ),
        ),
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: palette.primaryColor,
          borderRadius: BorderRadius.circular(14),
          onTap: widget.playerController.toggleRepeat,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              widget.playerController.repeatMode == MusicRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: widget.playerController.repeatMode != MusicRepeatMode.off ? palette.primaryColor : Colors.white38,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedPlayButtonIcon(MusicPlayButtonStyle style, AppThemePalette palette) {
    final isPlaying = widget.playerController.isPlaying;
    final icon = isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;

    if (style == MusicPlayButtonStyle.liquidGlassNeo) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: palette.primaryColor.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.5),
              blurRadius: 20,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 38),
      );
    }

    if (style == MusicPlayButtonStyle.neonSquare) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: [palette.primaryColor, palette.accentColor]),
          boxShadow: [
            BoxShadow(color: palette.primaryColor.withValues(alpha: 0.6), blurRadius: 20),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 38),
      );
    }

    // Default: Circle Glow
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [palette.primaryColor, palette.accentColor]),
        boxShadow: [
          BoxShadow(color: palette.primaryColor.withValues(alpha: 0.6), blurRadius: 22, spreadRadius: 2),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 40),
    );
  }

  Widget _buildVinylDiscArtwork(MusicTrack track, double size, AppThemePalette palette) {
    return AnimatedBuilder(
      animation: _discAnimController,
      builder: (context, child) => Transform.rotate(
        angle: widget.playerController.isPlaying ? _discAnimController.value * 2 * math.pi : 0,
        child: child,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF10131E),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 4),
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.4),
              blurRadius: 36,
            ),
          ],
        ),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.22),
            child: CachedNetworkImage(
              imageUrl: track.coverUrl,
              width: size * 0.44,
              height: size * 0.44,
              fit: BoxFit.cover,
              // P12: decode-capped (was full-res).
              memCacheWidth: ImageCaps.kCardW,
              maxWidthDiskCache: ImageCaps.kCardW,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCyberWaveArtwork(MusicTrack track, double size, AppThemePalette palette) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.primaryColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: palette.primaryColor.withValues(alpha: 0.45),
            blurRadius: 30,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CachedNetworkImage(
          imageUrl: track.coverUrl,
          fit: BoxFit.cover,
          // P12: decode-capped (was full-res).
          memCacheWidth: ImageCaps.kCardW,
          maxWidthDiskCache: ImageCaps.kCardW,
        ),
      ),
    );
  }

  Widget _buildLiquidGlassArtwork(MusicTrack track, double size, AppThemePalette palette) {
    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.35),
              blurRadius: 28,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: CachedNetworkImage(
            imageUrl: track.coverUrl,
            fit: BoxFit.cover,
            // P12: decode-capped (was full-res).
            memCacheWidth: ImageCaps.kCardW,
            maxWidthDiskCache: ImageCaps.kCardW,
          ),
        ),
      ),
    );
  }

  Widget _buildCinematicArtwork(MusicTrack track, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: CachedNetworkImage(
        imageUrl: track.coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // P12: decode-capped (was full-res).
        memCacheWidth: ImageCaps.kCardW,
        maxWidthDiskCache: ImageCaps.kCardW,
      ),
    );
  }

  Widget _buildCustomArtworkByStyle(MusicTrack track, double size, AppThemePalette palette, MusicArtworkStyle style) {
    if (style == MusicArtworkStyle.vinylSpinningDisc) {
      return _buildVinylDiscArtwork(track, size, palette);
    }
    if (style == MusicArtworkStyle.floatingCard3D) {
      return _buildLiquidGlassArtwork(track, size, palette);
    }
    if (style == MusicArtworkStyle.glowSphere) {
      return _wrapArtworkGestures(
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: palette.primaryColor.withValues(alpha: 0.5),
                blurRadius: 36,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: CachedNetworkImage(
              imageUrl: track.coverUrl,
              fit: BoxFit.cover,
              // P12: decode-capped (was full-res).
              memCacheWidth: ImageCaps.kCardW,
              maxWidthDiskCache: ImageCaps.kCardW,
            ),
          ),
        ),
        size,
      );
    }
    return _wrapArtworkGestures(_buildCinematicArtwork(track, size), size);
  }

  Widget _wrapArtworkGestures(Widget artwork, double size) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -250) {
          HapticFeedback.mediumImpact();
          widget.playerController.playNext();
        } else if (velocity > 250) {
          HapticFeedback.mediumImpact();
          widget.playerController.playPrevious();
        }
      },
      onDoubleTapDown: (details) {
        final x = details.localPosition.dx;
        if (x < size * 0.4) {
          HapticFeedback.lightImpact();
          widget.playerController.seekTo(
            widget.playerController.position - const Duration(seconds: 10),
          );
        } else if (x > size * 0.6) {
          HapticFeedback.lightImpact();
          widget.playerController.seekTo(
            widget.playerController.position + const Duration(seconds: 10),
          );
        }
      },
      child: artwork,
    );
  }
}

