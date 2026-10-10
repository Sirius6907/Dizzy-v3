import 'package:flutter/material.dart';
import '../../../design/dizzy_tactile.dart';
import '../../../design/dizzy_tokens.dart';
import '../../../models/music/music_track.dart';
import 'music_cover_image.dart';
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
                borderRadius: BorderRadius.circular(DizzyRadius.xl),
                child: MusicCoverImage(
                  imageUrl: album.coverUrl,
                  width: 145,
                  height: 145,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
                style: const TextStyle(
                  color: DizzyVoid.bone,
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
                  color: DizzyVoid.ash,
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

