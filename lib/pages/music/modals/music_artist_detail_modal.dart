import '../widgets/music_track_row.dart';
import '../widgets/music_album_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../models/music/music_track.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';

class MusicArtistDetailModal extends StatelessWidget {
  final MusicArtistDetails details;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;
  final Function(String) onOpenAlbum;

  const MusicArtistDetailModal({
    super.key,
    required this.details,
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
    required this.onOpenAlbum,
  });

  @override
  Widget build(BuildContext context) {
    final artist = details.artist;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              color: const Color(0xFF0F121C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: artist.pictureUrl,
                        fit: BoxFit.cover,
                        // P12: decode-capped (was full-res).
                        memCacheWidth: ImageCaps.kCardW,
                        maxWidthDiskCache: ImageCaps.kCardW,
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Color(0xFF0F121C),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                        onPressed: onClose,
                      ),
                    ),
                    Positioned(
                      left: 24,
                      bottom: 16,
                      child: Row(
                        children: [
                          Text(
                            artist.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (details.topTracks.isNotEmpty)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7C5CFF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              onPressed: () => onPlayTrack(details.topTracks.first, details.topTracks),
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                              label: const Text('Play All', style: TextStyle(color: Colors.white)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    children: [
                      if (details.topTracks.isNotEmpty) ...[
                        const Text(
                          'Top Songs',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: details.topTracks.length.clamp(0, 10),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final track = details.topTracks[index];
                            return MusicTrackRow(
                              track: track,
                              isPlaying: false,
                              isCurrent: false,
                              onTap: () => onPlayTrack(track, details.topTracks),
                              onMoreTap: () => onAddToPlaylist(track),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (details.albums.isNotEmpty) ...[
                        const Text(
                          'Albums & Discography',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 180,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: details.albums.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              final album = details.albums[index];
                              return MusicAlbumCard(album: album, onTap: () => onOpenAlbum(album.id));
                            },
                          ),
                        ),
                      ],
                    ],
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

