import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:flutter/services.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../services/music/music_radio_service.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';

/// Queue drawer (restyle 2026-11-09): the hardcoded 0xFF7C5CFF purple +
/// raw white text are gone in favour of [AppThemePalette.primaryColor] and
/// the Prism ink/silver tokens. Adds a "More like this" rail fed by
/// [MusicRadioService.generateSongRadio] with play-next / add-to-queue
/// actions on the existing player controller (extended, not rewritten).
class MusicQueueDrawer extends StatefulWidget {
  final VoidCallback onClose;

  const MusicQueueDrawer({super.key, required this.onClose});

  @override
  State<MusicQueueDrawer> createState() => _MusicQueueDrawerState();
}

class _MusicQueueDrawerState extends State<MusicQueueDrawer> {
  bool _showHistory = false;

  // Similar next-up state. Cached per seed track so controller churn
  // doesn't re-fire the radio search on every notifyListeners().
  String? _similarSeedId;
  bool _similarLoading = false;
  List<MusicTrack>? _similar;

  bool get _isLight => AppThemeService.currentPalette.value.isLight;
  Color get _ink => PrismInk.primary(_isLight);
  Color get _inkSoft => PrismInk.soft(_isLight);
  Color get _inkFaint => PrismInk.faint(_isLight);

  Color get _accent => AppThemeService.currentPalette.value.primaryColor;

  @override
  void initState() {
    super.initState();
    MusicPlayerController.instance.addListener(_onControllerChanged);
    _maybeLoadSimilar();
  }

  @override
  void dispose() {
    MusicPlayerController.instance.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
    _maybeLoadSimilar();
  }

  /// Loads similar tracks for the currently playing track. Skips everything
  /// already in the queue (now playing + upcoming + history) by id.
  Future<void> _maybeLoadSimilar() async {
    final controller = MusicPlayerController.instance;
    final current = controller.currentTrack;
    if (current == null || _similarSeedId == current.id) return;

    _similarSeedId = current.id;
    _similarLoading = true;
    _similar = null;
    if (mounted) setState(() {});

    try {
      final radio = await MusicRadioService.instance.generateSongRadio(current);
      if (!mounted) return;
      final queuedIds = <String>{
        ...[
          current,
          ...controller.upcomingTracks,
          ...controller.historyTracks,
        ].map((t) => t.id),
      };
      final suggestions = radio
          .where((t) => !queuedIds.contains(t.id))
          .take(6)
          .toList();
      if (!mounted || _similarSeedId != current.id) return;
      setState(() {
        _similarLoading = false;
        _similar = suggestions;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _similarLoading = false;
        _similar = const [];
      });
    }
  }

  void _playNextFromSimilar(MusicTrack track) {
    HapticFeedback.lightImpact();
    MusicPlayerController.instance.playTrackNext(track);
    // Remove from the rail so it can't be queued twice.
    setState(() {
      _similar = _similar?.where((t) => t.id != track.id).toList();
    });
  }

  void _queueFromSimilar(MusicTrack track) {
    HapticFeedback.lightImpact();
    MusicPlayerController.instance.addTrackToQueue(track);
    setState(() {
      _similar = _similar?.where((t) => t.id != track.id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayerController.instance;
    final currentTrack = controller.currentTrack;
    final upcoming = controller.upcomingTracks;
    final history = controller.historyTracks;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final accent = _accent;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        width: isMobile ? MediaQuery.sizeOf(context).width : 400,
        decoration: BoxDecoration(
          gradient: PrismShadows.surfaceGradient(_isLight),
          borderRadius: isMobile
              ? const BorderRadius.vertical(top: Radius.circular(28))
              : const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  bottomLeft: Radius.circular(28),
                ),
          boxShadow: PrismShadows.floating(isLight: _isLight),
        ),
        // Audit follow-up 2026-11-10: top padding now includes the status
        // bar inset. Without it the header row (and the X close button)
        // rendered behind system status-bar chrome and taps near it missed.
        padding: EdgeInsets.fromLTRB(
          20,
          20 + MediaQuery.paddingOf(context).top,
          20,
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.queue_music_rounded,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Queue & Up Next',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (upcoming.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      controller.clearUpcomingQueue();
                      setState(() {});
                    },
                    child: Text(
                      'Clear',
                      style: TextStyle(color: _inkFaint, fontSize: 12),
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: _inkSoft, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  // 1. NOW PLAYING
                  if (currentTrack != null) ...[
                    _sectionLabel('NOW PLAYING'),
                    const SizedBox(height: 8),
                    _buildNowPlayingCard(currentTrack, controller, accent),
                    const SizedBox(height: 18),
                  ],

                  // 2. UP NEXT REORDERABLE LIST
                  Row(
                    children: [
                      _sectionLabel('UP NEXT (${upcoming.length})'),
                      const Spacer(),
                      if (upcoming.isNotEmpty)
                        Text(
                          'Drag handles to reorder',
                          style: TextStyle(
                            color: _inkFaint.withValues(alpha: 0.5),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (upcoming.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Icon(
                            Icons.playlist_play_rounded,
                            color: _ink.withValues(alpha: 0.15),
                            size: 42,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No more songs queued up',
                            style: TextStyle(color: _inkFaint, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Songs you play or add will appear here',
                            style: TextStyle(
                              color: _inkFaint.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      ),
                      child: ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: upcoming.length,
                        onReorder: (oldIdx, newIdx) {
                          HapticFeedback.selectionClick();
                          controller.reorderUpcomingQueue(oldIdx, newIdx);
                          setState(() {});
                        },
                        itemBuilder: (context, index) {
                          final track = upcoming[index];
                          return _buildUpcomingItem(
                            key: ValueKey('upcoming_${track.id}_$index'),
                            track: track,
                            index: index,
                            controller: controller,
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 16),

                  // 3. SIMILAR NEXT-UP — radio suggestions for the current seed
                  if (currentTrack != null && _buildSimilarSection() != null)
                    _buildSimilarSection()!,

                  // 4. HISTORY SECTION
                  if (history.isNotEmpty) ...[
                    InkWell(
                      onTap: () => setState(() => _showHistory = !_showHistory),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            Icon(
                              _showHistory
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_right_rounded,
                              color: _inkFaint,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            _sectionLabel(
                              'PLAYED RECENTLY (${history.length})',
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showHistory) ...[
                      const SizedBox(height: 6),
                      for (int hIdx = history.length - 1; hIdx >= 0; hIdx--)
                        _buildHistoryItem(history[hIdx], hIdx, controller),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: _inkFaint,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget? _buildSimilarSection() {
    if (_similarLoading && _similar == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('UP NEXT · FOR THIS SONG'),
          const SizedBox(height: 12),
          const Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      );
    }
    final suggestions = _similar;
    if (suggestions == null || suggestions.isEmpty) return null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('UP NEXT · FOR THIS SONG'),
        const SizedBox(height: 8),
        for (final track in suggestions) _buildSimilarItem(track),
      ],
    );
  }

  Widget _buildSimilarItem(MusicTrack track) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: track.coverUrl,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              memCacheWidth: ImageCaps.kThumb,
              maxWidthDiskCache: ImageCaps.kThumb,
            ),
          ),
          title: Text(
            track.title,
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            style: TextStyle(color: _inkFaint, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Tap = play next (the next-up contract of this rail).
          onTap: () => _playNextFromSimilar(track),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Play next',
                icon: Icon(
                  Icons.low_priority_rounded,
                  color: _accent,
                  size: 18,
                ),
                onPressed: () => _playNextFromSimilar(track),
              ),
              IconButton(
                tooltip: 'Add to queue',
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  color: _inkFaint,
                  size: 18,
                ),
                onPressed: () => _queueFromSimilar(track),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNowPlayingCard(
    MusicTrack track,
    MusicPlayerController controller,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: track.coverUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              memCacheWidth: ImageCaps.kThumb,
              maxWidthDiskCache: ImageCaps.kThumb,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Animated Waveform Indicator + one-tap seed radio affordance:
          // every playing screen offers the next obvious action.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.graphic_eq_rounded,
                      color: PrismAccent.onAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      controller.isLoading
                          ? 'Loading'
                          : controller.isPlaying
                          ? 'Playing'
                          : 'Paused',
                      style: const TextStyle(
                        color: PrismAccent.onAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Play radio for this song',
                icon: Icon(Icons.radar_rounded, color: accent, size: 22),
                onPressed: () => MusicRadioService.instance.startRadioForTrack(
                  context,
                  track,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingItem({
    required Key key,
    required MusicTrack track,
    required int index,
    required MusicPlayerController controller,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppThemeService.currentPalette.value.cardBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _ink.withValues(alpha: 0.05)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: track.coverUrl,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              memCacheWidth: ImageCaps.kThumb,
              maxWidthDiskCache: ImageCaps.kThumb,
            ),
          ),
          title: Text(
            track.title,
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            style: TextStyle(color: _inkFaint, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            HapticFeedback.selectionClick();
            final targetIndex = controller.currentIndex + 1 + index;
            controller.jumpToQueueIndex(targetIndex);
            setState(() {});
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Delete from queue button
              IconButton(
                icon: Icon(
                  Icons.remove_circle_outline_rounded,
                  color: _inkFaint.withValues(alpha: 0.7),
                  size: 18,
                ),
                tooltip: 'Remove',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final targetIndex = controller.currentIndex + 1 + index;
                  controller.removeFromQueue(targetIndex);
                  setState(() {});
                },
              ),
              // Reorder Drag Handle
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: Color(0xFFB9BEC9),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryItem(
    MusicTrack track,
    int originalIndex,
    MusicPlayerController controller,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 1,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedNetworkImage(
              imageUrl: track.coverUrl,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              memCacheWidth: ImageCaps.kThumb,
              maxWidthDiskCache: ImageCaps.kThumb,
            ),
          ),
          title: Text(
            track.title,
            style: TextStyle(color: _inkSoft, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            style: TextStyle(
              color: _inkFaint.withValues(alpha: 0.6),
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: MusicHoverable(
            scaleFactor: 1.1,
            child: IconButton(
              icon: Icon(Icons.replay_rounded, color: _inkFaint, size: 18),
              tooltip: 'Replay now',
              onPressed: () {
                controller.jumpToQueueIndex(originalIndex);
                setState(() {});
              },
            ),
          ),
        ),
      ),
    );
  }
}
