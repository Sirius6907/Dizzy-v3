import '../../../services/music/music_download_service.dart';
import '../widgets/music_track_row.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';
import '../../../models/music/music_track.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';

class MusicAlbumDetailModal extends StatelessWidget {
  final MusicAlbumDetails details;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;

  const MusicAlbumDetailModal({
    super.key,
    required this.details,
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final album = details.album;
    final tracks = details.tracks;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = PrismInk.primary(isLight);
    final inkFaint = PrismInk.faint(isLight);

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              gradient: PrismShadows.surfaceGradient(isLight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: PrismShadows.floating(isLight: isLight),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: album.coverUrl,
                        width: isMobile ? 80 : 120,
                        height: isMobile ? 80 : 120,
                        fit: BoxFit.cover,
                        // P12: decode-capped (was full-res).
                        memCacheWidth: ImageCaps.kThumb,
                        maxWidthDiskCache: ImageCaps.kThumb,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.title,
                            style: TextStyle(
                              color: ink,
                              fontSize: isMobile ? 18 : 22,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            album.artistName,
                            style: const TextStyle(
                              color: Color(0xFF7C5CFF),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${tracks.length} tracks • ${album.releaseDate}',
                            style: TextStyle(color: inkFaint, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          if (tracks.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C5CFF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () =>
                                      onPlayTrack(tracks.first, tracks),
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Play Album',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: ink,
                                    side: BorderSide(
                                      color: isLight
                                          ? PrismLight.borderSubtle
                                          : Colors.white.withValues(alpha: 0.2),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () {
                                    MusicDownloadService.instance.queueTracks(
                                      tracks,
                                      collectionName: album.title,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Added ${tracks.length} tracks from "${album.title}" to download queue',
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Download Album'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: PrismInk.soft(isLight)),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(
                  color: isLight
                      ? PrismLight.borderSubtle
                      : Colors.white10,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      return MusicTrackRow(
                        track: track,
                        isPlaying: false,
                        isCurrent: false,
                        onTap: () => onPlayTrack(track, tracks),
                        onMoreTap: () => onAddToPlaylist(track),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
