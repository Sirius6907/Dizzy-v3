import 'package:flutter/material.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_player_controller.dart';
import 'music_horizontal_scroll_section.dart';
import 'music_album_card.dart';
import 'music_playlist_card.dart';
import 'music_track_card.dart';

class MusicAlbumsRow extends StatelessWidget {
  final String title;
  final List<MusicAlbum> albums;
  final Function(MusicAlbum) onAlbumTap;

  const MusicAlbumsRow({
    super.key,
    required this.title,
    required this.albums,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    return MusicHorizontalScrollSection(
      title: title,
      height: 200,
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return MusicAlbumCard(album: album, onTap: () => onAlbumTap(album));
      },
    );
  }
}

class MusicPlaylistsRow extends StatelessWidget {
  final String title;
  final List<MusicPlaylist> playlists;
  final Function(MusicPlaylist) onPlaylistTap;

  const MusicPlaylistsRow({
    super.key,
    required this.title,
    required this.playlists,
    required this.onPlaylistTap,
  });

  @override
  Widget build(BuildContext context) {
    return MusicHorizontalScrollSection(
      title: title,
      height: 200,
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final pl = playlists[index];
        return MusicPlaylistCard(playlist: pl, onTap: () => onPlaylistTap(pl));
      },
    );
  }
}

class MusicCategorySlider extends StatelessWidget {
  final String title;
  final List<MusicTrack> tracks;
  final Function(MusicTrack) onAddToPlaylist;

  const MusicCategorySlider({
    super.key,
    required this.title,
    required this.tracks,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return MusicHorizontalScrollSection(
      title: title,
      height: 215,
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return MusicTrackCard(
          track: track,
          onTap: () => MusicPlayerController.instance.playTrack(
            track,
            playlistQueue: tracks,
          ),
          onMoreTap: () => onAddToPlaylist(track),
        );
      },
    );
  }
}

