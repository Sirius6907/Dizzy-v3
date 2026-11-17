import 'package:flutter/material.dart';
import '../../models/music/music_track.dart';
import 'music_engagement_service.dart';
import 'music_library_service.dart';
import 'music_mood_filter.dart';
import 'music_onboarding_service.dart';
import 'music_service.dart';
import 'music_trend_service.dart';

class SmartMixPlaylist {
  final String id;
  final String title;
  final String description;
  final Color gradientStart;
  final Color gradientEnd;
  final List<MusicTrack> tracks;

  const SmartMixPlaylist({
    required this.id,
    required this.title,
    required this.description,
    required this.gradientStart,
    required this.gradientEnd,
    required this.tracks,
  });

  String get primaryCoverUrl => tracks.isNotEmpty ? tracks.first.coverUrl : '';

  /// Mood variants keep the same id/title/gradient; only tracks + copy shift.
  SmartMixPlaylist copyWith({String? description, List<MusicTrack>? tracks}) {
    return SmartMixPlaylist(
      id: id,
      title: title,
      description: description ?? this.description,
      gradientStart: gradientStart,
      gradientEnd: gradientEnd,
      tracks: tracks ?? this.tracks,
    );
  }
}

class MusicSmartMixService {
  MusicSmartMixService._();
  static final MusicSmartMixService instance = MusicSmartMixService._();

  /// Cache keyed by `mood_profKey`: `any` keeps the legacy layout
  /// untouched, each real mood gets its own filtered variant generated
  /// lazily, and the profile key makes any onboarding change (favorites,
  /// styles, default mood) miss the cache and regenerate fresh (Part C).
  final Map<String, List<SmartMixPlaylist>> _cache = {};

  /// Bounded cache: keeping every historical profile+mood combo would
  /// leak; anything past this many generations drops the whole map.
  static const int _cacheCap = 8;

  Future<List<SmartMixPlaylist>> getOrGenerateMixes({
    bool forceRefresh = false,
    MusicMood mood = MusicMood.any,
  }) async {
    if (forceRefresh) {
      _cache.clear();
    }
    final vibe = MusicVibeProfile.fromOnboarding();
    final key = '${mood.name}_${vibe.profKey}';
    final cached = _cache[key];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final mixes = await _buildMixes(mood, vibe);
    if (_cache.length >= _cacheCap) _cache.clear();
    _cache[key] = mixes;
    return mixes;
  }

  Future<List<SmartMixPlaylist>> _buildMixes(
    MusicMood mood,
    MusicVibeProfile vibe,
  ) async {
    final liked = MusicLibraryService.instance.likedTracks;
    final recent = MusicLibraryService.instance.recentTracks;
    final featured = await MusicService.instance.fetchFeaturedSections();

    final allPool = <MusicTrack>[...liked, ...recent];
    for (final list in featured.values) {
      allPool.addAll(list);
    }

    // Part C: vibe pools — live searches for the user's own styles and
    // favorite artists, day-cached under the profile key so a favorite
    // change fetches new content the same day. India-first: queries go
    // through the shared search surface (JioSaavn leads for desi terms).
    final vibeExtras = await _fetchVibePool(vibe);
    allPool.addAll(vibeExtras);

    // Favorite accents passed to the core: liked/recent tracks by the
    // user's favorite artists + the accent search hits. The generator
    // weaves them into every 4th slot of each mix.
    final favNames = vibe.favoriteArtists;
    final favTracks = <MusicTrack>[
      ...liked.where((t) => favNames.contains(t.artist.trim().toLowerCase())),
      ...recent.where((t) => favNames.contains(t.artist.trim().toLowerCase())),
      ...vibeExtras.where(
        (t) => favNames.contains(t.artist.trim().toLowerCase()),
      ),
    ];

    // Daily mixes via the engagement core (it deduplicates internally):
    // date-seeded composition, 4–6 mixes, mega-mix sizes, vibe-scored
    // pool ordering and ~1-in-4 favorite accents. Titles are human vibe
    // labels ("Lo-fi Evenings") — never artist concatenation.
    final now = DateTime.now();
    final generated = MusicEngagementCore.generateDailyMixes(
      pool: allPool,
      date: now,
      timeBucket: MusicEngagementCore.timeBucket(now),
      vibe: vibe,
      favoriteTracks: favTracks,
    );

    const gradients = [
      (Color(0xFF1DB954), Color(0xFF123B22)),
      (Color(0xFF7C5CFF), Color(0xFF261852)),
      (Color(0xFF00D2EF), Color(0xFF0D3F59)),
      (Color(0xFFFF4B72), Color(0xFF4A1024)),
      (Color(0xFFFFB35C), Color(0xFF4A2E10)),
      (Color(0xFF3ED6C0), Color(0xFF0E3D3A)),
    ];

    final base = <SmartMixPlaylist>[];
    for (var i = 0; i < generated.length; i++) {
      final mix = generated[i];
      final g = gradients[i % gradients.length];
      base.add(
        SmartMixPlaylist(
          id: mix.id,
          title: mix.title,
          description: mix.description,
          gradientStart: g.$1,
          gradientEnd: g.$2,
          tracks: mix.tracks,
        ),
      );
    }

    if (mood == MusicMood.any) {
      return base;
    }

    // Mood variant: score each mix through the mood filter, keep the top
    // slice, and tag the copy so the rail shows what's playing for this mood.
    final filtered = <SmartMixPlaylist>[];
    for (final mix in base) {
      final scored = MusicMoodFilter.filterTop(
        mix.tracks,
        mood,
        limit: mix.tracks.length,
      );
      if (scored.isEmpty) continue;
      filtered.add(
        mix.copyWith(
          description: '${mood.label} · ${mix.description}',
          tracks: scored.take(mix.tracks.length).toList(),
        ),
      );
    }

    // Nothing in the pool fits this mood — fall back to the unfiltered base
    // so a mood chip never leaves the home rails empty.
    if (filtered.isEmpty) {
      return base;
    }
    return filtered;
  }

  /// Live content for the user's vibe: one day-cached search per chosen
  /// style (shared keys with the home "Your Vibe" rail) plus one search
  /// per favorite artist, capped so a big favorites list stays cheap.
  /// Every miss is one live query; every hit is the same-day cache.
  Future<List<MusicTrack>> _fetchVibePool(MusicVibeProfile vibe) async {
    if (!vibe.hasSignal) return const [];
    final profHash = vibe.profKey.hashCode;

    final futures = <Future<List<MusicTrack>>>[
      for (final style in MusicOnboardingService.selectedStyles.value)
        MusicTrendService.instance
            .getOr<List<MusicTrack>>(
              'vibe_style_${style.name}_$profHash',
              () => MusicService.instance.searchTracks(style.searchQuery),
            )
            .catchError((_) => <MusicTrack>[]),
      for (final artist in vibe.favoriteArtists.take(4))
        MusicTrendService.instance
            .getOr<List<MusicTrack>>(
              'vibe_fav_${artist.hashCode}_$profHash',
              () => MusicService.instance.searchTracks(artist),
            )
            .catchError((_) => <MusicTrack>[]),
    ];

    final settled = await Future.wait(futures);
    final out = <MusicTrack>[];
    final seen = <String>{};
    for (final list in settled) {
      for (final t in list) {
        if (seen.add(t.id)) out.add(t);
      }
    }
    return out;
  }
}
