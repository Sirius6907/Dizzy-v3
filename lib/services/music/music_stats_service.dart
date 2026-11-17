import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/music/music_track.dart';

class MusicStatsService {
  MusicStatsService._();
  static final MusicStatsService instance = MusicStatsService._();

  static const String _keyTotalMinutes = 'music_stats_total_mins';
  static const String _keyTrackCounts = 'music_stats_track_counts';
  static const String _keyArtistCounts = 'music_stats_artist_counts';
  static const String _keyTrackMeta = 'music_stats_track_meta';

  /// Timestamped play log (2026-11-12, India recency rails). Lifetime
  /// counters cannot answer "what did I play this week", and the home
  /// feed needs that to mirror a weekly/monthly chart cadence.
  static const String _keyPlayLog = 'music_stats_play_log';

  /// Bounded so prefs stay small on a long-lived install.
  static const int _playLogCap = 500;

  /// Recency windows the home feed asks for.
  static const Duration weekWindow = Duration(days: 7);
  static const Duration monthWindow = Duration(days: 30);

  int _totalMinutes = 0;
  Map<String, int> _trackCounts = {};
  Map<String, int> _artistCounts = {};
  Map<String, String> _trackTitles = {};
  Map<String, String> _trackArtists = {};
  Map<String, String> _trackCovers = {};

  /// Newest last. Each entry: t (epoch ms), id, artist, title, cover.
  List<Map<String, dynamic>> _playLog = [];

  int get totalMinutes => _totalMinutes;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _totalMinutes = prefs.getInt(_keyTotalMinutes) ?? 0;

      final trackCountsStr = prefs.getString(_keyTrackCounts);
      if (trackCountsStr != null) {
        _trackCounts = Map<String, int>.from(jsonDecode(trackCountsStr));
      }

      final artistCountsStr = prefs.getString(_keyArtistCounts);
      if (artistCountsStr != null) {
        _artistCounts = Map<String, int>.from(jsonDecode(artistCountsStr));
      }

      final metaStr = prefs.getString(_keyTrackMeta);
      if (metaStr != null) {
        final decoded = jsonDecode(metaStr) as Map<String, dynamic>;
        _trackTitles = Map<String, String>.from(decoded['titles'] ?? {});
        _trackArtists = Map<String, String>.from(decoded['artists'] ?? {});
        _trackCovers = Map<String, String>.from(decoded['covers'] ?? {});
      }

      final logStr = prefs.getString(_keyPlayLog);
      if (logStr != null) {
        final decoded = jsonDecode(logStr);
        if (decoded is List) {
          _playLog = [
            for (final row in decoded)
              if (row is Map) Map<String, dynamic>.from(row),
          ];
        }
      }
    } catch (e) {
      debugPrint('[MusicStatsService] Init error: $e');
    }
  }

  Future<void> recordTrackPlay(MusicTrack track) async {
    _totalMinutes += (track.durationSeconds > 0
        ? (track.durationSeconds / 60).round()
        : 3);
    _trackCounts[track.id] = (_trackCounts[track.id] ?? 0) + 1;
    _artistCounts[track.artist] = (_artistCounts[track.artist] ?? 0) + 1;

    _trackTitles[track.id] = track.title;
    _trackArtists[track.id] = track.artist;
    _trackCovers[track.id] = track.coverUrl;

    _playLog.add({
      't': DateTime.now().millisecondsSinceEpoch,
      'id': track.id,
      'a': track.artist,
      'ti': track.title,
      'al': track.album,
      'c': track.coverUrl,
      'd': track.durationSeconds,
    });
    if (_playLog.length > _playLogCap) {
      _playLog = _playLog.sublist(_playLog.length - _playLogCap);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyTotalMinutes, _totalMinutes);
      await prefs.setString(_keyTrackCounts, jsonEncode(_trackCounts));
      await prefs.setString(_keyArtistCounts, jsonEncode(_artistCounts));
      await prefs.setString(
        _keyTrackMeta,
        jsonEncode({
          'titles': _trackTitles,
          'artists': _trackArtists,
          'covers': _trackCovers,
        }),
      );
      await prefs.setString(_keyPlayLog, jsonEncode(_playLog));
    } catch (_) {}
  }

  List<MapEntry<String, int>> get topArtists {
    final entries = _artistCounts.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).toList();
  }

  List<
    ({String id, String title, String artist, String coverUrl, int playCount})
  >
  get topTracks {
    final entries = _trackCounts.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));

    return entries.take(5).map((e) {
      return (
        id: e.key,
        title: _trackTitles[e.key] ?? 'Unknown Track',
        artist: _trackArtists[e.key] ?? 'Unknown Artist',
        coverUrl: _trackCovers[e.key] ?? '',
        playCount: e.value,
      );
    }).toList();
  }

  /// Plays inside [window], newest-first windows resolved by the caller.
  /// Empty when the log holds nothing recent — callers hide the rail
  /// rather than fall back to lifetime totals (that would mislabel old
  /// listening as "this week").
  List<Map<String, dynamic>> _logSince(Duration window) {
    if (_playLog.isEmpty) return const [];
    final cutoff = DateTime.now().subtract(window).millisecondsSinceEpoch;
    final out = <Map<String, dynamic>>[];
    for (final row in _playLog) {
      final t = (row['t'] as num?)?.toInt();
      if (t != null && t >= cutoff) out.add(row);
    }
    return out;
  }

  /// Top artists played inside [window] (1 week / 1 month rails).
  List<MapEntry<String, int>> topArtistsSince(Duration window, {int take = 5}) {
    final counts = <String, int>{};
    for (final row in _logSince(window)) {
      final artist = (row['a'] ?? '').toString().trim();
      if (artist.isEmpty) continue;
      counts[artist] = (counts[artist] ?? 0) + 1;
    }
    final entries = counts.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(take).toList();
  }

  /// Top tracks played inside [window]. Same record shape as [topTracks]
  /// so the existing home rail renders both without a second model.
  List<
    ({String id, String title, String artist, String coverUrl, int playCount})
  >
  topTracksSince(Duration window, {int take = 5, int minPlays = 1}) {
    final counts = <String, int>{};
    final meta = <String, Map<String, dynamic>>{};
    for (final row in _logSince(window)) {
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      counts[id] = (counts[id] ?? 0) + 1;
      meta[id] = row;
    }
    final entries = counts.entries.where((e) => e.value >= minPlays).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(take).map((e) {
      final row = meta[e.key] ?? const <String, dynamic>{};
      return (
        id: e.key,
        title: (row['ti'] ?? _trackTitles[e.key] ?? 'Unknown Track').toString(),
        artist: (row['a'] ?? _trackArtists[e.key] ?? 'Unknown Artist')
            .toString(),
        coverUrl: (row['c'] ?? _trackCovers[e.key] ?? '').toString(),
        playCount: e.value,
      );
    }).toList();
  }

  /// Recency rail content, already in the app's shared track model so the
  /// home rows can render it without a second mapping step.
  List<MusicTrack> recentTracks(
    Duration window, {
    int take = 15,
    int minPlays = 1,
  }) {
    final counts = <String, int>{};
    final meta = <String, Map<String, dynamic>>{};
    for (final row in _logSince(window)) {
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      counts[id] = (counts[id] ?? 0) + 1;
      meta[id] = row;
    }
    final entries = counts.entries.where((e) => e.value >= minPlays).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(take).map((e) {
      final row = meta[e.key] ?? const <String, dynamic>{};
      return MusicTrack(
        id: e.key,
        title: (row['ti'] ?? _trackTitles[e.key] ?? 'Unknown Track').toString(),
        artist: (row['a'] ?? _trackArtists[e.key] ?? 'Unknown Artist')
            .toString(),
        album: (row['al'] ?? 'Your listening').toString(),
        coverUrl: (row['c'] ?? _trackCovers[e.key] ?? '').toString(),
        durationSeconds: (row['d'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  String get musicalPersona {
    if (_totalMinutes > 600) {
      return 'Sonic Virtuoso 👑';
    } else if (topArtists.isNotEmpty && topArtists.first.value > 10) {
      return 'Superfan Loyal 💖';
    } else if (_totalMinutes > 180) {
      return 'Groove Explorer 🚀';
    } else {
      return 'Eclectic Melophile 🎵';
    }
  }
}
