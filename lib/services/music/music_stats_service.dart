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

  int _totalMinutes = 0;
  Map<String, int> _trackCounts = {};
  Map<String, int> _artistCounts = {};
  Map<String, String> _trackTitles = {};
  Map<String, String> _trackArtists = {};
  Map<String, String> _trackCovers = {};

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
    } catch (e) {
      debugPrint('[MusicStatsService] Init error: $e');
    }
  }

  Future<void> recordTrackPlay(MusicTrack track) async {
    _totalMinutes += (track.durationSeconds > 0 ? (track.durationSeconds / 60).round() : 3);
    _trackCounts[track.id] = (_trackCounts[track.id] ?? 0) + 1;
    _artistCounts[track.artist] = (_artistCounts[track.artist] ?? 0) + 1;

    _trackTitles[track.id] = track.title;
    _trackArtists[track.id] = track.artist;
    _trackCovers[track.id] = track.coverUrl;

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
    } catch (_) {}
  }

  List<MapEntry<String, int>> get topArtists {
    final entries = _artistCounts.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).toList();
  }

  List<({String id, String title, String artist, String coverUrl, int playCount})> get topTracks {
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
