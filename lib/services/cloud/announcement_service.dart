import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_client.dart';

/// v1.2.0-ADMIN: in-app announcements from Supabase `announcements` table.
///
/// Dashboard creates {title, body, url, min/max_version, active}.
/// App shows matching ones as dismissible banners. Version-gated client-side.
/// Fails soft — offline means no banners, never an error.
class AnnouncementService {
  static const _dismissKey = 'announcements_dismissed_v1';

  static final ValueNotifier<List<AppAnnouncement>> active =
      ValueNotifier<List<AppAnnouncement>>(<AppAnnouncement>[]);

  static String _appVersion = '';
  static bool _loaded = false;

  static Future<void> initialize({required String appVersion}) async {
    if (_loaded) return;
    _loaded = true;
    _appVersion = appVersion;
    await refresh();
  }

  static Future<void> refresh() async {
    try {
      if (!CloudClient.isReady) return;
      final rows = await CloudClient.db
          .from('announcements')
          .select()
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(10);
      final dismissed = await _dismissed();
      final list = <AppAnnouncement>[];
      for (final r in (rows as List)) {
        final a = AppAnnouncement.fromJson(Map<String, dynamic>.from(r as Map));
        if (dismissed.contains(a.id)) continue;
        if (!versionOk(a.minVersion, a.maxVersion, _appVersion)) continue;
        list.add(a);
      }
      active.value = list;
    } catch (e) {
      debugPrint('[Announcements] refresh failed (soft): $e');
    }
  }

  static Future<void> dismiss(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set = await _dismissed();
      set.add(id);
      await prefs.setStringList(_dismissKey, set.toList());
      active.value = active.value.where((a) => a.id != id).toList();
    } catch (_) {}
  }

  static Future<Set<String>> _dismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_dismissKey) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Pure: blank bound = unbounded. Compares dot-separated versions.
  static bool versionOk(String min, String max, String appVersion) {
    if (min.trim().isNotEmpty &&
        _cmp(appVersion, min.trim()) < 0) {
      return false;
    }
    if (max.trim().isNotEmpty && _cmp(appVersion, max.trim()) > 0) {
      return false;
    }
    return true;
  }

  /// Pure: -1 / 0 / +1 comparing "1.2.0" style versions.
  static int compareVersions(String a, String b) => _cmp(a, b);

  static int _cmp(String a, String b) {
    final pa = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final pb = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }
}

class AppAnnouncement {
  final String id;
  final String title;
  final String body;
  final String? url;
  final String minVersion;
  final String maxVersion;

  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    this.url,
    this.minVersion = '',
    this.maxVersion = '',
  });

  factory AppAnnouncement.fromJson(Map<String, dynamic> json) =>
      AppAnnouncement(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        url: (json['url'] as String?)?.isNotEmpty == true
            ? json['url'] as String
            : null,
        minVersion: (json['min_version'] ?? '').toString(),
        maxVersion: (json['max_version'] ?? '').toString(),
      );
}
