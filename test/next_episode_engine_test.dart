import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/movie/video.dart';
import 'package:dizzy/services/stream/next_episode_engine.dart';

Video _ep(int season, int episode, {String id = ''}) {
  return Video(
    id: id.isNotEmpty ? id : 's${season}e$episode',
    title: 'S$season E$episode',
    season: season,
    episode: episode,
  );
}

void main() {
  group('computeNext', () {
    test('next episode is N+1 in same season', () {
      final eps = [_ep(1, 1), _ep(1, 2), _ep(1, 3)];
      final next = NextEpisodeEngine.computeNext(
          episodes: eps, currentSeason: 1, currentEpisode: 2);
      expect(next, isNotNull);
      expect(next!.isSeriesFinale, isFalse);
      expect(next.episode.season, 1);
      expect(next.episode.episode, 3);
    });

    test('season finale wraps to next season episode 1', () {
      final eps = [_ep(1, 1), _ep(1, 12), _ep(2, 1), _ep(2, 2)];
      final next = NextEpisodeEngine.computeNext(
          episodes: eps, currentSeason: 1, currentEpisode: 12);
      expect(next, isNotNull);
      expect(next!.isSeriesFinale, isFalse);
      expect(next.episode.season, 2);
      expect(next.episode.episode, 1);
    });

    test('series finale returns isSeriesFinale', () {
      final eps = [_ep(1, 1), _ep(2, 5)];
      final next = NextEpisodeEngine.computeNext(
          episodes: eps, currentSeason: 2, currentEpisode: 5);
      expect(next, isNotNull);
      expect(next!.isSeriesFinale, isTrue);
    });

    test('unsorted episode list is ordered before computing', () {
      final eps = [_ep(2, 2), _ep(1, 3), _ep(1, 4), _ep(2, 1)];
      final next = NextEpisodeEngine.computeNext(
          episodes: eps, currentSeason: 1, currentEpisode: 4);
      expect(next, isNotNull);
      expect(next!.episode.season, 2);
      expect(next.episode.episode, 1);
    });

    test('null when episode list empty', () {
      final next = NextEpisodeEngine.computeNext(
          episodes: [], currentSeason: 1, currentEpisode: 1);
      expect(next, isNull);
    });

    test('null when current episode not in list', () {
      final eps = [_ep(1, 1), _ep(1, 2)];
      final next = NextEpisodeEngine.computeNext(
          episodes: eps, currentSeason: 3, currentEpisode: 7);
      expect(next, isNull);
    });
  });

  group('engine lifecycle', () {
    test('dispose clears prefetched state', () {
      final engine = NextEpisodeEngine();
      engine.dispose();
      expect(engine.prefetchedSource, isNull);
      expect(engine.prefetchedEpisode, isNull);
      expect(engine.isRunning, isFalse);
    });
  });
}
