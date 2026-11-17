import 'dart:io';

import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/music_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for a proven live defect (2026-11-12):
/// `GET api.deezer.com/search/album?q=bollywood` answers with
/// "Hollywood" albums by Véronique Sanson / Johnny Hallyday / Oasis, so
/// the "Albums for your taste" rail shipped French/Anglo stock to an
/// Indian listener. The rail is now seeded from charting artists and
/// every album must be credited to its seed.
MusicAlbum _album(String id, String title, String artist) => MusicAlbum(
  id: id,
  title: title,
  artistName: artist,
  coverUrl: '',
  trackCount: 10,
);

void main() {
  test('albumsForArtistSeed keeps only albums credited to the seed', () {
    final pool = [
      _album('1', 'Angels For Each Other', 'Martin Garrix'),
      _album('2', 'Arijit Singh - Ultimate Love Songs', 'Arijit Singh'),
      _album('3', 'Hollywood (Edition Deluxe)', 'Véronique Sanson'),
    ];

    final kept = MusicService.albumsForArtistSeed(pool, 'Arijit Singh');

    expect(kept.map((a) => a.id), ['2']);
  });

  test('albumsForArtistSeed ignores punctuation and case in the credit', () {
    final pool = [
      _album('1', 'Taal', 'A.R. Rahman'),
      _album('2', 'Dil Se', 'A. R. Rahman'),
      _album('3', 'Random', 'Someone Else'),
    ];

    final kept = MusicService.albumsForArtistSeed(pool, 'A. R. Rahman');

    expect(kept.map((a) => a.id), ['1', '2']);
  });

  test('albumsForArtistSeed drops everything for an empty seed', () {
    final pool = [_album('1', 'Anything', 'Anyone')];
    expect(MusicService.albumsForArtistSeed(pool, '  '), isEmpty);
  });

  test('taste album rail is never seeded from bare genre words', () {
    final source = File(
      'lib/services/music/music_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<List<MusicAlbum>> fetchNewReleases');
    expect(start, isNonNegative, reason: 'fetchNewReleases must exist');
    final body = source.substring(
      start,
      source.indexOf('Future<List<MusicPlaylist>> fetchCuratedPlaylists'),
    );

    expect(body, contains('albumsForArtistSeed'));
    expect(body, contains('saavn_trending'));
    for (final genre in ["'bollywood'", "'tamil'", "'telugu'"]) {
      expect(
        body,
        isNot(contains(genre)),
        reason: 'genre keyword $genre returns unrelated Western albums',
      );
    }
  });
}
