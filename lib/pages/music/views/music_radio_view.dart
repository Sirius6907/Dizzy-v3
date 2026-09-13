import 'package:flutter/material.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import '../widgets/music_hoverable.dart';

class MusicRadioView extends StatelessWidget {
  final ScrollController scrollController;
  final Function(String query) onGenreTap;

  const MusicRadioView({
    super.key,
    required this.scrollController,
    required this.onGenreTap,
  });

  @override
  Widget build(BuildContext context) {
    final radioGenres = [
      {'name': 'Pop Radio', 'color': const Color(0xFF7C5CFF), 'query': 'Pop Radio Hits'},
      {'name': 'Rap & Hip-Hop', 'color': const Color(0xFF7850FF), 'query': 'Hip Hop Radio'},
      {'name': 'Rock Mix', 'color': const Color(0xFFF99C00), 'query': 'Rock Radio'},
      {'name': 'Dance & Electro', 'color': const Color(0xFF00D294), 'query': 'Electro Radio'},
      {'name': 'R&B Station', 'color': const Color(0xFFE12AFB), 'query': 'R&B Radio'},
      {'name': 'Lofi & Ambient', 'color': const Color(0xFF00D2EF), 'query': 'Lofi Radio'},
      {'name': 'Heavy Metal Station', 'color': const Color(0xFFFB2C36), 'query': 'Metal Radio'},
      {'name': 'Jazz Club', 'color': const Color(0xFF625FFF), 'query': 'Jazz Radio'},
    ];

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 80, left: 24, right: 24, bottom: 150),
      children: [
        const Text(
          'Radio Stations & Live Streams',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Continuous music channels tuned to your mood.',
          style: TextStyle(color: Color(0xFF9E9EA8), fontSize: 14),
        ),
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.5,
          ),
          itemCount: radioGenres.length,
          itemBuilder: (context, index) {
            final station = radioGenres[index];
            final color = station['color'] as Color;
            return MusicHoverable(
              scaleFactor: 1.04,
              child: GestureDetector(
                onTap: () => onGenreTap(station['query'] as String),
                child: PerformanceLiquidLens(
                  style: PerformanceGlassStyles.menu,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: color.withValues(alpha: 0.20),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.radio_rounded, color: color, size: 28),
                        Text(
                          station['name'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
