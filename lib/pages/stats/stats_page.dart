import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_tokens.dart';

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
    final week = WatchStats.weekly(items);
    final genres = GenrePreferenceService.scores.value.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topGenres = genres.take(3).toList();

    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
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
              _weekCard(palette, week),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _statTile(
                        palette,
                        Icons.movie_rounded,
                        '${stats.titlesCount}',
                        'Titles watching',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statTile(
                        palette,
                        Icons.check_circle_rounded,
                        '${stats.episodesFinished}',
                        'Finished (90%+)',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _statTile(
                        palette,
                        Icons.local_fire_department_rounded,
                        '${stats.currentStreakDays}d',
                        WrapCopy.streakLine(stats.currentStreakDays),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statTile(
                        palette,
                        Icons.tv_rounded,
                        '${stats.typeCounts['series'] ?? 0} / ${stats.typeCounts['movie'] ?? 0}',
                        'Series / Movies',
                      ),
                    ),
                  ],
                ),
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
    final isLight = palette.isLight as bool;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white70;
    return Semantics(
      label: 'Total watch time ${stats.hoursLabel}. $cheer',
      child: Container(
        padding: const EdgeInsets.all(DizzySpace.lg - 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.primaryColor.withValues(alpha: isLight ? 0.14 : 0.25),
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
            Text(
              '⏱️ Total watch time',
              style: TextStyle(color: inkSoft, fontSize: DizzyType.body),
            ),
            const SizedBox(height: DizzySpace.xxs),
            Text(
              stats.hoursLabel,
              style: TextStyle(
                fontSize: DizzyType.display + 12,
                fontWeight: DizzyType.wBold,
                color: ink,
              ),
            ),
            const SizedBox(height: DizzySpace.xxs),
            Text(
              cheer,
              style: TextStyle(color: inkSoft, fontSize: DizzyType.caption),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekCard(dynamic palette, WatchStats week) {
    final isLight = palette.isLight as bool;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final line = WrapCopy.weekLine(
      week.titlesCount,
      week.minutesWatched,
      week.episodesFinished,
    );
    return Semantics(
      label: 'This week in Dizzy. $line',
      child: Container(
        padding: const EdgeInsets.all(DizzySpace.md),
        decoration: BoxDecoration(
          color: isLight ? PrismLight.raisedTop : PrismDark.raised,
          borderRadius: DizzyRadius.lgAll,
          border: Border.all(
            color: isLight
                ? PrismLight.borderSubtle
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  color: palette.primaryColor,
                  size: 18,
                ),
                const SizedBox(width: DizzySpace.xs),
                Text(
                  'This week',
                  style: TextStyle(
                    fontSize: DizzyType.subtitle,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DizzySpace.xxs),
            Text(
              line,
              style: TextStyle(color: inkSoft, fontSize: DizzyType.body),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(dynamic palette, IconData icon, String value, String label) {
    final isLight = palette.isLight as bool;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLight ? PrismLight.raisedTop : PrismDark.raised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight
              ? PrismLight.borderSubtle
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: palette.primaryColor, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          Text(label, style: TextStyle(color: inkSoft, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _genreCard(dynamic palette, List<MapEntry<String, double>> topGenres) {
    final isLight = palette.isLight as bool;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isLight ? PrismLight.raisedTop : PrismDark.raised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight
              ? PrismLight.borderSubtle
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎭 Your top genres',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 12),
          if (topGenres.isEmpty)
            Text(
              WrapCopy.emptyTaste(),
              style: TextStyle(color: inkSoft, fontSize: DizzyType.body - 1),
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
                        style: TextStyle(color: ink, fontSize: 14),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: g.value.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: isLight
                              ? PrismLight.raisedBottom
                              : Colors.white.withValues(alpha: 0.10),
                          valueColor: AlwaysStoppedAnimation(
                            palette.primaryColor,
                          ),
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
