import 'package:flutter/material.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_settings.dart';
import '../../../services/music/music_smart_mix_service.dart';
import '../widgets/music_hero_billboard.dart';
import '../widgets/music_trending_artists.dart';
import '../widgets/music_section_rows.dart';
import '../widgets/music_smart_mixes_row.dart';

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

    return RefreshIndicator(
      color: const Color(0xFF7C5CFF),
      backgroundColor: const Color(0xFF151822),
      onRefresh: onRefresh,
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.only(top: 75, bottom: bottomPad),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
          const SizedBox(height: 20),
          FutureBuilder<List<SmartMixPlaylist>>(
            future: MusicSmartMixService.instance.getOrGenerateMixes(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: MusicSmartMixesRow(mixes: snapshot.data!),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          if (trendingArtists.isNotEmpty)
            MusicTrendingArtists(
              artists: trendingArtists,
              onArtistTap: onArtistTap,
            ),
          if (newReleases.isNotEmpty)
            MusicAlbumsRow(
              title: '💿 New Album Releases',
              albums: newReleases,
              onAlbumTap: onAlbumTap,
            ),
          if (curatedPlaylists.isNotEmpty)
            MusicPlaylistsRow(
              title: '🎧 Curated Charts & Mixes',
              playlists: curatedPlaylists,
              onPlaylistTap: onCuratedPlaylistTap,
            ),
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
