import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../services/music/music_smart_mix_service.dart';
import '../../../utils/perf/image_caps.dart';
import 'music_hoverable.dart';

class MusicSmartMixesRow extends StatelessWidget {
  final List<SmartMixPlaylist> mixes;

  const MusicSmartMixesRow({
    super.key,
    required this.mixes,
  });

  @override
  Widget build(BuildContext context) {
    if (mixes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFF1DB954), size: 20),
              SizedBox(width: 8),
              Text(
                'Made For You',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              Spacer(),
              Text(
                'Smart Mixes',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: mixes.length,
            itemBuilder: (context, index) {
              final mix = mixes[index];
              return _buildMixCard(context, mix);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMixCard(BuildContext context, SmartMixPlaylist mix) {
    return Container(
      width: 165,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: MusicHoverable(
        scaleFactor: 1.04,
        child: InkWell(
          onTap: () => _playMix(mix),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141724),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Cover Art Box with Spotify-style Corner Gradient
                Stack(
                  children: [
                    Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [mix.gradientStart, mix.gradientEnd],
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: mix.primaryCoverUrl.isNotEmpty
                            ? Opacity(
                                opacity: 0.35,
                                child: CachedNetworkImage(
                                  imageUrl: mix.primaryCoverUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth: ImageCaps.kThumb,
                                  maxWidthDiskCache: ImageCaps.kThumb,
                                ),
                              )
                            : null,
                      ),
                    ),
                    // Large bold title on top of cover
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: Text(
                        mix.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                      ),
                    ),
                    // Floating Spotify Green/Accent Play Button
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: mix.gradientStart,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  mix.description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _playMix(SmartMixPlaylist mix) {
    if (mix.tracks.isEmpty) return;
    HapticFeedback.selectionClick();
    MusicPlayerController.instance.playTrack(
      mix.tracks.first,
      playlistQueue: mix.tracks,
    );
  }
}
