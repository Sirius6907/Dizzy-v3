import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../design/dizzy_tactile.dart';
import '../../../design/dizzy_tokens.dart';
import '../../../models/music/music_track.dart';
import '../../../utils/perf/image_caps.dart';
import 'music_hoverable.dart';

class MusicHeroBillboard extends StatelessWidget {
  final MusicTrack track;
  final VoidCallback onPlayTap;
  final VoidCallback onSaveTap;
  final VoidCallback onAddToPlaylistTap;
  final bool isSaved;

  const MusicHeroBillboard({
    super.key,
    required this.track,
    required this.onPlayTap,
    required this.onSaveTap,
    required this.onAddToPlaylistTap,
    required this.isSaved,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      height: isMobile ? 190 : 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DizzyRadius.xl),
        boxShadow: [
          BoxShadow(
            color: DizzyGlow.violet.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DizzyRadius.xl),
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: track.coverUrl,
                fit: BoxFit.cover,
                // P12: decode-capped (was full-res).
                memCacheWidth: ImageCaps.kCardW,
                maxWidthDiskCache: ImageCaps.kCardW,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      DizzyVoid.obsidian.withValues(alpha: 0.94),
                      DizzyVoid.obsidian.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(isMobile ? 18.0 : 28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: DizzyGlow.violet,
                      borderRadius: BorderRadius.circular(DizzyRadius.md),
                    ),
                    child: const Text(
                      'TOP CHART HIT',
                      style: TextStyle(
                        color: DizzyVoid.bone,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    track.title,
                    style: TextStyle(
                      color: DizzyVoid.bone,
                      fontSize: isMobile ? 20 : 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist,
                    style: TextStyle(
                      color: DizzyVoid.ash,
                      fontSize: isMobile ? 13 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isMobile ? 14 : 20),
                  Row(
                    children: [
                      MusicHoverable(
                        scaleFactor: 1.06,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DizzyGlow.violet,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(DizzyRadius.xl),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 16 : 20,
                              vertical: isMobile ? 10 : 12,
                            ),
                          ),
                          onPressed: onPlayTap,
                          icon: const Icon(Icons.play_arrow_rounded, color: DizzyVoid.bone),
                          label: const Text(
                            'Play Now',
                            style: TextStyle(color: DizzyVoid.bone, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      MusicHoverable(
                        scaleFactor: 1.1,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: DizzyVoid.surface2,
                          ),
                          icon: Icon(
                            isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isSaved ? DizzyGlow.ember : DizzyVoid.bone,
                          ),
                          onPressed: onSaveTap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      MusicHoverable(
                        scaleFactor: 1.1,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: DizzyVoid.surface2,
                          ),
                          icon: const Icon(Icons.playlist_add_rounded, color: DizzyVoid.bone),
                          onPressed: onAddToPlaylistTap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

