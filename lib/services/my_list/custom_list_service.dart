import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'custom_list_policy.dart';
import 'pin_lock_policy.dart';

/// F3 — hand-made lists that belong to a person, not a phone.
///
/// Storage is `custom_lists_v1::<profileId>`: one bucket per profile, so
/// switching profiles can never show another person's lists. The rules
/// (naming, caps, dedupe) live in [CustomListPolicy]; this file stores and
/// emits.
class CustomListService {
  static const _prefix = 'custom_lists_v1::';
  static const _lockPrefix = 'custom_list_pin_v1::';
  static const _missPrefix = 'custom_list_miss_v1::';

  /// Lists of the profile currently in use.
  static final ValueNotifier<List<CustomList>> lists =
      ValueNotifier<List<CustomList>>([]);

  /// The signed-in profile the notifier is currently showing.
  static String? _activeProfileId;

  static int _misses = 0;
  static DateTime? _firstMissAt;

  static String _key(String profileId) => '$_prefix$profileId';

  static String _lockKey(String profileId) => '$_lockPrefix$profileId';

  static String _missKey(String profileId) => '$_missPrefix$profileId';

  /// Load one profile's lists into [lists]. Call on profile switch.
  static Future<void> load(String profileId) async {
    if (profileId.isEmpty) {
      _activeProfileId = null;
      lists.value = [];
      return;
    }
    _activeProfileId = profileId;
    final prefs = await SharedPreferences.getInstance();
    lists.value = _read(prefs.getString(_key(profileId)));
    _misses = prefs.getInt(_missKey(profileId)) ?? 0;
    final first = prefs.getInt('${_missKey(profileId)}_at');
    _firstMissAt = first == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(first);
  }

  static List<CustomList> _read(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      final out = <CustomList>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        // A corrupt row is dropped; the rest of the lists still show.
        final l = CustomList.fromJson(Map<String, dynamic>.from(e));
        if (l != null) out.add(l);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<CustomList> next) async {
    lists.value = next;
    final id = _activeProfileId;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(id),
      jsonEncode(next.map((l) => l.toJson()).toList()),
    );
  }

  /// Create a list. Returns `true` when it was made, `false` when the name
  /// was unusable or the person is at the cap.
  static Future<bool> create(String name) async {
    final next = CustomListPolicy.create(
      lists.value,
      id: const Uuid().v4(),
      name: name,
    );
    if (next == null) return false;
    await _write(next);
    return true;
  }

  static Future<bool> rename(String listId, String name) async {
    final next = CustomListPolicy.rename(
      lists.value,
      id: listId,
      name: name,
    );
    if (next == null) return false;
    await _write(next);
    return true;
  }

  static Future<void> delete(String listId) async {
    await _write(CustomListPolicy.delete(lists.value, listId));
  }

  static Future<bool> addItem(String listId, String itemKey) async {
    final next = CustomListPolicy.addItem(
      lists.value,
      listId: listId,
      itemKey: itemKey,
    );
    if (next == null) return false;
    await _write(next);
    return true;
  }

  static Future<void> removeItem(String listId, String itemKey) async {
    await _write(
      CustomListPolicy.removeItem(
        lists.value,
        listId: listId,
        itemKey: itemKey,
      ),
    );
  }

  /// Every list of every profile, for the device merge. Never overwrites
  /// anything: keys are `profileId::listId` so two devices can hold two
  /// lists with the same name without fighting.
  static Future<Map<String, dynamic>> exportAll() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final profileId = key.substring(_prefix.length);
      final rows = _read(prefs.getString(key));
      out[profileId] = rows.map((l) => l.toJson()).toList();
    }
    return out;
  }

  /// Fold a merged copy back in, list by list, never dropping a local one.
  static Future<int> importAll(Map<String, dynamic> remote) async {
    var gained = 0;
    for (final entry in remote.entries) {
      final profileId = entry.key;
      final raw = entry.value;
      if (profileId.isEmpty || raw is! List) continue;
      final prefs = await SharedPreferences.getInstance();
      final local = _read(prefs.getString(_key(profileId)));
      final byId = {for (final l in local) l.id: l};
      for (final e in raw) {
        if (e is! Map) continue;
        final r = CustomList.fromJson(Map<String, dynamic>.from(e));
        if (r == null) continue;
        final mine = byId[r.id];
        if (mine == null) {
          byId[r.id] = r;
          gained++;
        } else {
          // Union of item keys — a title removed on one phone can still
          // come back from the other, but nothing is overwritten.
          final keys = <String>{...mine.itemKeys, ...r.itemKeys}.toList();
          final newer = r.updatedAt.isAfter(mine.updatedAt) ? r : mine;
          byId[r.id] = newer.copyWith(
            itemKeys: keys.length > CustomListPolicy.maxItemsPerList
                ? keys.take(CustomListPolicy.maxItemsPerList).toList()
                : keys,
            updatedAt:
                r.updatedAt.isAfter(mine.updatedAt) ? r.updatedAt : mine.updatedAt,
          );
        }
      }
      final merged = byId.values.take(CustomListPolicy.maxLists).toList();
      await prefs.setString(
        _key(profileId),
        jsonEncode(merged.map((l) => l.toJson()).toList()),
      );
      if (profileId == _activeProfileId) lists.value = merged;
    }
    return gained;
  }

  // ── PIN lock ────────────────────────────────────────────────────────────

  /// Set (or clear, with `pin: null`) the lock for one profile.
  static Future<void> setPin(String profileId, String? pin) async {
    if (profileId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final h = pin == null ? null : PinLockPolicy.hash(pin);
    if (h == null) {
      await prefs.remove(_lockKey(profileId));
    } else {
      await prefs.setString(_lockKey(profileId), h);
    }
    if (profileId == _activeProfileId) _misses = 0;
  }

  static Future<String?> storedPinHash(String profileId) async {
    if (profileId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lockKey(profileId));
  }

  /// Try to open the lists of one profile.
  ///
  /// A correct code clears the miss counter, so a lockout never sticks to
  /// someone who gets it right afterwards. A wrong one starts (or extends)
  /// the wait.
  static Future<PinCheck> unlock(String profileId, String candidate) async {
    final hashValue = await storedPinHash(profileId);
    final check = PinLockPolicy.unlock(
      candidate: candidate,
      storedHash: hashValue,
      misses: _misses,
      firstMissAt: _firstMissAt,
    );
    if (check.ok) {
      final (misses, first) = PinLockPolicy.afterHit();
      _misses = misses;
      _firstMissAt = first;
      await _saveMisses(profileId);
      return check;
    }
    if (check.isLockedOut) return check;
    final (misses, first) = PinLockPolicy.afterMiss(
      misses: _misses,
      firstMissAt: _firstMissAt,
    );
    _misses = misses;
    _firstMissAt = first;
    await _saveMisses(profileId);
    return check;
  }

  static Future<void> _saveMisses(String profileId) async {
    if (profileId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_missKey(profileId), _misses);
    if (_firstMissAt == null) {
      await prefs.remove('${_missKey(profileId)}_at');
    } else {
      await prefs.setInt(
        '${_missKey(profileId)}_at',
        _firstMissAt!.millisecondsSinceEpoch,
      );
    }
  }

  /// Test hook — clear in-memory state between cases.
  @visibleForTesting
  static void debugReset() {
    lists.value = [];
    _activeProfileId = null;
    _misses = 0;
    _firstMissAt = null;
  }
}
