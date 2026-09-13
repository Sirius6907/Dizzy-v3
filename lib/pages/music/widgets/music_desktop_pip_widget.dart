import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../../../services/music/music_mini_pip_service.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../utils/perf/image_caps.dart';
import 'music_dynamic_canvas_background.dart';

class MusicDesktopPipWidget extends StatelessWidget {
  const MusicDesktopPipWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayerController.instance;
    final track = controller.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D101A),
        body: Center(
          child: IconButton(
            icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
            onPressed: () => MusicMiniPipService.instance.exitMiniPip(),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0D14),
      body: MusicDynamicCanvasBackground(
        track: track,
        child: Column(
          children: [
            // Top Window Drag Region & Restore Button
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) {
                if (MusicMiniPipService.instance.isDesktop) {
                  windowManager.startDragging();
                }
              },
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.black.withValues(alpha: 0.35),
                child: Row(
                  children: [
                    const Icon(Icons.drag_handle_rounded, color: Colors.white30, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'Dizzy Mini Player',
                      style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        MusicMiniPipService.instance.exitMiniPip();
                      },
                      child: const Tooltip(
                        message: 'Restore window',
                        child: Icon(Icons.open_in_full_rounded, color: Colors.white70, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Main Player Bar
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    // Artwork Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        memCacheWidth: ImageCaps.kThumb,
                        maxWidthDiskCache: ImageCaps.kThumb,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Info Column
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          // Mini linear progress
                          AnimatedBuilder(
                            animation: controller,
                            builder: (context, _) {
                              final pos = controller.position.inMilliseconds.toDouble();
                              final dur = controller.duration.inMilliseconds.toDouble();
                              final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 3,
                                  backgroundColor: Colors.white12,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C5CFF)),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Media Controls
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70, size: 22),
                          onPressed: controller.playPrevious,
                        ),
                        IconButton(
                          icon: Icon(
                            controller.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                            color: const Color(0xFF7C5CFF),
                            size: 32,
                          ),
                          onPressed: controller.togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 22),
                          onPressed: controller.playNext,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
