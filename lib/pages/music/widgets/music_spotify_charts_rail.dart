import 'package:flutter/material.dart';

import '../../../design/dizzy_tokens.dart';
import '../../../design/prism_tokens.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../services/music/spotify_charts_service.dart';
import '../../../services/theme/app_theme_service.dart';
import 'music_horizontal_scroll_section.dart';
import 'music_hoverable.dart';

/// Daily-refreshing Spotify chart rails (2026-11-12).
///
/// One compact rail per chart (India daily, India weekly, Global daily,
/// Global weekly). Entries are rank-first tiles instead of cover cards:
/// every track on a chart shares the playlist cover, so fifty identical
/// covers would read as filler. Rank + title + artist is the information
/// the chart actually carries.
///
/// A chart that fails to load is omitted by the service, so an empty
/// snapshot renders nothing — never a placeholder.
class SpotifyChartsRails extends StatelessWidget {
  const SpotifyChartsRails({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SpotifyChart>>(
      future: SpotifyChartsService.instance.fetchAll(),
      builder: (context, snapshot) {
        final charts = snapshot.data;
        if (charts == null || charts.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final chart in charts)
              _ChartRail(key: ValueKey(chart.spec.key), chart: chart),
          ],
        );
      },
    );
  }
}

class _ChartRail extends StatelessWidget {
  final SpotifyChart chart;

  const _ChartRail({super.key, required this.chart});

  @override
  Widget build(BuildContext context) {
    return MusicHorizontalScrollSection(
      title: chart.spec.railTitle,
      height: 76,
      itemCount: chart.tracks.length,
      itemBuilder: (context, index) {
        final track = chart.tracks[index];
        return _ChartEntryTile(
          rank: index + 1,
          track: track,
          onTap: () => MusicPlayerController.instance.playTrack(
            track,
            playlistQueue: chart.tracks,
          ),
        );
      },
    );
  }
}

class _ChartEntryTile extends StatelessWidget {
  final int rank;
  final MusicTrack track;
  final VoidCallback onTap;

  const _ChartEntryTile({
    required this.rank,
    required this.track,
    required this.onTap,
  });

  String get _duration {
    final s = track.durationSeconds;
    if (s <= 0) return '';
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    return MusicHoverable(
      scaleFactor: 1.03,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(
            horizontal: PrismSpace.md,
            vertical: PrismSpace.sm,
          ),
          decoration: BoxDecoration(
            color: palette.cardBackgroundColor,
            borderRadius: BorderRadius.circular(DizzyRadius.lg),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PrismInk.faint(isLight),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: PrismSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        color: PrismInk.primary(isLight),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      style: TextStyle(
                        color: PrismInk.faint(isLight),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_duration.isNotEmpty) ...[
                const SizedBox(width: PrismSpace.sm),
                Text(
                  _duration,
                  style: TextStyle(color: PrismInk.faint(isLight), fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
