import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/music/music_track.dart';
import 'music_engagement_service.dart';
import 'music_player_controller.dart';
import 'music_service.dart';

class MusicRadioService {
  MusicRadioService._();
  static final MusicRadioService instance = MusicRadioService._();

  /// Test seam: when set, every radio search goes through this instead
  /// of the network (unit tests inject a deterministic provider).
  @visibleForTesting
  Future<List<MusicTrack>> Function(String query)? searchSeam;

  Future<List<MusicTrack>> _search(String query) {
    final seam = searchSeam;
    if (seam != null) return seam(query);
    return MusicService.instance.searchTracks(query);
  }

  /// Generates a curated, related radio queue based on a seed track.
  ///
  /// Round 2: candidates still come ONLY from seed metadata through the
  /// search surface (artist block + title-keyword block + the shared
  /// featured rail as backfill), but the ordering goes through the
  /// engagement core — same-artist/album/language affinity, taste and
  /// session skip/boost weighting, deterministic day-seeded tie-break.
  /// No fixed fallback song lists anywhere.
  Future<List<MusicTrack>> generateSongRadio(MusicTrack seedTrack) async {
    final results = <MusicTrack>[seedTrack];
    final seenIds = <String>{seedTrack.id};

    void addAll(List<MusicTrack> list) {
      for (final t in list) {
        if (!seenIds.contains(t.id)) {
          seenIds.add(t.id);
          results.add(t);
        }
      }
    }

    try {
      // 1. Same artist
      final artist = seedTrack.artist.trim();
      if (artist.isNotEmpty) {
        try {
          addAll((await _search(artist)).toList());
        } catch (_) {}
      }

      // 2. Title / theme keywords
      final titleQuery = seedTrack.title
          .split(RegExp(r'[\(\[\-–]'))
          .first
          .trim();
      if (titleQuery.isNotEmpty && titleQuery != seedTrack.title) {
        try {
          addAll((await _search(titleQuery)).toList());
        } catch (_) {}
      }

      // 2.5 Part C: vibe-first pool — same feel, any artist. The user's
      // style phrases and favorite artists feed the candidate set through
      // the same search seam (tests stay deterministic), before the
      // featured-rail backfill. rankUpNext below still keeps taste
      // continuation: the seed's own affinity leads the final order.
      final vibe = MusicVibeProfile.fromOnboarding();
      if (vibe.hasSignal) {
        final vibeQueries = [
          ...vibe.styleQueries.take(3),
          ...vibe.favoriteArtists.take(3),
        ];
        for (final q in vibeQueries) {
          if (results.length >= 20) break;
          try {
            addAll((await _search(q)).toList());
          } catch (_) {}
        }
      }

      // 3. If still short, backfill from the shared featured rails
      if (results.length < 15) {
        final sections = await MusicService.instance.fetchFeaturedSections();
        for (final list in sections.values) {
          addAll(list);
          if (results.length >= 25) break;
        }
      }
    } catch (e) {
      debugPrint('[MusicRadioService] Radio generation fallback: $e');
    }

    // Round 2: reorder everything after the seed through the
    // engagement core (session-aware, day-rotated, deterministic).
    final candidates = results.skip(1).toList();
    final ranked = MusicEngagementCore.rankUpNext(
      seed: seedTrack,
      candidates: candidates,
      skips: const {},
      boosts: const {},
      daySeed: MusicEngagementCore.daySeed(DateTime.now()),
      limit: candidates.length,
    );

    return [seedTrack, ...ranked];
  }

  /// One-touch launcher: builds the radio queue and begins playback
  Future<void> startRadioForTrack(
    BuildContext context,
    MusicTrack seedTrack,
  ) async {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1B1E2E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Color(0xFF7C5CFF),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tuning into "${seedTrack.title}" Radio...',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    final queue = await generateSongRadio(seedTrack);
    await MusicPlayerController.instance.playTrack(
      seedTrack,
      playlistQueue: queue,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF7C5CFF),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.radio_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Now Playing: ${seedTrack.artist} Song Radio (${queue.length} songs)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}
