import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/music/music_track.dart';
import 'music_player_controller.dart';
import 'music_service.dart';

class MusicRadioService {
  MusicRadioService._();
  static final MusicRadioService instance = MusicRadioService._();

  /// Generates a curated, related radio queue based on a seed track
  Future<List<MusicTrack>> generateSongRadio(MusicTrack seedTrack) async {
    final results = <MusicTrack>[seedTrack];
    final seenIds = <String>{seedTrack.id};

    try {
      // 1. Fetch tracks from the same artist
      final artistTracks = await MusicService.instance.searchTracks(seedTrack.artist);
      for (final t in artistTracks) {
        if (!seenIds.contains(t.id)) {
          seenIds.add(t.id);
          results.add(t);
        }
      }

      // 2. Fetch tracks matching the song title / theme keywords
      final titleQuery = seedTrack.title.split(RegExp(r'[\(\[\-–]')).first.trim();
      if (titleQuery.isNotEmpty && titleQuery != seedTrack.title) {
        final titleTracks = await MusicService.instance.searchTracks(titleQuery);
        for (final t in titleTracks) {
          if (!seenIds.contains(t.id)) {
            seenIds.add(t.id);
            results.add(t);
          }
        }
      }

      // 3. If still short, backfill from featured sections
      if (results.length < 15) {
        final sections = await MusicService.instance.fetchFeaturedSections();
        for (final list in sections.values) {
          for (final t in list) {
            if (!seenIds.contains(t.id)) {
              seenIds.add(t.id);
              results.add(t);
              if (results.length >= 25) break;
            }
          }
          if (results.length >= 25) break;
        }
      }
    } catch (e) {
      debugPrint('[MusicRadioService] Radio generation fallback: $e');
    }

    return results;
  }

  /// One-touch launcher: builds the radio queue and begins playback
  Future<void> startRadioForTrack(BuildContext context, MusicTrack seedTrack) async {
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
              child: CircularProgressIndicator(color: Color(0xFF7C5CFF), strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tuning into "${seedTrack.title}" Radio...',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    final queue = await generateSongRadio(seedTrack);
    await MusicPlayerController.instance.playTrack(seedTrack, playlistQueue: queue);

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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
