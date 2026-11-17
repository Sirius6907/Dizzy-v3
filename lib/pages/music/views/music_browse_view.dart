import 'package:flutter/material.dart';
import '../../../design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import '../widgets/music_hoverable.dart';

class MusicBrowseView extends StatelessWidget {
  final ScrollController scrollController;
  final Function(String query) onGenreTap;

  const MusicBrowseView({
    super.key,
    required this.scrollController,
    required this.onGenreTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final genres = [
      {
        'title': 'Bollywood Romance',
        // Content hues (genre identity), not theme chrome — palette-invariant.
        'color': const Color(0xFF9333EA),
        'query': 'Romantic Bollywood Hits',
      },
      {
        'title': 'Dance & Party',
        'color': const Color(0xFF6366F1),
        'query': 'Bollywood Dance',
      },
      {
        'title': 'Mashup & Remix',
        'color': const Color(0xFF00D294),
        'query': 'Bollywood Mashup',
      },
      {
        'title': 'Punjabi Party',
        'color': const Color(0xFF00D2EF),
        'query': 'Punjabi Hits',
      },
      {
        'title': 'Desi Hip-Hop',
        'color': const Color(0xFFF99C00),
        'query': 'Desi Hip Hop',
      },
      {
        'title': 'Indie & Acoustic',
        'color': const Color(0xFFE12AFB),
        'query': 'Indie Acoustic',
      },
      {
        'title': 'Ollywood DJ Mix',
        'color': const Color(0xFFFF6568),
        'query': 'Odia Hits',
      },
      {
        'title': 'Lofi Nights',
        'color': const Color(0xFFFB2C36),
        'query': 'Bollywood LoFi',
      },
      {
        'title': 'Sad & Slow Reverb',
        'color': const Color(0xFF625FFF),
        'query': 'Slowed Reverb Bollywood',
      },
      {
        'title': '90s Evergreen',
        'color': const Color(0xFFFAC800),
        'query': '90s Hindi Classics',
      },
    ];

    return ListView(
      controller: scrollController,
      // Header (58px + status inset) floats over the list; start below it.
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 150).copyWith(
        top: 72 + MediaQuery.paddingOf(context).top,
      ),
      children: [
        Text(
          'Browse Moods & Genres',
          style: TextStyle(
            color: PrismInk.primary(
              AppThemeService.currentPalette.value.isLight,
            ),
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.6,
          ),
          itemCount: genres.length,
          itemBuilder: (context, index) {
            final g = genres[index];
            final color = g['color'] as Color;
            return MusicHoverable(
              scaleFactor: 1.04,
              child: GestureDetector(
                onTap: () => onGenreTap(g['query'] as String),
                child: PerformanceLiquidLens(
                  style: PerformanceGlassStyles.menu,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withValues(alpha: 0.85),
                          color.withValues(alpha: 0.40),
                        ],
                      ),
                      border: Border.all(
                        color: isLight
                            ? PrismLight.borderSubtle
                            : PrismDark.borderSubtle,
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        g['title'] as String,
                        style: TextStyle(
                          // Saturated tiles: pick ink by tile brightness so
                          // the label survives pale yellows and deep violets.
                          color: color.computeLuminance() > 0.5
                              ? PrismLight.ink
                              : PrismDark.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
