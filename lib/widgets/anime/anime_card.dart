import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/design/prism_tokens.dart';

import '../../models/anime/anime_media.dart';
import '../../services/theme/app_theme_service.dart';
import '../common/poster_skeleton.dart';

class AnimeCard extends StatefulWidget {
  final AnimeMedia anime;
  final VoidCallback onTap;
  final double? width;

  const AnimeCard({
    super.key,
    required this.anime,
    required this.onTap,
    this.width,
  });

  @override
  State<AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<AnimeCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : PrismDark.ink;
    final inkMeta = isLight ? PrismLight.inkSoft : PrismDark.inkSoft;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.97 : (_hovered ? 1.045 : 1.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, _hovered ? -6 : 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster Frame
                Expanded(
                  child: _AnimePosterFrame(anime: anime, hovered: _hovered),
                ),

                // Title
                const SizedBox(height: 9),
                Text(
                  anime.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.25,
                    color: ink,
                  ),
                ),

                // Year / Format / Genre
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (anime.seasonYear > 0) ...[
                      Text(
                        '${anime.seasonYear}',
                        style: TextStyle(
                          fontSize: 13,
                          color: inkMeta.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.26),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        anime.genres.isNotEmpty
                            ? anime.genres.first
                            : anime.formattedFormat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: inkMeta.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimePosterFrame extends StatelessWidget {
  final AnimeMedia anime;
  final bool hovered;

  const _AnimePosterFrame({required this.anime, required this.hovered});

  @override
  Widget build(BuildContext context) {
    final posterUrl = anime.coverUrl;
    final hasPoster = posterUrl.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: PrismFrame.poster(
          isLight: AppThemeService.currentPalette.value.isLight,
          hovered: hovered,
          glow: AppThemeService.currentPalette.value.primaryColor,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: DizzyVoid.surface1),

            // Poster Image — P15: own raster boundary (see movie_card).
            if (hasPoster)
              RepaintBoundary(
                child: CachedNetworkImage(
                  imageUrl: posterUrl,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  memCacheWidth: 500,
                  memCacheHeight: 750,
                  maxWidthDiskCache: 500,
                  placeholder: (context, url) => const PosterSkeleton(),
                  errorWidget: (context, url, error) => const MissingPoster(),
                ),
              )
            else
              const MissingPoster(),

            // Vignette Gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.20),
                    ],
                  ),
                ),
              ),
            ),

            // Top Left Rating Badge
            if (anime.averageScore > 0)
              Positioned(
                top: 9,
                left: 9,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: Color(0xFFFFD700),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        anime.formattedScore,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFFD700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Top Right Format Pill
            Positioned(
              top: 9,
              right: 9,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: AppThemeService.currentPalette.value.primaryColor
                      .withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  anime.formattedFormat.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Bottom Overlay with Episode Count
            if (anime.totalEpisodes > 0)
              Positioned(
                bottom: 9,
                left: 9,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${anime.totalEpisodes} EPS',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),

            // Hover Play Glow Icon
            if (hovered)
              Positioned(
                bottom: 9,
                right: 9,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppThemeService.currentPalette.value.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
