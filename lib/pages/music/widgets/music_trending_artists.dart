import 'package:flutter/material.dart';
import '../../../design/prism_tokens.dart';
import '../../../models/music/music_track.dart';
import '../../../services/theme/app_theme_service.dart';
import 'music_cover_image.dart';
import 'music_hoverable.dart';
import 'music_horizontal_scroll_section.dart';

class MusicTrendingArtists extends StatelessWidget {
  final List<MusicArtist> artists;
  final Function(MusicArtist) onArtistTap;

  const MusicTrendingArtists({
    super.key,
    required this.artists,
    required this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    return MusicHorizontalScrollSection(
      title: '🌟 Trending Artists',
      height: 130,
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return MusicHoverable(
          scaleFactor: 1.06,
          child: GestureDetector(
            onTap: () => onArtistTap(artist),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF7C5CFF).withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: MusicCoverImage(
                    imageUrl: artist.pictureUrl,
                    width: 78,
                    height: 78,
                    circular: true,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 85,
                  child: Text(
                    artist.name,
                    style: TextStyle(
                      color: PrismInk.primary(
                        AppThemeService.currentPalette.value.isLight,
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
