import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../models/music/music_track.dart';
import '../../../utils/perf/image_caps.dart';
import '../widgets/music_card_sizing.dart';
import '../widgets/music_hoverable.dart';
import '../widgets/music_track_row.dart';
import '../widgets/music_album_card.dart';
import '../widgets/music_playlist_card.dart';

class MusicSearchView extends StatelessWidget {
  final ScrollController scrollController;
  final MusicSearchData searchData;
  final bool isSearching;
  final String activeQuery;
  final String selectedFilter;
  final Function(String) onFilterSelected;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;
  final Function(String) onOpenArtistModal;
  final Function(String) onOpenAlbumModal;
  final Function(String) onOpenCuratedPlaylistModal;
  final MusicTrack? currentPlayingTrack;
  final bool isPlaying;

  const MusicSearchView({
    super.key,
    required this.scrollController,
    required this.searchData,
    required this.isSearching,
    required this.activeQuery,
    required this.selectedFilter,
    required this.onFilterSelected,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
    required this.onOpenArtistModal,
    required this.onOpenAlbumModal,
    required this.onOpenCuratedPlaylistModal,
    required this.currentPlayingTrack,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final sizing = MusicCardSizing.fromWidth(MediaQuery.sizeOf(context).width);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 80, left: 24, right: 24, bottom: 150),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _filterTab('All'),
              const SizedBox(width: 8),
              _filterTab('Tracks (${searchData.tracks.length})'),
              const SizedBox(width: 8),
              _filterTab('Artists (${searchData.artists.length})'),
              const SizedBox(width: 8),
              _filterTab('Albums (${searchData.albums.length})'),
              const SizedBox(width: 8),
              _filterTab('Playlists (${searchData.playlists.length})'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48.0),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
            ),
          )
        else if (searchData.tracks.isEmpty &&
            searchData.artists.isEmpty &&
            searchData.albums.isEmpty &&
            searchData.playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48.0),
            child: Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    color: Colors.white38,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No results for "$activeQuery"',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if ((selectedFilter == 'All' || selectedFilter.startsWith('Tracks')) &&
              searchData.tracks.isNotEmpty) ...[
            const Text(
              'Songs',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: searchData.tracks.length.clamp(0, 15),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final track = searchData.tracks[index];
                return MusicTrackRow(
                  track: track,
                  isPlaying: currentPlayingTrack?.id == track.id && isPlaying,
                  isCurrent: currentPlayingTrack?.id == track.id,
                  onTap: () => onPlayTrack(track, searchData.tracks),
                  onMoreTap: () => onAddToPlaylist(track),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
          if ((selectedFilter == 'All' || selectedFilter.startsWith('Artists')) &&
              searchData.artists.isNotEmpty) ...[
            const Text(
              'Artists',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: searchData.artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final artist = searchData.artists[index];
                  return MusicHoverable(
                    scaleFactor: 1.06,
                    child: GestureDetector(
                      onTap: () => onOpenArtistModal(artist.id),
                      child: Column(
                        children: [
                          ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: artist.pictureUrl,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              // P12: decode-capped (was full-res).
                              memCacheWidth: ImageCaps.kThumb,
                              maxWidthDiskCache: ImageCaps.kThumb,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 90,
                            child: Text(
                              artist.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
          ],
          if ((selectedFilter == 'All' || selectedFilter.startsWith('Albums')) &&
              searchData.albums.isNotEmpty) ...[
            const Text(
              'Albums',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (MediaQuery.sizeOf(context).width / sizing.cardWidth)
                    .floor()
                    .clamp(2, 6),
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                childAspectRatio: sizing.cardWidth / sizing.totalHeight,
              ),
              itemCount: searchData.albums.length.clamp(0, 12),
              itemBuilder: (context, index) {
                final album = searchData.albums[index];
                return MusicAlbumCard(
                  album: album,
                  onTap: () => onOpenAlbumModal(album.id),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
          if ((selectedFilter == 'All' || selectedFilter.startsWith('Playlists')) &&
              searchData.playlists.isNotEmpty) ...[
            const Text(
              'Playlists',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (MediaQuery.sizeOf(context).width / sizing.cardWidth)
                    .floor()
                    .clamp(2, 6),
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                childAspectRatio: sizing.cardWidth / sizing.totalHeight,
              ),
              itemCount: searchData.playlists.length.clamp(0, 12),
              itemBuilder: (context, index) {
                final pl = searchData.playlists[index];
                return MusicPlaylistCard(
                  playlist: pl,
                  onTap: () => onOpenCuratedPlaylistModal(pl.id),
                );
              },
            ),
          ],
        ],
      ],
    );
  }

  Widget _filterTab(String label) {
    final isSelected = selectedFilter == label ||
        (selectedFilter == 'All' && label == 'All') ||
        (label.startsWith(selectedFilter) && selectedFilter != 'All');

    return MusicHoverable(
      scaleFactor: 1.05,
      child: GestureDetector(
        onTap: () {
          if (label.startsWith('Tracks')) {
            onFilterSelected('Tracks');
          } else if (label.startsWith('Artists')) {
            onFilterSelected('Artists');
          } else if (label.startsWith('Albums')) {
            onFilterSelected('Albums');
          } else if (label.startsWith('Playlists')) {
            onFilterSelected('Playlists');
          } else {
            onFilterSelected('All');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF7C5CFF)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF7C5CFF)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
