import '../../models/music/music_track.dart';

/// Listening mood selector for the Music home. `any` keeps the neutral
/// behavior — no reordering, just a deduped slice of the pool.
///
/// The filter is deliberately pure and text-based: MusicTrack carries no
/// genre or year, so mood scoring leans on title/artist/album keyword
/// signals plus a duration band bonus ("chill" likes comfortable lengths,
/// "energetic" likes radio-length club cuts).
enum MusicMood {
  any('Any mood', ''),
  chill('Chill', '🌙'),
  energetic('Energetic', '⚡'),
  happy('Happy', '✨'),
  focus('Focus', '🎯'),
  romance('Romance', '💗'),
  night('Late Night', '🌌');

  final String label;
  final String emoji;

  const MusicMood(this.label, this.emoji);
}

abstract final class MusicMoodFilter {
  /// Keyword signals mapped per mood. Matched case-insensitively against
  /// title + artist + album.
  static const Map<MusicMood, List<String>> _keywords = {
    MusicMood.chill: [
      'chill',
      'calm',
      'breeze',
      'dream',
      'sunset',
      'moonlight',
      'coffee',
      'lazy',
      'soft',
      'ease',
      'lull',
    ],
    MusicMood.energetic: [
      'energy',
      'party',
      'dance',
      'beat',
      'banger',
      'fire',
      'hype',
      'power',
      'pump',
      'workout',
      'hard',
      'stomp',
      'ting',
    ],
    MusicMood.happy: [
      'happy',
      'joy',
      'sunshine',
      'smile',
      'celebrate',
      'celebration',
      'festive',
      'masti',
      'groov',
      'shine',
      'light',
    ],
    MusicMood.focus: [
      'focus',
      'study',
      'work',
      'deep',
      'instrumental',
      'zen',
      'flow',
      'mind',
      'meditation',
      'minimal',
      'ambient',
    ],
    MusicMood.romance: [
      'love',
      'pyaar',
      'ishq',
      'dil',
      'heart',
      'romance',
      'romantic',
      'crush',
      'sapna',
      'forever',
      'wafa',
      'sanam',
    ],
    MusicMood.night: [
      'night',
      'raat',
      'midnight',
      'moon',
      'stars',
      'lofi',
      'lo-fi',
      'sleep',
      'insomnia',
      'nocturne',
      'sham',
    ],
  };

  /// Duration bands in seconds within which a track earns the band bonus.
  /// Chosen loosely around "comfortable single length" per mood energy.
  static const Map<MusicMood, (int, int)> _durationBands = {
    MusicMood.chill: (210, 420),
    MusicMood.energetic: (150, 280),
    MusicMood.happy: (150, 300),
    MusicMood.focus: (210, 480),
    MusicMood.romance: (210, 360),
    MusicMood.night: (200, 480),
  };

  static const double _keywordBonus = 2.0;
  static const double _durationBonus = 1.0;

  static int _keywordHits(MusicTrack track, MusicMood mood) {
    final haystack = '${track.title} ${track.artist} ${track.album}'
        .toLowerCase();
    var hits = 0;
    for (final word in _keywords[mood] ?? const <String>[]) {
      if (haystack.contains(word)) hits++;
    }
    return hits;
  }

  /// Higher score = better fit for the mood. 0 means no signal either way.
  static double scoreFor(MusicTrack track, MusicMood mood) {
    if (mood == MusicMood.any) return 0;
    var score = 0.0;
    score += _keywordHits(track, mood) * _keywordBonus;
    final band = _durationBands[mood];
    if (band != null) {
      final (low, high) = band;
      if (track.durationSeconds >= low && track.durationSeconds <= high) {
        score += _durationBonus;
      }
    }
    return score;
  }

  /// Top `limit` tracks for the mood, highest score first (stable within
  /// equal scores), deduplicated by track id. `MusicMood.any` preserves the
  /// pool order and only dedupes.
  static List<MusicTrack> filterTop(
    List<MusicTrack> pool,
    MusicMood mood, {
    int limit = 12,
  }) {
    if (pool.isEmpty || limit <= 0) return const [];
    final seen = <String>{};
    final deduped = <MusicTrack>[];
    for (final track in pool) {
      if (track.id.isEmpty || !seen.add(track.id)) continue;
      deduped.add(track);
    }
    if (mood == MusicMood.any) {
      return deduped.take(limit).toList();
    }
    final indexed = List<MusicTrack>.from(deduped);
    // Break ties by original position so equal-score tracks keep pool order.
    final order = <String, int>{};
    for (var i = 0; i < deduped.length; i++) {
      order[deduped[i].id] = i;
    }
    indexed.sort((a, b) {
      final byScore = MusicMoodFilter.scoreFor(
        b,
        mood,
      ).compareTo(MusicMoodFilter.scoreFor(a, mood));
      if (byScore != 0) return byScore;
      return (order[a.id] ?? 0).compareTo(order[b.id] ?? 0);
    });
    return indexed.take(limit).toList();
  }

  /// Live search phrase used to pull real mood content instead of only
  /// re-scoring the small trending pool. These are mood adjectives —
  /// queries, never fixed tracks/artists — so the results stay dynamic.
  static String? moodSearchQuery(MusicMood mood) => switch (mood) {
    MusicMood.any => null,
    MusicMood.chill => 'chill relaxing hits',
    MusicMood.energetic => 'party dance hits',
    MusicMood.happy => 'feel good happy hits',
    MusicMood.focus => 'focus instrumental study',
    MusicMood.romance => 'romantic love songs',
    MusicMood.night => 'late night lofi',
  };

  /// Mood rail composition: live mood-searched tracks lead (they ARE the
  /// mood), then the keyword-scored pool fills the remaining slots.
  /// Dedupe by id across both; cap at [limit]. A empty search result
  /// degrades exactly to [filterTop] on the pool. Pure; unit-tested.
  static List<MusicTrack> mergeMoodTracks({
    required List<MusicTrack> searched,
    required List<MusicTrack> pool,
    required MusicMood mood,
    int limit = 12,
  }) {
    if (limit <= 0) return const [];
    final seen = <String>{};
    final merged = <MusicTrack>[];
    for (final track in searched) {
      if (track.id.isEmpty || !seen.add(track.id)) continue;
      merged.add(track);
      if (merged.length >= limit) return merged;
    }
    for (final track in filterTop(pool, mood, limit: limit * 2)) {
      if (merged.length >= limit) break;
      if (track.id.isEmpty || !seen.add(track.id)) continue;
      merged.add(track);
    }
    return merged;
  }
}
