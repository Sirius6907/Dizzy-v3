import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/storage_space_helper.dart';

/// P11 — storage guard: disk-full is a playback killer (cache can't write =
/// stutter) and a download killer. Single choke point with a cached answer
/// so hot paths (position listener) never touch disk.
///
/// Rules (hard):
/// - CRITICAL when free < 500MB OR used > 90%: downloads refuse with an
///   Easy-English line, next-episode prefetch stops, temp purge runs.
/// - Temp purge: `*.part` / `*.tmp` / `*.temp` older than 7 days in the
///   downloads dir are deleted on every refresh (bounded: max 200 files).
/// - Refresh at most every 5 min; unknown space (check failed) = allow.
abstract final class StorageGuard {
  /// Free bytes below which storage counts as critical.
  static const int criticalFreeBytes = 500 * 1024 * 1024;

  /// Used fraction above which storage counts as critical.
  static const double criticalUsedFraction = 0.90;

  /// Temp files older than this are purged on refresh.
  static const Duration tempMaxAge = Duration(days: 7);

  /// Minimum gap between disk probes (df/wmic is slow).
  static const Duration refreshInterval = Duration(minutes: 5);

  static bool _critical = false;
  static DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  /// Cached answer — sync, safe for position listeners and build methods.
  static bool get isCritical => _critical;

  /// Next-episode prefetch needs headroom for buffers + artwork.
  static bool get prefetchAllowed => !_critical;

  /// Pure decision helper (unit-tested).
  static bool decideCritical({
    required int freeBytes,
    required int totalBytes,
  }) {
    if (totalBytes <= 0) return false; // unknown → allow, never block blind
    if (freeBytes < criticalFreeBytes) return true;
    final used = (totalBytes - freeBytes) / totalBytes;
    return used > criticalUsedFraction;
  }

  /// Probes disk + purges stale temp files. Never throws.
  static Future<void> refresh(String directoryPath) async {
    final now = DateTime.now();
    if (now.difference(_lastRefresh) < refreshInterval) return;
    _lastRefresh = now;
    try {
      final info = await StorageSpaceHelper.getAvailableSpace(directoryPath);
      if (info != null) {
        _critical = decideCritical(
          freeBytes: info.freeBytes,
          totalBytes: info.totalBytes,
        );
      }
      await purgeTempFiles(directoryPath);
    } catch (_) {
      // Unknown → allow. A failed probe must never block playback.
    }
  }

  /// Deletes stale temp/partial files. Returns deleted count. Never throws.
  static Future<int> purgeTempFiles(String directoryPath) async {
    var deleted = 0;
    try {
      final dir = Directory(directoryPath);
      if (!await dir.exists()) return 0;
      final cutoff = DateTime.now().subtract(tempMaxAge);
      await for (final e in dir.list()) {
        if (deleted >= 200) break;
        if (e is! File) continue;
        final p = e.path.toLowerCase();
        if (!(p.endsWith('.part') ||
            p.endsWith('.tmp') ||
            p.endsWith('.temp'))) {
          continue;
        }
        try {
          final stat = await e.stat();
          if (stat.modified.isBefore(cutoff)) {
            await e.delete();
            deleted++;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return deleted;
  }

  @visibleForTesting
  static void resetForTest() {
    _critical = false;
    _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
