import 'package:flutter/material.dart';
import '../../models/music/music_track.dart';
import 'music_library_service.dart';
import 'music_service.dart';

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
}

class MusicSmartMixService {
  MusicSmartMixService._();
  static final MusicSmartMixService instance = MusicSmartMixService._();

  List<SmartMixPlaylist>? _cachedMixes;

  Future<List<SmartMixPlaylist>> getOrGenerateMixes({bool forceRefresh = false}) async {
    if (_cachedMixes != null && !forceRefresh && _cachedMixes!.isNotEmpty) {
      return _cachedMixes!;
    }

    final liked = MusicLibraryService.instance.likedTracks;
    final recent = MusicLibraryService.instance.recentTracks;
    final featured = await MusicService.instance.fetchFeaturedSections();

    final allPool = <MusicTrack>[...liked, ...recent];
    for (final list in featured.values) {
      allPool.addAll(list);
    }

    // Deduplicate by ID
    final uniquePool = <String, MusicTrack>{};
    for (final t in allPool) {
      uniquePool[t.id] = t;
    }
    final pool = uniquePool.values.toList();

    // 1. Daily Mix 1: Top Favorites & Similar
    final mix1Tracks = pool.take(15).toList();
    final mix1Artists = mix1Tracks.map((t) => t.artist).toSet().take(3).join(', ');

    // 2. Daily Mix 2: Upbeat & High Energy
    final mix2Tracks = pool.skip(10).take(15).toList();
    final mix2Artists = mix2Tracks.map((t) => t.artist).toSet().take(3).join(', ');

    // 3. Discover Weekly: Fresh Discoveries
    final mix3Tracks = pool.reversed.take(15).toList();

    // 4. Night Chill: Acoustic & Mellow Vibes
    final mix4Tracks = pool.skip(5).take(15).toList();

    _cachedMixes = [
      SmartMixPlaylist(
        id: 'smart_mix_daily_1',
        title: 'Daily Mix 1',
        description: mix1Artists.isNotEmpty ? mix1Artists : 'Personalized for you',
        gradientStart: const Color(0xFF1DB954),
        gradientEnd: const Color(0xFF123B22),
        tracks: mix1Tracks,
      ),
      SmartMixPlaylist(
        id: 'smart_mix_daily_2',
        title: 'Daily Mix 2',
        description: mix2Artists.isNotEmpty ? mix2Artists : 'High energy & rhythm',
        gradientStart: const Color(0xFF7C5CFF),
        gradientEnd: const Color(0xFF261852),
        tracks: mix2Tracks,
      ),
      SmartMixPlaylist(
        id: 'smart_mix_discover_weekly',
        title: 'Discover Weekly',
        description: 'Fresh tracks & gems picked for your taste',
        gradientStart: const Color(0xFF00D2EF),
        gradientEnd: const Color(0xFF0D3F59),
        tracks: mix3Tracks,
      ),
      SmartMixPlaylist(
        id: 'smart_mix_night_chill',
        title: 'Chill & Relax',
        description: 'Mellow melodies, acoustic warmth, and focus',
        gradientStart: const Color(0xFFFF4B72),
        gradientEnd: const Color(0xFF4A1024),
        tracks: mix4Tracks,
      ),
    ];

    return _cachedMixes!;
  }
}
