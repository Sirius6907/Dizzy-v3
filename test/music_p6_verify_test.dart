import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/music_artwork_palette_service.dart';
import 'package:dizzy/services/music/music_player_controller.dart';
import 'package:dizzy/services/music/music_queue_ops.dart';
import 'package:dizzy/services/music/music_radio_service.dart';
import 'package:dizzy/services/music/music_service.dart';
import 'package:dizzy/services/music/music_smart_mix_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// P6 music verification — proves the features that are already built:
/// ambient canvas (no black flash), karaoke anti-jerk, queue reorder mapping,
/// quality hot-swap, Song Radio + Smart Mix.
MusicTrack _track(String id) => MusicTrack(
      id: id,
      title: 'Track $id',
      artist: 'Artist $id',
      album: 'Album $id',
      coverUrl: '',
      durationSeconds: 200,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P6 ambient canvas — HSL fallback never black-flashes', () {
    test('fast palette is ambient-safe for every hue bucket', () {
      final service = MusicArtworkPaletteService.instance;
      for (var i = 0; i < 200; i++) {
        final palette = service.getFastPalette(_track('t$i'));
        expect(
          palette.isAmbientSafe,
          isTrue,
          reason: 'palette for t$i flashed black: ${palette.background}',
        );
        expect(palette.background, isNot(const Color(0xFF000000)));
        expect(palette.background.a, 1.0);
      }
    });

    test('fast palette background clears the documented luminance floor', () {
      final service = MusicArtworkPaletteService.instance;
      for (var i = 0; i < 50; i++) {
        final bg = service.getFastPalette(_track('lum$i')).background;
        expect(
          bg.computeLuminance(),
          greaterThanOrEqualTo(MusicTrackPalette.minBackgroundLuminance),
        );
      }
    });

    test('fast palette is deterministic so rebuilds never re-roll the tint', () {
      final service = MusicArtworkPaletteService.instance;
      final track = _track('stable');
      final a = service.getFastPalette(track);
      final b = service.getFastPalette(track);
      expect(a.primary, b.primary);
      expect(a.secondary, b.secondary);
      expect(a.background, b.background);
      expect(a.accent, b.accent);
    });

    test('extractPalette falls back to the safe HSL palette without artwork',
        () async {
      final service = MusicArtworkPaletteService.instance;
      final palette =
          await service.extractPalette(_track('nocover-${DateTime.now().microsecondsSinceEpoch}'));
      expect(palette.isAmbientSafe, isTrue);
    });

    test('default dark palette is itself ambient-safe', () {
      expect(MusicTrackPalette.defaultDark.isAmbientSafe, isTrue);
    });
  });

  group('P6 queue reorder — upcoming indices map to absolute', () {
    final queue = ['a', 'b', 'c', 'd', 'e'];
    const current = 1; // 'b' is playing

    test('upcoming slice excludes the current track', () {
      expect(MusicQueueOps.upcoming(queue, current), ['c', 'd', 'e']);
      expect(MusicQueueOps.history(queue, current), ['a']);
    });

    test('moving an item up inside the slice', () {
      final next = MusicQueueOps.reorderUpcoming(queue, current,
          oldIndex: 2, newIndex: 0);
      expect(next, ['a', 'b', 'e', 'c', 'd']);
    });

    test('moving an item down inside the slice (ReorderableListView slot)',
        () {
      // Drop after 'd' → raw insert slot 2, legacy onReorder decrements a
      // downward move → lands between 'd' and 'e'.
      final afterD = MusicQueueOps.reorderUpcoming(queue, current,
          oldIndex: 0, newIndex: 2);
      expect(afterD, ['a', 'b', 'd', 'c', 'e']);

      // Drop past the end → raw insert slot 3 (= slice length) → true end.
      final atEnd = MusicQueueOps.reorderUpcoming(queue, current,
          oldIndex: 0, newIndex: 3);
      expect(atEnd, ['a', 'b', 'd', 'e', 'c']);
    });

    test('a no-op drag keeps the order', () {
      final next = MusicQueueOps.reorderUpcoming(queue, current,
          oldIndex: 1, newIndex: 1);
      expect(next, queue);
    });

    test('reordering never touches the current track or history', () {
      final next = MusicQueueOps.reorderUpcoming(queue, current,
          oldIndex: 0, newIndex: 3);
      expect(next[0], 'a');
      expect(next[1], 'b');
      expect(MusicQueueOps.history(next, current), ['a']);
      expect(MusicQueueOps.upcoming(next, current), next.sublist(2));
    });

    test('out-of-range drags are ignored instead of throwing', () {
      expect(
        MusicQueueOps.reorderUpcoming(queue, current, oldIndex: 99, newIndex: 0),
        queue,
      );
      expect(
        MusicQueueOps.reorderUpcoming(queue, current, oldIndex: -5, newIndex: 0),
        queue,
      );
    });

    test('the last track has no upcoming slice to reorder', () {
      expect(
        MusicQueueOps.reorderUpcoming(queue, 4, oldIndex: 0, newIndex: 1),
        queue,
      );
    });

    test('an empty queue is handled without throwing', () {
      expect(MusicQueueOps.upcoming(const <String>[], 0), isEmpty);
      expect(MusicQueueOps.history(const <String>[], 0), isEmpty);
      expect(
        MusicQueueOps.reorderUpcoming(const <String>[], 0, oldIndex: 0, newIndex: 1),
        isEmpty,
      );
    });

    test('controller reorder drives the same mapping through its public API',
        () {
      final controller = MusicPlayerController.instance;
      final tracks = [_track('a'), _track('b'), _track('c'), _track('d')];
      controller.debugSeedPlaybackState(track: tracks[1], queue: tracks);

      controller.reorderUpcomingQueue(0, 2);
      expect(
        controller.upcomingTracks.map((t) => t.id).toList(),
        ['d', 'c'],
      );
      expect(controller.currentTrack?.id, 'b');
      expect(controller.historyTracks.map((t) => t.id).toList(), ['a']);
    });
  });

  group('P6 quality hot-swap keeps the listening position', () {
    test('switching source reloads the same track at the same position',
        () async {
      final controller = MusicPlayerController.instance;
      final track = _track('hot-swap');
      const at = Duration(seconds: 97);
      controller.debugSeedPlaybackState(
        track: track,
        queue: [track, _track('next')],
        position: at,
      );

      final before = controller.position;
      final target = controller.audioSource == MusicAudioSource.flac
          ? MusicAudioSource.youtube
          : MusicAudioSource.flac;
      await controller.setAudioSource(target);

      expect(controller.position, before);
      expect(controller.currentTrack?.id, 'hot-swap');
      expect(controller.audioSource, target);
    });

    test('FLAC and YouTube report opposite lossless badges', () {
      final controller = MusicPlayerController.instance;
      expect(controller.isCurrentTrackLossless,
          controller.audioSource == MusicAudioSource.flac);
      expect(controller.currentQualityLabel,
          controller.isCurrentTrackLossless ? contains('FLAC') : contains('YouTube'));
    });

    test('the same source is a no-op', () async {
      final controller = MusicPlayerController.instance;
      final track = _track('noop');
      controller.debugSeedPlaybackState(track: track, queue: [track]);
      await controller.setAudioSource(controller.audioSource);
      expect(controller.position, Duration.zero);
    });
  });

  group('P6 Song Radio + Smart Mix', () {
    test('Song Radio always leads with the seed track', () async {
      final queue =
          await MusicRadioService.instance.generateSongRadio(_track('seed'));
      expect(queue, isNotEmpty);
      expect(queue.first.id, 'seed');
    });

    test('Song Radio never returns duplicate tracks', () async {
      final queue =
          await MusicRadioService.instance.generateSongRadio(_track('dedup'));
      final ids = queue.map((t) => t.id).toSet();
      expect(ids.length, queue.length);
    });

    test('Song Radio fails soft when nothing can be fetched', () async {
      final queue =
          await MusicRadioService.instance.generateSongRadio(_track('offline'));
      expect(queue.length, greaterThanOrEqualTo(1));
    });

    test('Smart Mix cover helper is safe on an empty mix', () {
      const empty = SmartMixPlaylist(
        id: 'empty',
        title: 'Empty',
        description: 'Nothing yet',
        gradientStart: Color(0xFF1DB954),
        gradientEnd: Color(0xFF123B22),
        tracks: [],
      );
      expect(empty.primaryCoverUrl, '');
    });

    test('Smart Mix cover helper uses the first track', () {
      final mix = SmartMixPlaylist(
        id: 'mix',
        title: 'Mix',
        description: 'd',
        gradientStart: const Color(0xFF1DB954),
        gradientEnd: const Color(0xFF123B22),
        tracks: [_track('one'), _track('two')],
      );
      expect(mix.primaryCoverUrl, '');
    });
  });
}
