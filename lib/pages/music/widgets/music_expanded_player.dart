import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/design/prism_tokens.dart';

import '../../../models/music/music_track.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../services/music/music_settings.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/music/music_waveform_seekbar.dart';
import 'music_audio_source_selector.dart';
import 'music_equalizer_modal.dart';
import 'music_queue_drawer.dart';
import 'music_sleep_timer_modal.dart';

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

class _MusicExpandedPlayerState extends State<MusicExpandedPlayer> {
  bool _queueOpen = false;
  AppThemePalette get _palette => AppThemeService.currentPalette.value;
  Color get _ink => PrismInk.primary(_palette.isLight);
  Color get _soft => PrismInk.soft(_palette.isLight);

  void _openQueue() {
    if (_queueOpen) return;
    _queueOpen = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _palette.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.78,
        child: MusicQueueDrawer(
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    ).whenComplete(() => _queueOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.playerController,
        AppThemeService.currentPalette,
      ]),
      builder: (context, _) {
        final track = widget.playerController.currentTrack;
        if (track == null) return const SizedBox.shrink();
        final screen = MediaQuery.sizeOf(context);
        final desktop = screen.width >= 800;
        final artSize = math
            .min(desktop ? 300.0 : screen.width - 72, screen.height * 0.32)
            .clamp(140.0, 340.0);
        final preset = MusicSettings.selectedFullscreenPreset.value;
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Close player',
                  onPressed: widget.onCollapse,
                  icon: Icon(
                    desktop
                        ? Icons.close_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _ink,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Now playing',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _soft,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add to playlist',
                  onPressed: widget.onAddToPlaylist,
                  icon: Icon(Icons.more_horiz_rounded, color: _ink),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (preset == MusicFullscreenPreset.customStudio)
              ...MusicSettings.componentOrderFullscreen.value.map(
                (key) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _customComponent(key, track, artSize),
                ),
              )
            else ...[
              _artwork(
                track,
                artSize,
                preset == MusicFullscreenPreset.vinylStudio,
              ),
              const SizedBox(height: 32),
              _title(track),
              const SizedBox(height: 24),
              _seekbar(
                preset == MusicFullscreenPreset.cyberWaveform
                    ? MusicSeekbarStyle.waveformEqualizer
                    : MusicSettings.customSeekbarStyle.value,
              ),
              const SizedBox(height: 16),
              _controls(),
            ],
            if (widget.playerController.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Audio unavailable. Try another source or song.',
                  style: TextStyle(color: _soft),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 20),
            _secondaryControls(),
            const SizedBox(height: 16),
            _queuePreview(),
          ],
        );
        final surface = ColoredBox(
          key: const ValueKey('music-player-surface'),
          color: _palette.scaffoldBackgroundColor,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: content,
            ),
          ),
        );
        if (desktop) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: widget.onCollapse,
                  child: ColoredBox(
                    color: PrismDark.sunken.withValues(alpha: 0.75),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 540,
                    maxHeight: screen.height * 0.92,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: PrismRadius.xlAll,
                      boxShadow: PrismShadows.floating(
                        isLight: _palette.isLight,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: PrismRadius.xlAll,
                      child: surface,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -280) {
              HapticFeedback.lightImpact();
              _openQueue();
            } else if ((details.primaryVelocity ?? 0) > 280) {
              widget.onCollapse();
            }
          },
          child: surface,
        );
      },
    );
  }

  Widget _artwork(MusicTrack track, double size, bool clayFrame) {
    final art = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(clayFrame ? 12 : 0),
      decoration: BoxDecoration(
        gradient: PrismShadows.surfaceGradient(_palette.isLight),
        borderRadius: PrismRadius.xlAll,
        boxShadow: PrismShadows.raised(isLight: _palette.isLight, scale: 1.25),
        border: Border.all(
          color: _palette.isLight
              ? PrismLight.borderSubtle
              : PrismDark.borderSubtle,
        ),
      ),
      child: ClipRRect(
        borderRadius: PrismRadius.lgAll,
        child: track.coverUrl.isEmpty
            ? ColoredBox(
                color: _palette.cardBackgroundColor,
                child: Icon(
                  Icons.album_rounded,
                  size: size * 0.4,
                  color: _soft,
                ),
              )
            : CachedNetworkImage(
                imageUrl: track.coverUrl,
                fit: BoxFit.cover,
                memCacheWidth: ImageCaps.kCardW,
                maxWidthDiskCache: ImageCaps.kCardW,
                errorWidget: (_, __, ___) =>
                    Icon(Icons.album_rounded, size: size * 0.4, color: _soft),
              ),
      ),
    );
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -280) _openQueue();
        if ((details.primaryVelocity ?? 0) > 280) widget.onCollapse();
      },
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -250) {
          widget.playerController.playNext();
        }
        if ((details.primaryVelocity ?? 0) > 250) {
          widget.playerController.playPrevious();
        }
      },
      onDoubleTapDown: (details) {
        final delta = details.localPosition.dx < size / 2 ? -10 : 10;
        widget.playerController.seekTo(
          widget.playerController.position + Duration(seconds: delta),
        );
      },
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(clayFrame ? -0.035 : 0),
        child: art,
      ),
    );
  }

  Widget _title(MusicTrack track) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _ink,
                fontSize: 24,
                height: 1.15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _soft, fontSize: 15),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: widget.isSaved ? 'Remove from liked songs' : 'Like song',
        onPressed: widget.onToggleSave,
        icon: Icon(
          widget.isSaved
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: widget.isSaved ? PrismAccent.text(_palette.isLight) : _soft,
          size: 28,
        ),
      ),
    ],
  );

  Widget _seekbar(MusicSeekbarStyle style) => MusicWaveformSeekbar(
    position: widget.playerController.position,
    duration: widget.playerController.duration,
    isPlaying: widget.playerController.isPlaying,
    style: style,
    onSeek: widget.playerController.seekTo,
  );

  Widget _controls() {
    final controller = widget.playerController;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: 'Shuffle',
          onPressed: controller.toggleShuffle,
          icon: Icon(
            Icons.shuffle_rounded,
            color: controller.isShuffle
                ? PrismAccent.text(_palette.isLight)
                : _soft,
          ),
        ),
        IconButton(
          tooltip: 'Previous song',
          onPressed: controller.playPrevious,
          icon: Icon(Icons.skip_previous_rounded, color: _ink, size: 34),
        ),
        SizedBox(
          width: 72,
          height: 72,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _palette.primaryColor,
              borderRadius:
                  MusicSettings.customPlayButtonStyle.value ==
                      MusicPlayButtonStyle.neonSquare
                  ? PrismRadius.lgAll
                  : BorderRadius.circular(36),
              boxShadow: PrismShadows.raised(isLight: _palette.isLight),
            ),
            child: IconButton(
              tooltip: controller.isPlaying ? 'Pause' : 'Play',
              onPressed: controller.isLoading
                  ? null
                  : controller.togglePlayPause,
              icon: controller.isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: PrismAccent.onAccent,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      controller.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: PrismAccent.onAccent,
                      size: 38,
                    ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next song',
          onPressed: controller.playNext,
          icon: Icon(Icons.skip_next_rounded, color: _ink, size: 34),
        ),
        IconButton(
          tooltip: 'Repeat',
          onPressed: controller.toggleRepeat,
          icon: Icon(
            controller.repeatMode == MusicRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: controller.repeatMode == MusicRepeatMode.off
                ? _soft
                : PrismAccent.text(_palette.isLight),
          ),
        ),
      ],
    );
  }

  Widget _sourceButton() => TextButton.icon(
    onPressed: () =>
        MusicAudioSourceSelectorButton.showAudioSourceDialog(context),
    icon: Icon(
      widget.playerController.isCurrentTrackLossless
          ? Icons.album_rounded
          : Icons.graphic_eq_rounded,
      size: 16,
    ),
    label: Text(
      widget.playerController.currentQualityLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    style: TextButton.styleFrom(foregroundColor: _soft),
  );

  Widget _secondaryControls() => Row(
    children: [
      Expanded(child: _sourceButton()),
      IconButton(
        tooltip: 'Lyrics',
        onPressed: widget.onLyricsTap,
        icon: Icon(Icons.format_quote_rounded, color: _soft),
      ),
      IconButton(
        tooltip: 'Equalizer',
        onPressed: () => MusicEqualizerModal.show(context),
        icon: Icon(Icons.tune_rounded, color: _soft),
      ),
      IconButton(
        tooltip: 'Sleep timer',
        onPressed: () => MusicSleepTimerModal.show(context),
        icon: Icon(Icons.bedtime_rounded, color: _soft),
      ),
    ],
  );

  Widget _queuePreview() {
    final upcoming = widget.playerController.upcomingTracks;
    return Tooltip(
      message: 'Queue & Up Next',
      child: Material(
        color: _palette.cardBackgroundColor,
        borderRadius: PrismRadius.lgAll,
        child: InkWell(
          onTap: _openQueue,
          borderRadius: PrismRadius.lgAll,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.queue_music_rounded, color: _ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Up next · ${upcoming.length} songs',
                        style: TextStyle(color: _soft, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        upcoming.isEmpty ? 'Open queue' : upcoming.first.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.keyboard_arrow_up_rounded, color: _soft),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customComponent(String key, MusicTrack track, double size) {
    switch (key) {
      case 'artwork':
        return _artwork(
          track,
          size,
          MusicSettings.customArtworkStyle.value !=
              MusicArtworkStyle.glowSphere,
        );
      case 'title':
        return _title(track);
      case 'qualityBadge':
        return _sourceButton();
      case 'seekbar':
        return _seekbar(MusicSettings.customSeekbarStyle.value);
      case 'mainControls':
        return _controls();
      case 'secondaryControls':
        return _secondaryControls();
      case 'extraActions':
        return TextButton.icon(
          onPressed: _openQueue,
          icon: const Icon(Icons.queue_music_rounded),
          label: const Text('Open queue'),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
