import 'package:flutter/material.dart';

import '../../design/dizzy_tokens.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/home/genre_preference_service.dart';
import '../../services/stats/watch_stats.dart';
import '../../services/stats/wrap_copy.dart';
import '../../services/theme/app_theme_service.dart';

/// F5 (v1.1.9): "My Dizzy Wrap" — Spotify-Wrapped style stats page.
/// Entry: Settings + profile avatar tap. All local data, no network.
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final items = ContinueWatchingService.activeItems.value;
    final stats = WatchStats.aggregate(items);
    final genres = GenrePreferenceService.scores.value.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topGenres = genres.take(3).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Dizzy Wrap',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              _heroCard(palette, stats),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _statTile(palette, Icons.movie_rounded, '${stats.titlesCount}',
                      'Titles watching'),
                  _statTile(palette, Icons.check_circle_rounded,
                      '${stats.episodesFinished}', 'Finished (90%+)'),
                  _statTile(palette, Icons.local_fire_department_rounded,
                      '${stats.currentStreakDays}d',
                      WrapCopy.streakLine(stats.currentStreakDays)),
                  _statTile(
                      palette,
                      Icons.tv_rounded,
                      '${stats.typeCounts['series'] ?? 0} / ${stats.typeCounts['movie'] ?? 0}',
                      'Series / Movies'),
                ],
              ),
              const SizedBox(height: 12),
              _genreCard(palette, topGenres),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard(dynamic palette, WatchStats stats) {
    // Polish P19: editorial cheer under the big number + tokens.
    final cheer = WrapCopy.hoursCheer(stats.minutesWatched);
    return Semantics(
      label: 'Total watch time ${stats.hoursLabel}. $cheer',
      child: Container(
      padding: const EdgeInsets.all(DizzySpace.lg - 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.primaryColor.withValues(alpha: 0.25),
            const Color(0xFF00E5FF).withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: DizzyRadius.xlAll,
        border: Border.all(
          color: palette.primaryColor.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⏱️ Total watch time',
              style: TextStyle(
                  color: Colors.white70, fontSize: DizzyType.body)),
          const SizedBox(height: DizzySpace.xxs),
          Text(
            stats.hoursLabel,
            style: const TextStyle(
                fontSize: DizzyType.display + 12,
                fontWeight: DizzyType.wBold,
                color: Colors.white),
          ),
          const SizedBox(height: DizzySpace.xxs),
          Text(cheer,
              style: const TextStyle(
                  color: Colors.white60, fontSize: DizzyType.caption)),
        ],
      ),
    ),
    );
  }

  Widget _statTile(
      dynamic palette, IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: palette.primaryColor, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _genreCard(
      dynamic palette, List<MapEntry<String, double>> topGenres) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🎭 Your top genres',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 12),
          if (topGenres.isEmpty)
            Text(
              WrapCopy.emptyTaste(),
              style: const TextStyle(
                  color: Colors.white60, fontSize: DizzyType.body - 1),
            )
          else
            for (final g in topGenres)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.key.isEmpty
                            ? 'Unknown'
                            : '${g.key[0].toUpperCase()}${g.key.substring(1)}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: g.value.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.10),
                          valueColor: AlwaysStoppedAnimation(
                              palette.primaryColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
