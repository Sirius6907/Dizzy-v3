import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/music/music_track.dart';
import '../cloud/cloud_client.dart';
import 'deezer_api_client.dart';
import 'jiosaavn_music_client.dart';
import 'lyrics_service.dart';
import 'music_match_policy.dart';
import 'qobuz_music_service.dart';
import 'youtube_stream_resolver.dart';

enum MusicAudioSource { flac, youtube }

class MusicStreamResult {
  final String url;
  final String? userAgent;
  final String format;
  final String quality;
  final bool isLossless;

  const MusicStreamResult({
    required this.url,
    this.userAgent,
    this.format = 'flac',
    this.quality = 'FLAC Hi-Res',
    this.isLossless = true,
  });
}

class MusicService {
  static final MusicService instance = MusicService._internal();
  MusicService._internal();

  final DeezerApiClient _deezer = DeezerApiClient.instance;
  final JiosaavnMusicClient _jiosaavn = JiosaavnMusicClient.instance;
  final QobuzMusicService _qobuz = QobuzMusicService.instance;
  final YoutubeStreamResolver _streamResolver = YoutubeStreamResolver.instance;
  final LyricsService _lyricsService = LyricsService.instance;
  final Map<String, MusicPlaylistDetails> _curatedCache = {};

  Future<MusicSearchData> searchFull(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return MusicSearchData.empty;

    try {
      final tracksFuture = searchTracks(trimmed);
      final artistsFuture = _deezer.searchArtists(trimmed, limit: 15);
      final albumsFuture = _deezer.searchAlbums(trimmed, limit: 15);
      final playlistsFuture = _deezer.searchPlaylists(trimmed, limit: 15);

      final results = await Future.wait([
        tracksFuture,
        artistsFuture,
        albumsFuture,
        playlistsFuture,
      ]);

      return MusicSearchData(
        tracks: results[0] as List<MusicTrack>,
        artists: results[1] as List<MusicArtist>,
        albums: results[2] as List<MusicAlbum>,
        playlists: results[3] as List<MusicPlaylist>,
      );
    } catch (e) {
      debugPrint('searchFull error: $e');
      return MusicSearchData.empty;
    }
  }

  Future<List<MusicTrack>> searchTracks(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final saavnFuture = _jiosaavn.search(trimmed, limit: 20);
      final deezerFuture = _deezer.searchTracks(trimmed, limit: 30);

      final results = await Future.wait([
        saavnFuture.catchError((e) {
          debugPrint('searchTracks saavn error: $e');
          return <MusicTrack>[];
        }),
        deezerFuture.catchError((e) {
          debugPrint('searchTracks deezer error: $e');
          return <MusicTrack>[];
        }),
      ]);

      final saavnTracks = results[0];
      final deezerTracks = results[1];

      final langHint = MusicMatchPolicy.languageHint(trimmed);
      final out = <MusicTrack>[];
      final seenTitles = <String>{};

      // Desi / regional query: prioritize JioSaavn depth first
      final primary = langHint.isNotEmpty ? saavnTracks : deezerTracks;
      final secondary = langHint.isNotEmpty ? deezerTracks : saavnTracks;

      for (final t in primary) {
        final norm = MusicMatchPolicy.normalize(t.title);
        if (norm.isNotEmpty && seenTitles.add(norm)) {
          out.add(t);
        }
      }
      for (final t in secondary) {
        final norm = MusicMatchPolicy.normalize(t.title);
        if (norm.isNotEmpty && seenTitles.add(norm)) {
          out.add(t);
        }
      }

      // Exact-match elevation (site §13 rule): exact title jumps to top
      final exactIdx = MusicMatchPolicy.pickExact(
        trimmed,
        candidateTitles: out.map((t) => t.title).toList(),
        lang: langHint,
      );
      if (exactIdx != null && exactIdx > 0 && exactIdx < out.length) {
        final exactTrack = out.removeAt(exactIdx);
        out.insert(0, exactTrack);
      }

      return out;
    } catch (e) {
      debugPrint('searchTracks error: $e');
      return _deezer.searchTracks(trimmed);
    }
  }

  Future<List<MusicArtist>> fetchTrendingArtists() async {
    // India-first: seed desi artist faces so the row never opens with
    // only western faces. Chart artists append after.
    // Dedup by id AND normalized name — Deezer can return the same
    // artist twice under different ids (e.g. two "Arijit Singh" rows).
    final out = <MusicArtist>[];
    final seenIds = <String>{};
    final seenNames = <String>{};
    bool addUnique(MusicArtist a) {
      final norm = a.name.trim().toLowerCase();
      if (norm.isEmpty || seenNames.contains(norm)) return false;
      if (!seenIds.add(a.id)) return false;
      seenNames.add(norm);
      out.add(a);
      return true;
    }
    try {
      const seeds = [
        'Arijit Singh',
        'Pritam',
        'Diljit Dosanjh',
        'Badshah',
        'Shreya Ghoshal',
        'Anuv Jain',
      ];
      for (final name in seeds) {
        try {
          final found = await _deezer.searchArtists(name, limit: 2);
          for (final a in found) {
            addUnique(a);
            if (out.length >= 7) break;
          }
        } catch (_) {}
        if (out.length >= 7) break;
      }
      try {
        final chart = await _deezer.getChartArtists(limit: 20);
        for (final a in chart) {
          addUnique(a);
          if (out.length >= 14) break;
        }
      } catch (e) {
        debugPrint('fetchTrendingArtists chart error: $e');
      }
      if (out.isNotEmpty) return out;
    } catch (e) {
      debugPrint('fetchTrendingArtists error: $e');
    }
    return [];
  }

  Future<List<MusicAlbum>> fetchNewReleases() async {
    // India-first: desi albums open the row, global editorial fills behind.
    final out = <MusicAlbum>[];
    final seen = <String>{};
    try {
      const seeds = ['Arijit Singh', 'AP Dhillon', 'Pritam', 'Diljit Dosanjh'];
      for (final name in seeds) {
        try {
          final found = await _deezer.searchAlbums(name, limit: 3);
          for (final a in found) {
            if (seen.add(a.id)) out.add(a);
            if (out.length >= 8) break;
          }
        } catch (_) {}
        if (out.length >= 8) break;
      }
      try {
        final releases = await _deezer.getNewReleases(limit: 20);
        final pick = releases.isNotEmpty
            ? releases
            : await _deezer.getChartAlbums(limit: 20);
        for (final a in pick) {
          if (seen.add(a.id)) out.add(a);
          if (out.length >= 14) break;
        }
      } catch (e) {
        debugPrint('fetchNewReleases chart error: $e');
      }
      if (out.isNotEmpty) return out;
    } catch (e) {
      debugPrint('fetchNewReleases error: $e');
    }
    return [];
  }

  Future<List<MusicPlaylist>> fetchCuratedPlaylists() async {
    final out = <MusicPlaylist>[];
    final seen = <String>{};

    // 1. First priority: admin-published curated playlists from Supabase (v1.3.3-T2.4/T3.4)
    if (CloudClient.isReady) {
      try {
        final res = await CloudClient.db
            .from('curated_playlists')
            .select()
            .eq('active', true)
            .order('position', ascending: true)
            .limit(10);
        for (final row in res) {
          final id = (row['id'] ?? row['slug'] ?? '').toString();
          if (id.isEmpty) continue;
          final tracksRaw = row['tracks'] is List ? (row['tracks'] as List) : const [];
          final tracks = tracksRaw
              .whereType<Map<String, dynamic>>()
              .map((m) => MusicTrack.fromJson(m))
              .toList();
          final p = MusicPlaylist(
            id: 'curated_$id',
            title: (row['title'] ?? 'Dizzy Curated').toString(),
            description: (row['subtitle'] ?? '').toString(),
            coverUrl: (row['cover_url'] ?? '').toString(),
            trackCount: tracks.length,
            creatorName: 'Dizzy Curators',
            tracks: tracks,
          );
          if (seen.add(p.id)) {
            _curatedCache[p.id] = MusicPlaylistDetails(
              playlist: p,
              tracks: tracks,
            );
            out.add(p);
          }
        }
      } catch (e) {
        debugPrint('fetchCuratedPlaylists supabase error: $e');
      }
    }

    // 2. India-first Deezer curated seeds
    try {
      const seeds = [
        'Bollywood Love Songs',
        'Punjabi Bhangra',
        'Honey Singh',
        'Bollywood Remix',
        'Night Drive',
        'Sad Lofi',
        'Phonk Hits',
      ];
      for (final q in seeds) {
        try {
          final found = await _deezer.searchPlaylists(q, limit: 2);
          for (final p in found) {
            if (seen.add(p.id)) out.add(p);
            if (out.length >= 10) break;
          }
        } catch (_) {}
        if (out.length >= 10) break;
      }
      try {
        final chart = await _deezer.getChartPlaylists(limit: 20);
        final pick = chart.isNotEmpty
            ? chart
            : await _deezer.getEditorialSelection(limit: 20);
        for (final p in pick) {
          if (seen.add(p.id)) out.add(p);
          if (out.length >= 14) break;
        }
      } catch (e) {
        debugPrint('fetchCuratedPlaylists chart error: $e');
      }
      if (out.isNotEmpty) return out;
    } catch (e) {
      debugPrint('fetchCuratedPlaylists error: $e');
    }
    return out;
  }

  Future<Map<String, List<MusicTrack>>> fetchFeaturedSections() async {
    final results = <String, List<MusicTrack>>{};

    try {
      // India-first order: pehla section hero billboard banata hai,
      // isliye sabse pehle desi romance taaki hero hamesha desi lage.
      // Har query Deezer pe live verify hai (khaali section nahi banega).
      // Aakhri me global chart — "thoda global" touch ke liye.
      final queries = <String, String>{
        '❤️ Bollywood Romance Essentials': 'Pritam Bollywood',
        '💃 Bollywood Dance & Party': 'Bollywood Dance',
        '🎧 Mashup & Remix Lab': 'Bollywood Mashup',
        '🌾 Punjabi Party Hits': 'AP Dhillon',
        '🎤 Desi Hip-Hop — Gully Vibes': 'Desi Hip Hop',
        '🛻 Indie & Acoustic Feels': 'Anuv Jain',
        '🥁 Ollywood DJ & Sambalpuri Mashups': 'Sambalpuri DJ',
        '🌙 Lofi & Slowed-Reverb Nights': 'Bollywood LoFi',
      };

      final chartFuture = _deezer.getChartTracks(limit: 25);
      final saavnTrendingFuture = _jiosaavn.trending(limit: 15).catchError((_) => <MusicTrack>[]);
      final queryFutures = queries.entries
          .map((e) => _deezer.searchTracks(e.value, limit: 15))
          .toList();
      final settled = await Future.wait<Object>([chartFuture, saavnTrendingFuture, ...queryFutures]);

      // v1.3.3-T3.0: JioSaavn Trending row
      final saavnTracks = settled[1] as List<MusicTrack>;
      if (saavnTracks.isNotEmpty) {
        results['🔥 Trending Desi Hits — JioSaavn'] = saavnTracks;
      }

      for (var i = 0; i < queries.length; i++) {
        final title = queries.keys.elementAt(i);
        final tracks = settled[i + 2] as List<MusicTrack>;
        if (tracks.isNotEmpty) {
          results[title] = tracks;
        }
      }

      final chartTracks = settled[0] as List<MusicTrack>;
      if (chartTracks.isNotEmpty) {
        results['🔥 Trending Now — Global'] = chartTracks;
      }
    } catch (e) {
      debugPrint('fetchFeaturedSections error: $e');
    }

    return results;
  }

  Future<MusicArtistDetails?> fetchArtistDetails(String artistId) async {
    return _deezer.getArtistDetails(artistId);
  }

  Future<MusicAlbumDetails?> fetchAlbumDetails(String albumId) async {
    return _deezer.getAlbumDetails(albumId);
  }

  Future<MusicPlaylistDetails?> fetchPlaylistDetails(String playlistId) async {
    if (playlistId.startsWith('curated_') && _curatedCache.containsKey(playlistId)) {
      return _curatedCache[playlistId];
    }
    return _deezer.getPlaylistDetails(playlistId);
  }

  Future<List<MusicGenre>> fetchGenres() async {
    return _deezer.getGenres();
  }

  Future<List<MusicTrack>> fetchGenreTracks(String genreName) async {
    return _deezer.searchTracks('$genreName Top Hits', limit: 25);
  }

  Future<MusicStreamResult?> getAudioStream(
    MusicTrack track, {
    MusicAudioSource source = MusicAudioSource.flac,
  }) async {
    if (source == MusicAudioSource.flac) {
      try {
        final flac = await _qobuz.resolveLosslessUrl(track);
        if (flac != null && flac.url.isNotEmpty) {
          return MusicStreamResult(
            url: flac.url,
            userAgent: flac.headers['User-Agent'],
            format: flac.format,
            quality: flac.quality,
            isLossless: true,
          );
        }
      } catch (e) {
        debugPrint('Qobuz FLAC error, falling back to YouTube: $e');
      }
    }

    // Direct Saavn stream if available
    if (track.id.startsWith('saavn_') &&
        track.previewUrl != null &&
        track.previewUrl!.startsWith('http')) {
      return MusicStreamResult(
        url: track.previewUrl!,
        format: 'm4a',
        quality: 'JioSaavn HQ',
        isLossless: false,
      );
    }

    // YouTube Audio Stream (Primary or Fallback)
    final yt = await _streamResolver.resolveUrl(track);
    if (yt != null && yt.url.isNotEmpty) {
      return MusicStreamResult(
        url: yt.url,
        userAgent: yt.userAgent,
        format: 'm4a',
        quality: 'YouTube HQ',
        isLossless: false,
      );
    }

    // Last resort fallback: previewUrl
    if (track.previewUrl != null && track.previewUrl!.startsWith('http')) {
      return MusicStreamResult(
        url: track.previewUrl!,
        format: 'mp3',
        quality: 'Preview (30s)',
        isLossless: false,
      );
    }

    return null;
  }

  Future<LyricsData> fetchLyrics(MusicTrack track) async {
    return _lyricsService.getLyrics(track);
  }
}
