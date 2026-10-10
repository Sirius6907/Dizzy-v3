import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../utils/perf/image_caps.dart';

/// Music cover/artwork image with graceful fallback (2026-10-10).
///
/// Every raw `CachedNetworkImage` in music had NO placeholder/errorWidget,
/// so any cache/network hiccup rendered a blank hole (or nothing at all).
/// This wrapper always paints something: a themed loading shimmer while
/// fetching, and a music-note tile on error/empty URL — never blank.
class MusicCoverImage extends StatelessWidget {
  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final bool circular;

  const MusicCoverImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return _fallback();
    final img = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: ImageCaps.kThumb,
      maxWidthDiskCache: ImageCaps.kThumb,
      placeholder: (c, u) => _loading(),
      errorWidget: (c, u, e) => _fallback(),
    );
    if (circular) {
      return ClipOval(child: img);
    }
    return img;
  }

  Widget _loading() => Container(
        width: width,
        height: height,
        color: const Color(0xFF1A1030),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF7C5CFF),
            ),
          ),
        ),
      );

  Widget _fallback() => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          shape: circular ? BoxShape.circle : BoxShape.rectangle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1B4E), Color(0xFF120A24)],
          ),
        ),
        child: Icon(
          Icons.music_note_rounded,
          color: const Color(0xFF7C5CFF).withValues(alpha: 0.7),
          size: (width < height ? width : height) * 0.4,
        ),
      );
}
