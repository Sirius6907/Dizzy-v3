import 'package:flutter/material.dart';
import '../../../design/prism_shadows.dart';
import '../../../design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../models/music/music_track.dart';
import 'music_cover_image.dart';
import 'music_hoverable.dart';

class MusicPlaylistCard extends StatelessWidget {
  final MusicPlaylist playlist;
  final VoidCallback onTap;

  const MusicPlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MusicHoverable(
      scaleFactor: 1.05,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 145,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: PrismFrame.poster(
                    isLight: AppThemeService.currentPalette.value.isLight,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MusicCoverImage(
                    imageUrl: playlist.coverUrl,
                    width: 145,
                    height: 145,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                playlist.title,
                style: TextStyle(
                  color: PrismInk.primary(
                    AppThemeService.currentPalette.value.isLight,
                  ),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${playlist.trackCount} tracks',
                style: TextStyle(
                  color: PrismInk.faint(
                    AppThemeService.currentPalette.value.isLight,
                  ),
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
