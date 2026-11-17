import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_mood_filter.dart';
import '../../../services/music/music_onboarding_service.dart';
import '../../../services/music/music_settings.dart';
import '../../../services/music/music_smart_mix_service.dart';
import '../../../services/theme/app_theme_service.dart';
import '../widgets/music_hero_billboard.dart';
import '../widgets/music_trending_artists.dart';
import '../widgets/music_section_rows.dart';
import '../widgets/music_smart_mixes_row.dart';
import '../widgets/music_spotify_charts_rail.dart';

/// Music home (restyle 2026-11-09): flat props list with a mood selector
/// row on top. The mood chip row writes to [MusicSettings.selectedMood]
/// (persisted) and the smart-mixes rail reads it back — pick a mood and
/// the rail regenerates for that vibe. No new theme pickers; everything
/// colors off the active palette + Prism tokens.
class MusicHomeView extends StatelessWidget {
  final ScrollController scrollController;
  final bool isDesktop;
  final Future<void> Function() onRefresh;
  final MusicTrack? heroTrack;
  final List<MusicArtist> trendingArtists;
  final List<MusicAlbum> newReleases;
  final List<MusicPlaylist> curatedPlaylists;
  final Map<String, List<MusicTrack>> sections;
  final Function(MusicArtist) onArtistTap;
  final Function(MusicAlbum) onAlbumTap;
  final Function(MusicPlaylist) onCuratedPlaylistTap;
  final Function(MusicTrack) onAddToPlaylist;
  final Function(MusicTrack, List<MusicTrack>?) onPlayTrack;
  final Function(MusicTrack) onToggleSave;
  final bool Function(String) isTrackSaved;

  const MusicHomeView({
    super.key,
    required this.scrollController,
    required this.isDesktop,
    required this.onRefresh,
    required this.heroTrack,
    required this.trendingArtists,
    required this.newReleases,
    required this.curatedPlaylists,
    required this.sections,
    required this.onArtistTap,
    required this.onAlbumTap,
    required this.onCuratedPlaylistTap,
    required this.onAddToPlaylist,
    required this.onPlayTrack,
    required this.onToggleSave,
    required this.isTrackSaved,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = isDesktop ? 120.0 : 160.0;
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final accent = palette.primaryColor;

    return RefreshIndicator(
      color: accent,
      backgroundColor: palette.cardBackgroundColor,
      onRefresh: onRefresh,
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.only(top: 75, bottom: bottomPad),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: [
          if (MusicSettings.enableSpotlight.value && heroTrack != null)
            MusicHeroBillboard(
              track: heroTrack!,
              onPlayTap: () => onPlayTrack(
                heroTrack!,
                sections.values.isNotEmpty ? sections.values.first : null,
              ),
              onSaveTap: () => onToggleSave(heroTrack!),
              onAddToPlaylistTap: () => onAddToPlaylist(heroTrack!),
              isSaved: isTrackSaved(heroTrack!.id),
            ),
          const SizedBox(height: PrismSpace.lg),
          ValueListenableBuilder<MusicMood>(
            valueListenable: MusicSettings.selectedMood,
            builder: (context, mood, _) {
              return MusicMoodChips(
                current: mood,
                isLight: isLight,
                accent: accent,
                onPick: MusicSettings.setSelectedMood,
              );
            },
          ),
          const SizedBox(height: PrismSpace.sm),
          ValueListenableBuilder<MusicMood>(
            valueListenable: MusicSettings.selectedMood,
            builder: (context, mood, _) {
              return FutureBuilder<List<SmartMixPlaylist>>(
                // Cache is keyed by mood inside the service, so repeated
                // chips only cost one generation per mood.
                future: MusicSmartMixService.instance
                    .getOrGenerateMixes(mood: mood),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return Padding(
                      padding:
                          const EdgeInsets.only(bottom: PrismSpace.xxl),
                      child: MusicSmartMixesRow(mixes: snapshot.data!),
                    );
                  }
                  return const SizedBox.shrink();
                },
              );
            },
          ),
          if (trendingArtists.isNotEmpty)
            // Part C: onboarded users with a vibe get their own row
            // ('⭐ Your Artists', favorites lead — ordering lives in
            // fetchTrendingArtists); everyone else keeps global trending.
            ValueListenableBuilder<bool>(
              valueListenable: MusicOnboardingService.isDone,
              builder: (context, done, _) {
                return MusicTrendingArtists(
                  title: done && MusicOnboardingService.hasSignal
                      ? '⭐ Your Artists'
                      : '🌟 Trending Artists',
                  artists: trendingArtists,
                  onArtistTap: onArtistTap,
                );
              },
            ),
          if (newReleases.isNotEmpty)
            MusicAlbumsRow(
              title: 'Albums for your taste',
              albums: newReleases,
              onAlbumTap: onAlbumTap,
            ),
          if (curatedPlaylists.isNotEmpty)
            MusicPlaylistsRow(
              title: '🎧 Curated Charts & Mixes',
              playlists: curatedPlaylists,
              onPlaylistTap: onCuratedPlaylistTap,
            ),
          const SpotifyChartsRails(),
          for (final entry in sections.entries)
            MusicCategorySlider(
              title: entry.key,
              tracks: entry.value,
              onAddToPlaylist: onAddToPlaylist,
            ),
        ],
      ),
    );
  }
}

/// Mood selector: one horizontal chip rail, two themes only. Selected chip
/// is accent-filled; everything else is a flat card surface with ink text.
class MusicMoodChips extends StatelessWidget {
  final MusicMood current;
  final bool isLight;
  final Color accent;
  final ValueChanged<MusicMood> onPick;

  const MusicMoodChips({
    super.key,
    required this.current,
    required this.isLight,
    required this.accent,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: PrismSpace.xl),
        scrollDirection: Axis.horizontal,
        itemCount: MusicMood.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: PrismSpace.xxs),
        itemBuilder: (context, index) {
          final mood = MusicMood.values[index];
          final selected = mood == current;
          final label = mood.emoji.isEmpty
              ? mood.label
              : '${mood.emoji} ${mood.label}';

          return AnimatedContainer(
            duration: PrismMotion.standard,
            curve: PrismMotion.curve,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(PrismRadius.pill),
                onTap: () => onPick(selected ? MusicMood.any : mood),
                child: AnimatedContainer(
                  duration: PrismMotion.standard,
                  curve: PrismMotion.curve,
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrismSpace.sm,
                    vertical: PrismSpace.xxs,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PrismRadius.pill),
                    color: selected
                        ? accent
                        : AppThemeService.currentPalette.value
                            .cardBackgroundColor,
                    border: Border.all(
                      color: selected
                          ? Colors.transparent
                          : isLight
                              ? PrismLight.borderSubtle
                              : PrismDark.borderSubtle,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: PrismType.caption,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      // On the accent fill copy is the on-accent token;
                      // elsewhere it's page ink.
                      color: selected
                          ? PrismAccent.onAccent
                          : PrismInk.primary(isLight),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
