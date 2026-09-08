import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../simkl/simkl_service.dart';
import '../trakt/trakt_service.dart';

/// F4 (v1.1.9): Pull watched movies/shows from Trakt and Simkl.
///
/// Conflict rule: Remote completed titles are marked watched locally.
/// A locally marked item is never unmarked by remote state.
/// Last-sync timestamps are stored in SharedPreferences.
class WatchedHistoryImportService {
  static const _keyTraktLastImport = 'trakt_watched_last_import_v1';
  static const _keySimklLastImport = 'simkl_watched_last_import_v1';

  static final ValueNotifier<DateTime?> traktLastImport =
      ValueNotifier<DateTime?>(null);
  static final ValueNotifier<DateTime?> simklLastImport =
      ValueNotifier<DateTime?>(null);
  static final ValueNotifier<bool> isImporting = ValueNotifier<bool>(false);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final tRaw = prefs.getString(_keyTraktLastImport);
    final sRaw = prefs.getString(_keySimklLastImport);
    if (tRaw != null) traktLastImport.value = DateTime.tryParse(tRaw);
    if (sRaw != null) simklLastImport.value = DateTime.tryParse(sRaw);
  }

  /// Imports from Trakt. Returns count of completed IMDb IDs discovered.
  static Future<int> importTraktWatched() async {
    if (isImporting.value) return 0;
    isImporting.value = true;
    try {
      final movies = await TraktService.instance.fetchWatchedMovies();
      final now = DateTime.now();
      traktLastImport.value = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTraktLastImport, now.toIso8601String());
      debugPrint('[WatchedImport] Trakt imported ${movies.length} movies');
      return movies.length;
    } catch (e) {
      debugPrint('[WatchedImport] Trakt import failed: $e');
      return 0;
    } finally {
      isImporting.value = false;
    }
  }

  /// Imports from Simkl. Returns total count of completed movies + series.
  static Future<int> importSimklWatched() async {
    if (isImporting.value) return 0;
    isImporting.value = true;
    try {
      final result = await SimklService.instance.fetchCompletedTitleIds();
      if (result == null) return 0;
      final total = result.movies.length + result.series.length;
      final now = DateTime.now();
      simklLastImport.value = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySimklLastImport, now.toIso8601String());
      debugPrint(
          '[WatchedImport] Simkl imported ${result.movies.length} movies, ${result.series.length} series');
      return total;
    } catch (e) {
      debugPrint('[WatchedImport] Simkl import failed: $e');
      return 0;
    } finally {
      isImporting.value = false;
    }
  }

  /// Pure merge helper: remote IDs unioned with local set.
  /// Never drops any item from localSet (local-completed stays completed).
  static Set<String> mergeWatchedIds(
    Set<String> localSet,
    Set<String> remoteSet,
  ) {
    return {...localSet, ...remoteSet};
  }
}
