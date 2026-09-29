import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/movie/movie.dart';
import '../../../models/movie/movie_detail.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/home/home_page_settings.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../utils/navigation/route_transitions.dart';
import '../../details/details_page.dart';
import 'home_hero_title.dart';

class HomeHeroSlide extends StatelessWidget {
  final Movie movie;
  final MovieDetail? detail;
  final double screenWidth;

  const HomeHeroSlide({super.key,
    required this.movie,
    required this.detail,
    required this.screenWidth,
  });

  void _openDetails(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final offset = box?.localToGlobal(box.size.center(Offset.zero));
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: DetailsPage(movie: movie),
        tapPosition: offset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = screenWidth < 600;
    final palette = AppThemeService.currentPalette.value;
    final heroStyle = HomePageSettings.heroStyle.value;

    final imageUrl = detail?.background ?? movie.poster;
    final year = detail?.year ?? movie.year;
    final rating = detail?.imdbRating;
    final description = detail?.description;
    final genres = detail?.genres ?? const <String>[];
    final logo = detail?.logo;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background ──
        if (imageUrl != null)
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.15),
            filterQuality: FilterQuality.medium,
            // Polish P14: backdrop cap 960 (P23 contract, 3GB safe).
            memCacheWidth: ImageCaps.kBackdrop,
            maxWidthDiskCache: ImageCaps.kBackdrop,
            fadeInDuration: const Duration(milliseconds: 300),
            placeholder: (_, __) => const ColoredBox(color: Color(0xFF151822)),
            errorWidget: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF151822)),
          )
        else
          const ColoredBox(color: Color(0xFF151822)),

        // Left horizontal wash for cinematic readability
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0.0, 0.38, 0.85],
                colors: [
                  palette.scaffoldBackgroundColor.withValues(alpha: 0.95),
                  palette.scaffoldBackgroundColor.withValues(alpha: 0.70),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Top gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [
                  palette.scaffoldBackgroundColor.withValues(alpha: 0.85),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Bottom gradient (fades seamlessly into the body background)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: const [0.0, 0.28, 0.70],
                colors: [
                  palette.scaffoldBackgroundColor,
                  palette.scaffoldBackgroundColor.withValues(alpha: 0.85),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ── Content overlay ──
        Positioned(
          left: isCompact ? 20 : 48,
          right: isCompact ? 20 : 48,
          bottom: isCompact
              ? (heroStyle == HeroStyle.minimalist ? 18 : 32)
              : (heroStyle == HeroStyle.minimalist ? 28 : 50),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isCompact ? double.infinity : 680.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rating + year + runtime
                  Row(
                    children: [
                      if (rating != null && rating.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFFD700,
                            ).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: const Color(
                                0xFFFFD700,
                              ).withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: Color(0xFFFFD700),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rating,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFFD700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (year != null && year.isNotEmpty)
                        Text(
                          year,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: Colors.white.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (detail?.runtime != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.circle,
                            size: 4,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        Text(
                          detail!.runtime!,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: Colors.white.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),

                  SizedBox(height: heroStyle == HeroStyle.minimalist ? 8 : 14),

                  // Title / clearlogo
                  HomeHeroTitle(
                    title: movie.name,
                    logoUrl: logo,
                    isCompact: isCompact || heroStyle == HeroStyle.minimalist,
                  ),

                  // Description (Hidden in Minimalist, 1-line in Compact, 3-line in Immersive)
                  if (heroStyle != HeroStyle.minimalist &&
                      description != null &&
                      description.isNotEmpty) ...[
                    SizedBox(height: isCompact ? 10 : 14),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isCompact ? double.infinity : 560,
                      ),
                      child: Text(
                        description,
                        maxLines: heroStyle == HeroStyle.compact
                            ? 1
                            : (isCompact ? 2 : 3),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isCompact ? 14.0 : 15.0,
                          color: Colors.white.withValues(alpha: 0.65),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],

                  // Genre chips (Immersive only)
                  if (heroStyle == HeroStyle.immersive &&
                      genres.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: genres.take(4).map((genre) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            genre,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.70),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  // Action buttons
                  SizedBox(
                    height: heroStyle == HeroStyle.minimalist
                        ? 12
                        : (isCompact ? 18 : 24),
                  ),
                  Row(
                    children: [
                      Builder(
                        builder: (context) {
                          return ElevatedButton.icon(
                            onPressed: () => _openDetails(context),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 22,
                            ),
                            label: const Text(
                              'Watch Now',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: palette.primaryColor,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 16 : 24,
                                vertical: isCompact ? 10 : 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 4,
                              shadowColor: Colors.black.withValues(alpha: 0.35),
                            ),
                          );
                        },
                      ),
                      if (heroStyle != HeroStyle.minimalist) ...[
                        SizedBox(width: isCompact ? 8 : 12),
                        Builder(
                          builder: (context) {
                            return OutlinedButton.icon(
                              onPressed: () => _openDetails(context),
                              icon: Icon(
                                Icons.info_outline_rounded,
                                size: isCompact ? 18 : 20,
                                color: Colors.white.withValues(alpha: 0.80),
                              ),
                              label: Text(
                                'Details',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: isCompact ? 13.5 : 15,
                                  color: Colors.white.withValues(alpha: 0.80),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 14 : 20,
                                  vertical: isCompact ? 10 : 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1.2,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Title — clearlogo when available, crossfaded text fallback otherwise.
// ─────────────────────────────────────────────────────────────────────────────

