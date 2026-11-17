import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/music/music_mood_filter.dart';
import 'package:dizzy/models/music/music_track.dart';

MusicTrack _t(
  String id,
  String title, {
  String artist = 'A',
  String album = 'Album',
  int seconds = 240,
}) {
  return MusicTrack(
    id: id,
    title: title,
    artist: artist,
    album: album,
    coverUrl: '',
    durationSeconds: seconds,
  );
}

void main() {
  test('keyword mentions beat keyword-free tracks for the same mood', () {
    final night = _t('a', 'Midnight Drive');
    final party = _t('b', 'Party Fire', seconds: 240);
    expect(
      MusicMoodFilter.scoreFor(night, MusicMood.night),
      greaterThan(MusicMoodFilter.scoreFor(party, MusicMood.night)),
    );
    // And the reverse: an energetic keyword track wins the energetic mood.
    expect(
      MusicMoodFilter.scoreFor(party, MusicMood.energetic),
      greaterThan(MusicMoodFilter.scoreFor(night, MusicMood.energetic)),
    );
  });

  test('duration bands break ties when titles carry no keywords', () {
    // No keywords in either title — scoring is decided by duration bands.
    final midLength = _t('a', 'Track One', seconds: 210);
    final longTrack = _t('b', 'Track Two', seconds: 600);
    expect(
      MusicMoodFilter.scoreFor(midLength, MusicMood.energetic),
      greaterThan(MusicMoodFilter.scoreFor(longTrack, MusicMood.energetic)),
    );
  });

  test('filterTop sort, dedupes by id and caps at the limit', () {
    final pool = [
      _t('party', 'Party Fire', seconds: 220),
      _t('dupe', 'Calm Chill Vibes'),
      _t('dupe', 'Calm Chill Vibes'), // same id — must appear once
      _t('filler', 'Track X', seconds: 300),
      _t('filler2', 'Track Y', seconds: 300),
    ];
    final top = MusicMoodFilter.filterTop(pool, MusicMood.chill, limit: 3);
    expect(top.length, 3);
    expect(top.map((t) => t.id).toSet().length, 3);
    // The keyword match must come first.
    expect(top.first.id, 'dupe');
  });

  test('the any mood preserves pool order and still dedupes', () {
    final pool = [
      _t('first', 'Alpha'),
      _t('first', 'Alpha'),
      _t('second', 'Beta'),
    ];
    final top = MusicMoodFilter.filterTop(pool, MusicMood.any, limit: 10);
    expect(top.map((t) => t.id).toList(), ['first', 'second']);
  });

  test('filterTop on an empty pool returns empty instead of crashing', () {
    expect(MusicMoodFilter.filterTop([], MusicMood.happy), isEmpty);
  });

  group('mood search wiring', () {
    test('every concrete mood has a search query; any has none', () {
      for (final mood in MusicMood.values) {
        if (mood == MusicMood.any) {
          expect(MusicMoodFilter.moodSearchQuery(mood), isNull);
        } else {
          expect(
            MusicMoodFilter.moodSearchQuery(mood)!.trim().isNotEmpty,
            isTrue,
            reason: '${mood.name} needs a live search query',
          );
        }
      }
    });

    test('mergeMoodTracks puts searched tracks first, dedupes, fills '
        'remaining slots with scored pool tracks', () {
      final searched = [
        _t('s1', 'Chill Sunset Drive'),
        _t('s2', 'Lo-fi Coffee Rain'),
      ];
      final pool = [
        _t('s1', 'Chill Sunset Drive'), // duplicate of searched — dropped
        _t('p1', 'Calm Breeze'),
        _t('p2', 'Party Fire'),
      ];
      final merged = MusicMoodFilter.mergeMoodTracks(
        searched: searched,
        pool: pool,
        mood: MusicMood.chill,
        limit: 3,
      );
      expect(merged.map((t) => t.id).toList(), ['s1', 's2', 'p1']);
    });

    test('mergeMoodTracks caps at limit and degrades to filterTop when '
        'the search came back empty', () {
      final pool = [
        _t('p1', 'Calm Breeze'),
        _t('p2', 'Party Fire'),
        _t('p3', 'Relax Slow'),
      ];
      final fallback = MusicMoodFilter.mergeMoodTracks(
        searched: [],
        pool: pool,
        mood: MusicMood.chill,
        limit: 2,
      );
      expect(fallback.length, 2);
      expect(
        fallback.map((t) => t.id).toSet(),
        MusicMoodFilter.filterTop(pool, MusicMood.chill, limit: 2)
            .map((t) => t.id)
            .toSet(),
      );
    });
  });
}
