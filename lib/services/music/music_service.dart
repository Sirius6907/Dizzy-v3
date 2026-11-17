import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/music/music_track.dart';
import '../cloud/cloud_client.dart';
import 'deezer_api_client.dart';
import 'default_artists.dart';
import 'jiosaavn_music_client.dart';
import 'lyrics_service.dart';
import 'music_engagement_service.dart';
import 'music_match_policy.dart';
import 'music_mood_filter.dart';
import 'music_onboarding_service.dart';
import 'music_stats_service.dart';
import 'music_trend_service.dart';
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
  static final MusicService instance = MusicService();
  MusicService({YoutubeStreamResolver? streamResolver})
    : _streamResolver = streamResolver ?? YoutubeStreamResolver.instance;

  final DeezerApiClient _deezer = DeezerApiClient.instance;
  final JiosaavnMusicClient _jiosaavn = JiosaavnMusicClient.instance;
  final QobuzMusicService _qobuz = QobuzMusicService.instance;
  final YoutubeStreamResolver _streamResolver;
  final LyricsService _lyricsService = LyricsService.instance;
  final MusicTrendService _trends = MusicTrendService.instance;
  final Map<String, MusicPlaylistDetails> _curatedCache = {};

  /// Round-2 completeness gate (Complaint 1): a card may only present
  /// itself as an album when a real track count answers for it —
  /// ≥5 tracks resolved inline, or the API-declared nb_tracks ≥5.
  /// Flat-track rows (JioSaavn has no album op) simply never present
  /// as album cards, so they stay out of this path.
  static bool isAlbumCardComplete(MusicAlbum album) =>
      album.trackCount >= 5 || album.tracks.length >= 5;

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
        // Round-2 gate: incomplete album rows (1–4 tracks) never surface
        // inside search either.
        albums: (results[2] as List<MusicAlbum>)
            .where(isAlbumCardComplete)
            .toList(),
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
    // Round 2 + India pass (2026-11-12): no global chart seeds. The row
    // is built from the product-approved default list (see
    // default_artists.dart), the user's own recent plays (1 week, then
    // 1 month), and the JioSaavn trending rail's artists. The Deezer
    // global chart is not a source: from a non-Indian IP it returns
    // French rap, which is not "trending" for an Indian user.
    //
    // The default list is resolved to live catalog artists — the names
    // in default_artists.dart are queries, never content. Dedup by id
    // AND normalized name: Deezer can return the same artist twice
    // under different ids.
    const maxRow = 18;
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
      // 1. Part C: favorites lead the row. Each unresolved favorite gets
      //    its face from a live artist search — never a fake name without
      //    an image, and nothing hardcoded.
      final vibe = MusicVibeProfile.fromOnboarding();
      if (vibe.hasSignal) {
        for (final fav in vibe.favoriteArtists) {
          if (out.length >= 5) break;
          try {
            final found = await _deezer.searchArtists(fav, limit: 1);
            for (final a in found) {
              addUnique(a);
            }
          } catch (_) {}
        }
      }

      // 2. Product-approved default row (2026-11-12): the exact list the
      //    owner specified, in the order they gave. Resolved in parallel
      //    so thirteen lookups cost one round-trip instead of thirteen,
      //    and each name is resolved to a real catalog artist so the
      //    face and spelling are live data (Krshna → Krsna, etc.).
      final defaultMatches = await Future.wait<MusicArtist?>([
        for (final entry in kDefaultArtists)
          _deezer
              .searchArtists(entry.query, limit: 5)
              .then(
                (candidates) => pickDefaultArtistMatch(candidates, entry.query),
              )
              .catchError((_) => null),
      ]);
      for (final artist in defaultMatches) {
        if (out.length >= maxRow) break;
        if (artist != null) addUnique(artist);
      }

      // 3. India-first faces: what the user actually played this week,
      //    then this month, then the JioSaavn trending rail's own
      //    artists. These fill the remaining slots after the defaults so
      //    the row still learns from listening.
      final recentNames = <String>{};
      for (final window in const [
        MusicStatsService.weekWindow,
        MusicStatsService.monthWindow,
      ]) {
        for (final e in MusicStatsService.instance.topArtistsSince(
          window,
          take: 8,
        )) {
          recentNames.add(e.key);
        }
        if (recentNames.length >= 8) break;
      }
      for (final name in recentNames) {
        if (out.length >= maxRow) break;
        try {
          final found = await _deezer.searchArtists(name, limit: 1);
          for (final a in found) {
            addUnique(a);
          }
        } catch (_) {}
      }

      // 4. Desi faces from the JioSaavn trending rail (shared daily cache
      //    with the home rows), resolved to a real portrait.
      final saavnTracks = await _trends
          .getOr<List<MusicTrack>>(
            'saavn_trending',
            () => _jiosaavn.trending(limit: 25),
          )
          .catchError((_) => <MusicTrack>[]);
      final artistNames = <String>{};
      for (final t in saavnTracks) {
        final name = t.artist.trim();
        if (name.isNotEmpty) artistNames.add(name);
        if (artistNames.length >= 10) break;
      }
      for (final name in artistNames) {
        if (out.length >= maxRow) break;
        try {
          final found = await _deezer.searchArtists(name, limit: 1);
          for (final a in found) {
            addUnique(a);
          }
        } catch (_) {}
      }

      // 5. Round-2: taste affinity nudge — a recent top-10 listened
      //    artist that's already in the row moves to the front, so the
      //    row visibly learns from the last week/month rather than from
      //    lifetime totals. (Favorites already occupy the front slots,
      //    so the nudge starts scanning after them.)
      final topListened = <String>{
        for (final e in MusicStatsService.instance.topArtistsSince(
          MusicStatsService.monthWindow,
          take: 10,
        ))
          e.key.trim().toLowerCase(),
      };
      if (topListened.isEmpty) {
        topListened.addAll(
          MusicStatsService.instance.topArtists
              .map((e) => e.key.trim().toLowerCase())
              .take(10),
        );
      }
      int tasteIndex(int i) {
        var start = i;
        for (var k = i; k < out.length; k++) {
          if (topListened.contains(out[k].name.trim().toLowerCase())) {
            start = k;
            break;
          }
        }
        return start;
      }

      if (out.length > 1) {
        // Skip the favorites block at the front when it exists.
        final firstFree = vibe.hasSignal
            ? (out.indexWhere(
                    (a) => !vibe.favoriteArtists.contains(
                      a.name.trim().toLowerCase(),
                    ),
                  ) +
                  1)
            : 1;
        final anchor = firstFree >= out.length ? out.length - 1 : firstFree;
        final first = tasteIndex(anchor);
        if (first != anchor && first < out.length) {
          final artist = out.removeAt(first);
          out.insert(anchor, artist);
        }
      }
      return out;
    } catch (e) {
      debugPrint('fetchTrendingArtists error: $e');
    }
    return [];
  }

  /// Punctuation/case-insensitive artist key (`A. R. Rahman` ==
  /// `A.R. Rahman`), used to prove an album is really credited to the
  /// artist that produced it.
  static String _albumArtistKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Keeps only albums genuinely credited to [seed]. Deezer's album
  /// search is literal rather than semantic — the genre keyword
  /// "bollywood" fuzzy-matches "Hollywood" and returns French/Anglo
  /// stock (Véronique Sanson, Johnny Hallyday — proven live 2026-11-12)
  /// — so a row seeded that way is never trustworthy on title alone.
  static List<MusicAlbum> albumsForArtistSeed(
    List<MusicAlbum> albums,
    String seed,
  ) {
    final key = _albumArtistKey(seed);
    if (key.isEmpty) return const <MusicAlbum>[];
    return [
      for (final album in albums)
        if (_albumArtistKey(album.artistName).contains(key)) album,
    ];
  }

  /// "Albums for your taste": seeded from artists that actually chart in
  /// India (the shared JioSaavn trending rail) plus the user's picks —
  /// never from bare genre words, which the catalog answers with
  /// unrelated Western editorial stock.
  Future<List<MusicAlbum>> fetchNewReleases() async {
    final seeds = <String>{
      ...MusicOnboardingService.favoriteArtists.value.take(3),
    };
    try {
      final saavnTracks = await _trends
          .getOr<List<MusicTrack>>(
            'saavn_trending',
            () => _jiosaavn.trending(limit: 25),
          )
          .catchError((_) => <MusicTrack>[]);
      for (final track in saavnTracks) {
        final lead = track.artist.split(',').first.trim();
        if (lead.isEmpty) continue;
        seeds.add(lead);
        if (seeds.length >= 6) break;
      }
    } catch (_) {
      // Trending is best-effort: the approved launch row still seeds.
    }
    if (seeds.isEmpty) {
      seeds.addAll(kDefaultArtists.take(4).map((artist) => artist.query));
    }

    final pools = await Future.wait([
      for (final seed in seeds)
        _trends
            .getOr<List<MusicAlbum>>(
              'taste_albums_artist_$seed',
              () => _deezer.searchAlbums(seed, limit: 8),
            )
            .then((albums) => albumsForArtistSeed(albums, seed))
            .catchError((_) => <MusicAlbum>[]),
    ]);
    final seen = <String>{};
    final candidates = pools
        .expand((pool) => pool)
        .where((album) => album.id.isNotEmpty && seen.add(album.id))
        .toList();
    final selected = MusicEngagementCore.rotateRail(
      candidates,
      daySeed: MusicEngagementCore.daySeed(DateTime.now()),
      take: 10,
    );
    final resolved = await Future.wait([
      for (final album in selected)
        fetchAlbumDetails(album.id).catchError((_) => null),
    ]);
    return [
      for (final details in resolved)
        if (details != null && isAlbumCardComplete(details.album))
          details.album,
    ];
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
          final tracksRaw = row['tracks'] is List
              ? (row['tracks'] as List)
              : const [];
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

    // 2. India-first stations (2026-11-12): instead of Deezer chart /
    //    editorial playlists (French-market rows via the geo proxy), the
    //    rail is built from live JioSaavn searches — each station has one
    //    query, and the card is resolved to real tracks + real cover art.
    //    Queries are stored, content is never.
    const stations = <(String, String, String)>[
      ('punjabi', 'punjabi top hits', 'Punjabi Heat'),
      ('tollywood', 'tollywood hits', 'Tollywood Now'),
      ('lofi', 'hindi lofi hits', 'Hindi Lofi Room'),
      ('party', 'bollywood party hits', 'Desi Dancefloor'),
      ('romance', 'bollywood romantic hits', 'Golden Hour Romance'),
      ('devotional', 'bhajan morning aarti', 'Devotional Mornings'),
      ('indie', 'desi indie hits', 'Desi Indie Corner'),
      ('ollywood', 'odia songs', 'Ollywood Now'),
    ];
    try {
      final futures = <Future<List<MusicTrack>>>[
        for (final (key, query, _) in stations)
          _trends
              .getOr<List<MusicTrack>>(
                'station_$key',
                () => _jiosaavn.search(query, limit: 25),
              )
              .catchError((_) => <MusicTrack>[]),
      ];
      final settled = await Future.wait<List<MusicTrack>>(futures);
      final daySeed = MusicEngagementCore.daySeed(DateTime.now());
      final built = <MusicPlaylist>[];
      for (var i = 0; i < stations.length; i++) {
        final (_, _, title) = stations[i];
        final p = MusicEngagementCore.stationPlaylist(
          id: 'saavn_station_${stations[i].$1}',
          title: title,
          tracks: settled[i],
        );
        if (p != null) built.add(p);
      }
      for (final p in MusicEngagementCore.rotateRail(
        built,
        daySeed: daySeed,
        take: 14,
      )) {
        if (seen.add(p.id)) {
          _curatedCache[p.id] = MusicPlaylistDetails(
            playlist: p,
            tracks: p.tracks,
          );
          out.add(p);
        }
        if (out.length >= 14) break;
      }
      if (out.isNotEmpty) return out;
    } catch (e) {
      debugPrint('fetchCuratedPlaylists station error: $e');
    }

    return out;
  }

  Future<Map<String, List<MusicTrack>>> fetchFeaturedSections() async {
    // Every rail is live and content-derived: India trending, this user's
    // recent plays (week/month), time-of-day mood rails scored with
    // MusicMoodFilter, and day-rotated radio rows built from India
    // faces. No fixed query maps — an empty source simply means the rail
    // is absent (surface-hiding), never a placeholder list.
    final now = DateTime.now();
    final daySeed = MusicEngagementCore.daySeed(now);
    final bucket = MusicEngagementCore.timeBucket(now);
    final results = <String, List<MusicTrack>>{};
    final vibe = MusicVibeProfile.fromOnboarding();

    try {
      // India-first pool: the JioSaavn trending rail is the only
      // "what India is playing" source that a proxy IP cannot skew. The
      // Deezer global chart is deliberately not a default rail — from a
      // non-Indian IP it returns French rap.
      final saavnTracks = await _trends
          .getOr<List<MusicTrack>>(
            'saavn_trending',
            () => _jiosaavn.trending(limit: 25),
          )
          .catchError((_) => <MusicTrack>[]);

      // Part C: the user's own vibe rail leads the home when the
      // onboarding produced any signal. Content is live: one search per
      // chosen style (day-cached under the profile key, shared with the
      // smart-mix pool), explored with a day-rotated merge then ranked
      // by the vibe score. No signal → no rail, exactly as before.
      if (vibe.hasSignal) {
        final vibeRail = await _buildVibeRail(
          vibe: vibe,
          moodPool: saavnTracks,
          now: now,
        );
        if (vibeRail.length >= 5) {
          results['💫 Your Vibe'] = vibeRail;
        }
      }
      if (saavnTracks.isNotEmpty) {
        results['🇮🇳 Trending in India'] = _trends.rotateTracks(
          'saavn_trending',
          saavnTracks,
          now: now,
          take: 20,
        );
      }

      // Recency rails (2026-11-12): Spotify's home runs on a weekly chart
      // (Top Songs) plus a daily one (Top 50). A server-side India chart
      // is not deployable from here, so the same cadence is built from
      // this user's timestamped play log — week first, then month, and a
      // rail is hidden unless it has enough repeats to mean something.
      final weekTracks = MusicStatsService.instance.recentTracks(
        MusicStatsService.weekWindow,
        take: 15,
        minPlays: 2,
      );
      if (weekTracks.length >= 4) {
        results['🕐 On Repeat — Last 7 Days'] = weekTracks;
      }
      final monthTracks = MusicStatsService.instance.recentTracks(
        MusicStatsService.monthWindow,
        take: 15,
        minPlays: 3,
      );
      if (monthTracks.length >= 4) {
        results['📅 Your Month in Music'] = monthTracks;
      }

      // Time-of-day mood rails: each mood pulls its OWN live content via
      // a mood search query (results rotate daily), then the keyword-scored
      // trending pool only fills leftover slots — so rails actually differ
      // by mood instead of showing the same five trending tracks.
      final moodPool = saavnTracks;
      final moodList = MusicEngagementCore.moodOrder(
        bucket,
      ).where((m) => m != MusicMood.any).toList();
      final moodSearches = await Future.wait<List<MusicTrack>>([
        for (final mood in moodList)
          _trends
              .getOr<List<MusicTrack>>(
                'mood_search_${mood.name}',
                () => _jiosaavn.search(
                  MusicMoodFilter.moodSearchQuery(mood)!,
                  limit: 15,
                ),
              )
              .catchError((_) => <MusicTrack>[]),
      ]);
      for (var i = 0; i < moodList.length; i++) {
        final mood = moodList[i];
        final searched = _trends.rotateTracks(
          'mood_${mood.name}',
          moodSearches[i],
          now: now,
          take: 15,
        );
        final scored = MusicMoodFilter.mergeMoodTracks(
          searched: searched,
          pool: moodPool,
          mood: mood,
          limit: 12,
        );
        if (scored.length >= 5) {
          results['${mood.emoji} ${mood.label} Picks'] = scored;
        }
      }

      List<MusicArtist> chartArtists = [];
      try {
        chartArtists = await _trends
            .getOr<List<MusicArtist>>(
              'taste_radar_${vibe.profKey}',
              fetchTrendingArtists,
            )
            .catchError((_) => <MusicArtist>[]);
      } catch (e) {
        debugPrint('fetchFeaturedSections artists error: $e');
      }
      if (chartArtists.isNotEmpty) {
        // Part C: when the user has favorite artists, radar rows bias
        // toward them first (matches on the chart jump the queue); the
        // rest still rotate by day so it never freezes.
        List<MusicArtist> picks;
        if (vibe.hasSignal && vibe.favoriteArtists.isNotEmpty) {
          final favMatch = chartArtists
              .where(
                (a) =>
                    vibe.favoriteArtists.contains(a.name.trim().toLowerCase()),
              )
              .toList();
          final rest = chartArtists.where(
            (a) => !vibe.favoriteArtists.contains(a.name.trim().toLowerCase()),
          );
          picks = [
            ...favMatch,
            ...MusicEngagementCore.rotateRail(
              rest.toList(),
              daySeed: daySeed,
              take: chartArtists.length,
            ),
          ].take(3).toList();
        } else {
          picks = MusicEngagementCore.rotateRail(
            chartArtists,
            daySeed: daySeed,
            take: 3,
          );
        }
        final railFutures = picks
            .map((a) => _deezer.searchTracks(a.name, limit: 12))
            .toList();
        final rails = await Future.wait<List<MusicTrack>>(
          railFutures.map((f) => f.catchError((_) => <MusicTrack>[])),
        );
        for (var i = 0; i < picks.length; i++) {
          final artist = picks[i];
          final tracks = rails[i];
          if (tracks.length >= 5) {
            results['🎙️ ${artist.name} Radar'] = tracks;
          }
        }
      }
    } catch (e) {
      debugPrint('fetchFeaturedSections error: $e');
    }

    return results;
  }

  /// Part C: "Your Vibe" rail body. Live content for the user's chosen
  /// styles (+ their default mood phrase), day-rotated for exploration,
  /// then vibe-ranked so favorites and mood matches lead. Same trend
  /// keys as the smart-mix pool, so the two surfaces share one fetch.
  Future<List<MusicTrack>> _buildVibeRail({
    required MusicVibeProfile vibe,
    required List<MusicTrack> moodPool,
    required DateTime now,
  }) async {
    final daySeed = MusicEngagementCore.daySeed(now);
    final profHash = vibe.profKey.hashCode;
    final queries = <String, String>{
      for (final style in MusicOnboardingService.selectedStyles.value)
        'vibe_style_${style.name}_$profHash': style.searchQuery,
      if (vibe.defaultMood != MusicMood.any)
        'vibe_mood_${vibe.defaultMood.name}_$profHash':
            MusicMoodFilter.moodSearchQuery(vibe.defaultMood)!,
    };

    final searchedLists = await Future.wait<List<MusicTrack>>([
      for (final entry in queries.entries)
        _trends
            .getOr<List<MusicTrack>>(
              entry.key,
              () => _jiosaavn.search(entry.value, limit: 15),
            )
            .catchError((_) => <MusicTrack>[]),
    ]);

    // Day-rotated exploration: rotate the merged searched pool by the
    // day seed so tomorrow the "same vibe" surfaces different cuts first.
    final searched = <MusicTrack>[];
    final seen = <String>{};
    for (final list in searchedLists) {
      final rotated = MusicEngagementCore.rotateRail(
        list,
        daySeed: daySeed,
        take: list.length,
      );
      for (final t in rotated) {
        if (seen.add(t.id)) searched.add(t);
      }
    }

    // Vibe-ranked merge: keyword + duration mood scoring under the
    // profile's own weights, favorites boosted, index-stable tie-break.
    final scored = List.generate(searched.length, (i) => (i, searched[i]));
    scored.sort((a, b) {
      final byVibe = MusicEngagementCore.vibeScore(
        b.$2,
        vibe,
      ).compareTo(MusicEngagementCore.vibeScore(a.$2, vibe));
      if (byVibe != 0) return byVibe;
      return a.$1.compareTo(b.$1);
    });
    final out = [for (final s in scored) s.$2].take(12).toList();
    if (out.length < 12) {
      for (final t in moodPool) {
        if (out.length >= 12) break;
        if (seen.add(t.id)) out.add(t);
      }
    }
    return out;
  }

  Future<MusicArtistDetails?> fetchArtistDetails(String artistId) async {
    return _deezer.getArtistDetails(artistId);
  }

  Future<MusicAlbumDetails?> fetchAlbumDetails(String albumId) async {
    // Round-2 completeness validation: a declared ≥5-track album whose
    // tracklist resolved thin is NOT shown as an album at all — better
    // to drop than to present incomplete data as a complete album.
    // (The full `/album/{id}` + `/album/{id}/tracks` resolve already
    // returns the complete tracklist in the normal path; this guards
    // partial responses.)
    final details = await _trends.getOr<MusicAlbumDetails?>(
      'album_details_$albumId',
      () => _deezer.getAlbumDetails(albumId),
    );
    if (details == null) return null;
    final declared = details.album.trackCount;
    final resolved = details.tracks.length;
    if (declared >= 5 && resolved < 5) {
      debugPrint(
        'fetchAlbumDetails: incomplete tracklist $resolved/$declared — dropped',
      );
      return null;
    }
    return details;
  }

  Future<MusicPlaylistDetails?> fetchPlaylistDetails(String playlistId) async {
    if (playlistId.startsWith('curated_') &&
        _curatedCache.containsKey(playlistId)) {
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

  void invalidateAudio(MusicTrack track) {
    _streamResolver.invalidate(track.id);
  }

  /// A different playable stream for [track], used when the native player
  /// rejected the previous URL (expired signature, rejected CDN node).
  Future<MusicStreamResult?> getNextAudioStream(MusicTrack track) async {
    if (_saavnResult(track) != null) return null;
    try {
      final next = await _streamResolver.nextCandidate(track);
      if (next == null || next.url.isEmpty) return null;
      return MusicStreamResult(
        url: next.url,
        userAgent: next.userAgent,
        format: 'm4a',
        quality: 'YouTube HQ',
        isLossless: false,
      );
    } catch (_) {
      return null;
    }
  }

  Future<MusicStreamResult?> getAudioStream(
    MusicTrack track, {
    MusicAudioSource source = MusicAudioSource.flac,
  }) async {
    // Direct Saavn stream — instant, no need to enter the race.
    final saavn = _saavnResult(track);
    if (saavn != null) return saavn;

    // Race immediately so the fallback receives its full resolution budget.
    final resolved = await _raceAudioPaths(
      track,
      source,
    ).timeout(const Duration(seconds: 14), onTimeout: () => null);
    return resolved ?? _previewResult(track);
  }

  MusicStreamResult? _saavnResult(MusicTrack track) {
    final url = track.previewUrl;
    if (!track.id.startsWith('saavn_') ||
        url == null ||
        !url.startsWith('http')) {
      return null;
    }
    return MusicStreamResult(
      url: url,
      format: 'm4a',
      quality: 'JioSaavn HQ',
      isLossless: false,
    );
  }

  MusicStreamResult? _previewResult(MusicTrack track) {
    final url = track.previewUrl;
    if (url == null || !url.startsWith('http')) return null;
    return MusicStreamResult(
      url: url,
      format: 'mp3',
      quality: 'Preview (30s)',
      isLossless: false,
    );
  }

  Future<MusicStreamResult?> _raceAudioPaths(
    MusicTrack track,
    MusicAudioSource source,
  ) {
    final winner = Completer<MusicStreamResult?>();
    var active = 0;
    var youtubeStarted = false;

    void maybeFinish() {
      if (winner.isCompleted) return;
      if (youtubeStarted && active == 0) winner.complete(null);
    }

    void startYoutube() {
      if (youtubeStarted || winner.isCompleted) return;
      youtubeStarted = true;
      active++;
      unawaited(
        _runYoutubePath(track, winner, () {
          active--;
          maybeFinish();
        }),
      );
    }

    Future<void> runQobuz() async {
      active++;
      try {
        if (source == MusicAudioSource.flac) {
          final flac = await _qobuz.resolveLosslessUrl(track);
          if (flac != null && flac.url.isNotEmpty && !winner.isCompleted) {
            winner.complete(
              MusicStreamResult(
                url: flac.url,
                userAgent: flac.headers['User-Agent'],
                format: flac.format,
                quality: flac.quality,
                isLossless: true,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Qobuz FLAC error, falling back to YouTube: $e');
      } finally {
        active--;
        startYoutube();
        maybeFinish();
      }
    }

    unawaited(runQobuz());
    startYoutube();
    return winner.future;
  }

  Future<void> _runYoutubePath(
    MusicTrack track,
    Completer<MusicStreamResult?> winner,
    VoidCallback onDone,
  ) async {
    try {
      final yt = await _streamResolver.resolveUrl(track);
      if (yt != null && yt.url.isNotEmpty && !winner.isCompleted) {
        winner.complete(
          MusicStreamResult(
            url: yt.url,
            userAgent: yt.userAgent,
            format: 'm4a',
            quality: 'YouTube HQ',
            isLossless: false,
          ),
        );
      }
    } catch (_) {
      // Falls through to the overall budget + preview fallback.
    } finally {
      onDone();
    }
  }

  Future<LyricsData> fetchLyrics(MusicTrack track) async {
    return _lyricsService.getLyrics(track);
  }
}
