import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'progress_merge.dart';

/// F3 — Continue Watching that follows the person, not the phone.
///
/// Every resume point is keyed `profileId::mediaId`, so two people sharing
/// one tablet never see each other's place. The merge rule lives in
/// [ProgressMerge] (max progress wins); this file only stores and wires.
///
/// Reinstall restore: the whole map lives under one preferences key, so
/// coming back on a new phone with a restored cloud copy replays the exact
/// same rows. Nothing here needs a login — the anonymous session is enough.
class ProfileProgressStore {
  static const _storageKey = 'profile_progress_v1';

  static final ValueNotifier<Map<String, MediaProgress>> rows =
      ValueNotifier<Map<String, MediaProgress>>({});

  static bool _loaded = false;

  /// Reads storage once. Safe to call from more than one place.
  static Future<void> initialize() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = <String, MediaProgress>{};
      for (final entry in decoded.entries) {
        final v = entry.value;
        if (v is! Map) continue;
        // Corrupt row: skip it, keep the rest of the profile usable.
        final row = _decode(entry.key, v);
        if (row != null) parsed[entry.key] = row;
      }
      rows.value = parsed;
    } catch (_) {
      // Unreadable blob = a fresh start, never a crash on launch.
      rows.value = {};
    }
  }

  static MediaProgress? _decode(String key, Map<dynamic, dynamic> json) {
    try {
      final pos = json['positionSeconds'];
      final total = json['totalDurationSeconds'];
      final seen = json['lastWatchedAt'];
      final meta = json['meta'];
      return MediaProgress(
        key: json['key']?.toString() ?? key,
        positionSeconds: pos is int ? pos : int.tryParse(pos?.toString() ?? '') ?? 0,
        totalDurationSeconds:
            total is int ? total : int.tryParse(total?.toString() ?? '') ?? 0,
        lastWatchedAt:
            DateTime.tryParse(seen?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        meta: meta is Map ? Map<String, dynamic>.from(meta) : const {},
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _encode(MediaProgress r) => {
        'key': r.key,
        'positionSeconds': r.positionSeconds,
        'totalDurationSeconds': r.totalDurationSeconds,
        'lastWatchedAt': r.lastWatchedAt.toIso8601String(),
        'meta': r.meta,
      };

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({for (final e in rows.value.entries) e.key: _encode(e.value)}),
    );
  }

  /// Save one resume point. Progress never moves backwards: a smaller
  /// position than the one already stored is ignored, so a late-arriving
  /// tick from a paused player cannot rewind the bar.
  static Future<void> save({
    required String profileId,
    required String mediaId,
    required int positionSeconds,
    int totalDurationSeconds = 0,
    DateTime? lastWatchedAt,
    Map<String, dynamic> meta = const {},
  }) async {
    if (profileId.isEmpty || mediaId.isEmpty) return;
    final key = MediaProgress.forProfile(profileId, mediaId);
    final incoming = MediaProgress(
      key: key,
      positionSeconds: positionSeconds < 0 ? 0 : positionSeconds,
      totalDurationSeconds: totalDurationSeconds < 0 ? 0 : totalDurationSeconds,
      lastWatchedAt: lastWatchedAt ?? DateTime.now(),
      meta: meta,
    );
    final mine = rows.value[key];
    rows.value = ProgressMerge.merge(
      mine == null ? {} : {key: mine},
      {key: incoming},
    ).$1;
    await _persist();
  }

  /// All rows for one profile, freshest first.
  static List<MediaProgress> forProfile(String profileId) =>
      ProgressMerge.forProfile(rows.value, profileId);

  /// The stored row for one media, or `null`.
  static MediaProgress? peek(String profileId, String mediaId) =>
      rows.value[MediaProgress.forProfile(profileId, mediaId)];

  /// Fold a cloud / other-device copy in using the max rule. Returns how
  /// much came back, so the UI can say "12 titles are back with you".
  static Future<ProgressMergeReport> mergeIncoming(
    Map<String, MediaProgress> incoming,
  ) async {
    final (merged, report) = ProgressMerge.merge(rows.value, incoming);
    rows.value = merged;
    await _persist();
    return report;
  }

  /// The whole map, for handing to the merge edge function.
  static Map<String, MediaProgress> snapshot() =>
      Map<String, MediaProgress>.from(rows.value);

  /// Wipe one profile's rows (used when a profile is deleted).
  static Future<void> clearProfile(String profileId) async {
    if (profileId.isEmpty) return;
    final next = <String, MediaProgress>{
      for (final e in rows.value.entries)
        if (MediaProgress.splitKey(e.key)?.$1 != profileId) e.key: e.value,
    };
    rows.value = next;
    await _persist();
  }

  /// Test hook: reset in-memory state so a test can start clean.
  @visibleForTesting
  static void debugReset() {
    rows.value = {};
    _loaded = false;
  }
}
