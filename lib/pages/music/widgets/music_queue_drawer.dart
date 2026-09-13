import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';

class MusicQueueDrawer extends StatefulWidget {
  final VoidCallback onClose;

  const MusicQueueDrawer({
    super.key,
    required this.onClose,
  });

  @override
  State<MusicQueueDrawer> createState() => _MusicQueueDrawerState();
}

class _MusicQueueDrawerState extends State<MusicQueueDrawer> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayerController.instance;
    final currentTrack = controller.currentTrack;
    final upcoming = controller.upcomingTracks;
    final history = controller.historyTracks;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        width: isMobile ? MediaQuery.sizeOf(context).width : 400,
        decoration: BoxDecoration(
          color: const Color(0xFF0D101A).withValues(alpha: 0.96),
          borderRadius: isMobile
              ? const BorderRadius.vertical(top: Radius.circular(28))
              : const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  bottomLeft: Radius.circular(28),
                ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 36,
              offset: const Offset(-8, 0),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.queue_music_rounded,
                    color: Color(0xFF7C5CFF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Queue & Up Next',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                if (upcoming.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      controller.clearUpcomingQueue();
                      setState(() {});
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
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
                    const Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildNowPlayingCard(currentTrack, controller),
                    const SizedBox(height: 18),
                  ],

                  // 2. UP NEXT REORDERABLE LIST
                  Row(
                    children: [
                      Text(
                        'UP NEXT (${upcoming.length})',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      if (upcoming.isNotEmpty)
                        const Text(
                          'Drag handles to reorder',
                          style: TextStyle(color: Colors.white24, fontSize: 10),
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
                          Icon(Icons.playlist_play_rounded, color: Colors.white.withValues(alpha: 0.15), size: 42),
                          const SizedBox(height: 8),
                          const Text(
                            'No more songs queued up',
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Songs you play or add will appear here',
                            style: TextStyle(color: Colors.white24, fontSize: 11),
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

                  // 3. HISTORY SECTION
                  if (history.isNotEmpty) ...[
                    InkWell(
                      onTap: () => setState(() => _showHistory = !_showHistory),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            Icon(
                              _showHistory ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                              color: Colors.white54,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'PLAYED RECENTLY (${history.length})',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
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

  Widget _buildNowPlayingCard(MusicTrack track, MusicPlayerController controller) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF7C5CFF).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7C5CFF).withValues(alpha: 0.35)),
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
                  style: const TextStyle(
                    color: Colors.white,
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
                    color: Colors.white.withValues(alpha: 0.7),
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
          // Animated Waveform Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C5CFF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  'Playing',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
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
        color: const Color(0xFF141724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
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
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.artist,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
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
              icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white38, size: 18),
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
                child: Icon(Icons.drag_indicator_rounded, color: Colors.white38, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(MusicTrack track, int originalIndex, MusicPlayerController controller) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
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
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.artist,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: MusicHoverable(
          scaleFactor: 1.1,
          child: IconButton(
            icon: const Icon(Icons.replay_rounded, color: Colors.white54, size: 18),
            tooltip: 'Replay now',
            onPressed: () {
              controller.jumpToQueueIndex(originalIndex);
              setState(() {});
            },
          ),
        ),
      ),
    );
  }
}
