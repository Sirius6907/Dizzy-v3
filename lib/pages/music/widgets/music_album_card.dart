import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../models/music/music_track.dart';
import '../../../utils/perf/image_caps.dart';
import 'music_hoverable.dart';

class MusicAlbumCard extends StatelessWidget {
  final MusicAlbum album;
  final VoidCallback onTap;

  const MusicAlbumCard({
    super.key,
    required this.album,
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
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: album.coverUrl,
                  width: 145,
                  height: 145,
                  fit: BoxFit.cover,
                  // P12: decode-capped (was full-res).
                  memCacheWidth: ImageCaps.kThumb,
                  maxWidthDiskCache: ImageCaps.kThumb,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
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
                album.artistName,
                style: const TextStyle(
                  color: Colors.white54,
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

