import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform/storage_space_helper.dart';

/// F3 (v1.1.9): Smart Downloads.
///
/// Features:
/// - Global toggle: Auto-download next episode
/// - Storage guard: Refuses to enqueue if free space < 1 GB
/// - Preferred quality pick: 720p (default), 1080p, 480p
class SmartDownloadService {
  static const _keyEnabled = 'smart_download_enabled_v1';
  static const _keyQuality = 'smart_download_quality_v1';
  static const int minFreeBytes = 1024 * 1024 * 1024; // 1 GB safety floor

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  static final ValueNotifier<String> preferredQuality =
      ValueNotifier<String>('720p');

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_keyEnabled) ?? false;
    preferredQuality.value = prefs.getString(_keyQuality) ?? '720p';
  }

  static Future<void> setEnabled(bool val) async {
    enabled.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, val);
  }

  static Future<void> setPreferredQuality(String quality) async {
    preferredQuality.value = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyQuality, quality);
  }

  /// Evaluates whether the next episode may be enqueued for [downloadDir].
  /// Returns a reason string if rejected, null if permitted.
  static Future<String?> canEnqueueNext(String downloadDir) async {
    if (!enabled.value) return 'Smart Downloads disabled';
    try {
      final space = await StorageSpaceHelper.getAvailableSpace(downloadDir);
      if (space != null && space.freeBytes < minFreeBytes) {
        return 'Low storage: less than 1 GB free space remaining';
      }
    } catch (_) {
      // Storage check failed soft; allow download rather than hard blocking.
    }
    return null;
  }

  /// Pure decision helper for unit testing.
  static bool hasSufficientStorage(int freeBytes) => freeBytes >= minFreeBytes;
}
