import 'package:flutter/material.dart';
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
    final genres = [
      {'title': 'Pop Hits', 'color': const Color(0xFF7C5CFF), 'query': 'Pop Hits'},
      {'title': 'Hip-Hop & Rap', 'color': const Color(0xFF7850FF), 'query': 'Hip-Hop'},
      {'title': 'Electronic & EDM', 'color': const Color(0xFF00D294), 'query': 'EDM Dance'},
      {'title': 'Chill Lofi Beats', 'color': const Color(0xFF00D2EF), 'query': 'Chill Lofi'},
      {'title': 'Rock Classics', 'color': const Color(0xFFF99C00), 'query': 'Rock Classics'},
      {'title': 'R&B & Soul', 'color': const Color(0xFFE12AFB), 'query': 'R&B Soul'},
      {'title': 'Soundtracks & Gaming', 'color': const Color(0xFFFF6568), 'query': 'Soundtracks'},
      {'title': 'Heavy Metal', 'color': const Color(0xFFFB2C36), 'query': 'Heavy Metal'},
      {'title': 'Jazz & Blues', 'color': const Color(0xFF625FFF), 'query': 'Jazz Blues'},
      {'title': 'Classical Piano', 'color': const Color(0xFFFAC800), 'query': 'Classical Piano'},
    ];

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 80, left: 24, right: 24, bottom: 150),
      children: [
        const Text(
          'Browse Moods & Genres',
          style: TextStyle(
            color: Colors.white,
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
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        g['title'] as String,
                        style: const TextStyle(
                          color: Colors.white,
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
