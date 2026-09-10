import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/profiles/dizzy_profile.dart';
import '../cloud/cloud_client.dart';

/// S3B (v1.1.9) + v1.2.0-P1 (T1.4): local-first profiles. Cloud sync runs for
/// any signed-in session including anonymous (anonymous-first, OAuth removed).
/// PIN is SHA-256 hashed — raw PIN is never stored/synced.
class DizzyProfileService {
  static const _profilesKey = 'dizzy_profiles_v1';
  static const _activeKey = 'dizzy_active_profile_v1';

  static final ValueNotifier<List<DizzyProfile>> profiles =
      ValueNotifier<List<DizzyProfile>>([]);
  static final ValueNotifier<String?> activeProfileId = ValueNotifier<String?>(null);

  static DizzyProfile? get active {
    final id = activeProfileId.value;
    if (id == null) return null;
    for (final p in profiles.value) {
      if (p.id == id) return p;
    }
    return null;
  }

  static bool get isCloudUser {
    if (!CloudClient.isReady) return false;
    // v1.2.0-P1 (T1.4): anonymous-first — anonymous sessions sync too.
    // RLS (`auth.uid() = user_id`) already scopes anon rows per device.
    final user = CloudClient.db.auth.currentUser;
    return user != null;
  }

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_profilesKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as List;
        profiles.value = decoded
            .whereType<Map>()
            .map((e) => DizzyProfile.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    if (profiles.value.isEmpty) {
      final guest = DizzyProfile(
        id: const Uuid().v4(),
        name: 'Main Profile',
        avatar: '✨',
        isKids: false,
        createdAt: DateTime.now(),
      );
      profiles.value = [guest];
      await _persist();
    }
    activeProfileId.value = prefs.getString(_activeKey) ?? profiles.value.first.id;
    if (isCloudUser) syncFromCloud();
  }

  static Future<void> create({
    required String name,
    required String avatar,
    required bool isKids,
    String? pin,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty || profiles.value.length >= 5) return;
    final p = DizzyProfile(
      id: const Uuid().v4(),
      name: clean.substring(0, clean.length.clamp(0, 30)),
      avatar: avatar,
      isKids: isKids,
      pinHash: _hashPin(pin),
      createdAt: DateTime.now(),
    );
    profiles.value = [...profiles.value, p];
    await _persist();
    await _upsertCloud(p);
  }

  static Future<void> select(String id, {String? pin}) async {
    final p = profiles.value.where((e) => e.id == id).firstOrNull;
    if (p == null || (p.hasPin && _hashPin(pin) != p.pinHash)) return;
    activeProfileId.value = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
  }

  static Future<void> delete(String id) async {
    if (profiles.value.length <= 1) return;
    profiles.value = profiles.value.where((e) => e.id != id).toList();
    if (activeProfileId.value == id) {
      activeProfileId.value = profiles.value.first.id;
    }
    await _persist();
    if (isCloudUser) {
      try {
        await CloudClient.db.from('profiles').delete().match({
          'user_id': CloudClient.db.auth.currentUser!.id,
          'profile_id': id,
        });
      } catch (_) {}
    }
  }

  static String? _hashPin(String? pin) {
    final p = pin?.trim() ?? '';
    if (!RegExp(r'^\d{4,6}$').hasMatch(p)) return null;
    return sha256.convert(utf8.encode(p)).toString();
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _profilesKey, jsonEncode(profiles.value.map((e) => e.toJson()).toList()));
  }

  static Future<void> _upsertCloud(DizzyProfile p) async {
    if (!isCloudUser) return;
    try {
      await CloudClient.db.from('profiles').upsert({
        'user_id': CloudClient.db.auth.currentUser!.id,
        ...p.toCloudJson(),
      }, onConflict: 'user_id,profile_id');
    } catch (e) {
      debugPrint('[Profiles] cloud upsert failed (soft): $e');
    }
  }

  /// Merge remote profiles; local profile wins matching IDs, because it may
  /// have a newer local PIN selection. No profile is deleted by sync.
  static Future<void> syncFromCloud() async {
    if (!isCloudUser) return;
    try {
      final uid = CloudClient.db.auth.currentUser!.id;
      for (final p in profiles.value) {
        await _upsertCloud(p);
      }
      final rows = await CloudClient.db
          .from('profiles')
          .select()
          .eq('user_id', uid);
      final byId = {for (final p in profiles.value) p.id: p};
      for (final row in rows as List) {
        final remote = DizzyProfile.fromJson(Map<String, dynamic>.from(row));
        byId.putIfAbsent(remote.id, () => remote);
      }
      profiles.value = byId.values.toList();
      await _persist();
    } catch (e) {
      debugPrint('[Profiles] cloud sync failed (soft): $e');
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}