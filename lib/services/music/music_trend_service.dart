import 'dart:async';

import '../../models/music/music_track.dart';
import 'music_engagement_service.dart';

/// Trend cache (Round 2): chart/editorial lists are fetched ONCE per
/// day and reused across all surfaces for 24h, and every consumer
/// rotates the cached window with the day seed so two surfaces never
/// show the exact same slice twice in a row.
///
/// The cache is keyed `railKey` + the bucketed date, so a day flip
/// invalidates naturally — no timers, no background refresh jobs.
class _TrendEntry<T> {
  final T value;
  final DateTime expiresAt;
  _TrendEntry(this.value, this.expiresAt);
}

class MusicTrendService {
  MusicTrendService._();
  static final MusicTrendService instance = MusicTrendService._();

  final Map<String, _TrendEntry<dynamic>> _cache = {};
  final Map<String, Future<dynamic>> _inFlight = {};

  DateTime get _now => DateTime.now();

  String _fullKey(String key, DateTime now) {
    final seed = MusicEngagementCore.daySeed(now);
    return '${key}_d$seed';
  }

  bool _fresh(_TrendEntry<dynamic>? e, DateTime now) =>
      e != null && e.expiresAt.isAfter(now);

  /// Returns the cached value for [key] if it is fresher than [ttl],
  /// otherwise loads it via [loader], stores it, and returns it.
  /// Concurrent callers for the same key share one in-flight load.
  Future<T> getOr<T>(
    String key,
    Future<T> Function() loader, {
    Duration ttl = const Duration(hours: 24),
  }) async {
    final now = _now;
    final fullKey = _fullKey(key, now);
    final e = _cache[fullKey];
    if (_fresh(e, now)) return e!.value as T;

    // 24h TTL: an entry fetched earlier today may still be valid under
    // the same daily key even if first stored yesterday evening.
    final sameDay = _cache.entries
        .where((entry) => entry.key.startsWith('${key}_d'))
        .where((entry) => _fresh(entry.value, now))
        .toList();
    if (sameDay.isNotEmpty) {
      return sameDay.first.value.value as T;
    }

    final inFlight = _inFlight[fullKey];
    if (inFlight != null) {
      return (inFlight as Future<T>).then((_) => _cache[fullKey]!.value as T);
    }

    final f = loader()
        .then((value) {
          final stamp = _now;
          _cache[fullKey] = _TrendEntry<T>(value, stamp.add(ttl));
          _inFlight.remove(fullKey);
          // Prune anything older than yesterday to keep the map tiny.
          _cache.removeWhere((_, v) => !_fresh(v, stamp));
          return value;
        })
        .catchError((Object failure) {
          _inFlight.remove(fullKey);
          throw failure;
        });
    _inFlight[fullKey] = f;
    return f;
  }

  /// Day-rotated slice of a cached rail — the same backing list yields
  /// a different window per day, so no two days open identically.
  List<MusicTrack> rotateTracks(
    String key,
    List<MusicTrack> items, {
    required DateTime now,
    int take = 10,
  }) {
    if (items.isEmpty) return const [];
    return MusicEngagementCore.rotateRail(
      items,
      daySeed: MusicEngagementCore.daySeed(now),
      take: take,
    );
  }

  /// Test seam: drop the entire cache.
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  int get debugEntryCount => _cache.length;
}
