import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/my_list/my_list_item.dart';
import '../trakt/trakt_service.dart';
import '../simkl/simkl_service.dart';

abstract final class MyListService {
  static const _storageKey = 'my_list_v1';
  static const int maxItems = 500;

  static final ValueNotifier<List<MyListItem>> items =
      ValueNotifier<List<MyListItem>>([]);
  static final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  // Every persist runs through this chain: mutations and the parallel
  // Trakt/Simkl syncs all snapshot the list, and unsynchronized writes used to
  // overwrite each other (last write wins, progress lost).
  static Future<void> _writeChain = Future<void>.value();

  // Bumped by clearLocal(); an in-flight cloud sync that started before a
  // sign-out must not merge its snapshot back into the now-empty list.
  static int _generation = 0;

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored != null) {
      try {
        final decoded = jsonDecode(stored);
        final parsed = <MyListItem>[];
        if (decoded is List) {
          for (final entry in decoded) {
            // Skip only the bad row: one malformed entry must never wipe the
            // whole list (the next save would persist the empty result).
            try {
              if (entry is Map) {
                parsed.add(
                  MyListItem.fromJson(Map<String, dynamic>.from(entry)),
                );
              }
            } catch (e) {
              debugPrint('MyListService: skipping malformed entry: $e');
            }
          }
        }
        items.value = parsed;
      } catch (e) {
        // Unreadable blob: keep whatever is in memory rather than wiping it.
        debugPrint('MyListService: failed to decode stored list: $e');
      }
    }
    syncAll();
  }

  /// Serializes [action] after every previously queued write so a mutation's
  /// read-modify-write cannot interleave with another persist or sync merge.
  static Future<void> _enqueue(Future<void> Function() action) {
    final next = _writeChain.then((_) => action()).catchError((Object e) {
      debugPrint('MyListService: write error: $e');
    });
    _writeChain = next;
    return next;
  }

  /// Reads the in-memory list at execution time, then writes it.
  static Future<void> _writeNow() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = List<MyListItem>.from(items.value);
    await prefs.setString(
      _storageKey,
      jsonEncode(snapshot.map((e) => e.toJson()).toList()),
    );
  }

  /// Empties the local list and persists it (used by the sign-out flow).
  static Future<void> clearLocal() {
    _generation++;
    items.value = [];
    return _enqueue(_writeNow);
  }

  static Future<void> syncAll() async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    try {
      await Future.wait([syncWithTrakt(), syncWithSimkl()]);
    } finally {
      isSyncing.value = false;
    }
  }

  static Future<void> syncWithTrakt() async {
    try {
      final gen = _generation;
      if (!await TraktService.instance.isAuthenticated()) return;
      final movieItems = await TraktService.instance.fetchList(
        'watchlist',
        'movies',
      );
      final showItems = await TraktService.instance.fetchList(
        'watchlist',
        'shows',
      );

      final combined = [...movieItems, ...showItems];
      if (combined.isEmpty) return;

      await _enqueue(() async {
        if (gen != _generation) return;
        // Re-read inside the chain: add()/remove() may have landed meanwhile.
        final current = List<MyListItem>.from(items.value);
        for (final raw in combined) {
          if (raw is! Map<String, dynamic>) continue;
          final item = MyListItem.fromTraktJson(raw);
          final idx = current.indexWhere(
            (i) => i.uniqueKey == item.uniqueKey || i.matches(item),
          );
          if (idx == -1) {
            current.insert(0, item);
          } else {
            current[idx] = current[idx].mergeWith(item);
          }
        }
        current.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        items.value = current.take(maxItems).toList();
        await _writeNow();
      });
    } catch (e) {
      debugPrint('MyListService: Trakt sync error: $e');
    }
  }

  static Future<void> syncWithSimkl() async {
    try {
      final gen = _generation;
      if (!await SimklService.instance.isAuthenticated()) return;
      final lib = await SimklService.instance.fetchLibrarySnapshotOrNull();
      if (lib == null) return;

      await _enqueue(() async {
        if (gen != _generation) return;
        final current = List<MyListItem>.from(items.value);
        for (final bucket in ['movies', 'shows', 'anime']) {
          final list = lib[bucket];
          if (list is! List) continue;
          for (final raw in list) {
            if (raw is! Map<String, dynamic>) continue;
            final status = raw['status'];
            if (status == 'plantowatch' || status == 'watching') {
              final item = MyListItem.fromSimklJson(raw);
              final idx = current.indexWhere(
                (i) => i.uniqueKey == item.uniqueKey || i.matches(item),
              );
              if (idx == -1) {
                current.insert(0, item);
              } else {
                current[idx] = current[idx].mergeWith(item);
              }
            }
          }
        }
        current.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        items.value = current.take(maxItems).toList();
        await _writeNow();
      });
    } catch (e) {
      debugPrint('MyListService: Simkl sync error: $e');
    }
  }

  static bool isInList(MyListItem item) {
    return items.value.any(
      (i) => i.uniqueKey == item.uniqueKey || i.matches(item),
    );
  }

  static void add(MyListItem item) {
    // Mutate synchronously (UI + callers read items.value immediately); only
    // the persist is queued so concurrent saves cannot interleave.
    if (isInList(item)) return;

    final newList = <MyListItem>[...items.value, item];
    newList.sort((a, b) => b.addedAt.compareTo(a.addedAt));

    if (newList.length > maxItems) {
      newList.removeRange(maxItems, newList.length);
    }

    items.value = newList;
    unawaited(_enqueue(_writeNow));

    // Push to cloud services if logged in
    _syncCloudAdd(item);
  }

  static void _syncCloudAdd(MyListItem item) async {
    final imdb = item.imdbId;
    final tmdb = item.tmdbId;
    final trakt = item.traktId;
    final simkl = item.simklId;

    if (await TraktService.instance.isAuthenticated()) {
      TraktService.instance.addToWatchlist(
        imdb ?? '',
        item.type,
        tmdbId: tmdb,
        traktId: trakt,
      );
    }
    if (await SimklService.instance.isAuthenticated()) {
      SimklService.instance.addToList(
        imdb ?? '',
        item.type,
        'plantowatch',
        tmdbId: tmdb,
        simklId: simkl,
      );
    }
  }

  static void remove(MyListItem item) {
    final next = items.value
        .where((i) => i.uniqueKey != item.uniqueKey && !i.matches(item))
        .toList();
    final changed = next.length != items.value.length;
    if (!changed) return;

    items.value = next;
    unawaited(_enqueue(_writeNow));
    _syncCloudRemove(item);
  }

  static void _syncCloudRemove(MyListItem item) async {
    final imdb = item.imdbId;
    final tmdb = item.tmdbId;
    final trakt = item.traktId;
    final simkl = item.simklId;

    if (await TraktService.instance.isAuthenticated()) {
      TraktService.instance.removeFromWatchlist(
        imdb ?? '',
        item.type,
        tmdbId: tmdb,
        traktId: trakt,
      );
    }
    if (await SimklService.instance.isAuthenticated()) {
      SimklService.instance.addToList(
        imdb ?? '',
        item.type,
        'dropped',
        tmdbId: tmdb,
        simklId: simkl,
      );
    }
  }

  static void toggle(MyListItem item) {
    if (isInList(item)) {
      remove(item);
    } else {
      add(item);
    }
  }
}
