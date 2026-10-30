import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../addon/addon_manager.dart';
import '../theme/app_theme_service.dart';
import '../home/home_page_settings.dart';
import '../theme/custom_background_service.dart';

/// Thrown when a backup was written by a schema version we do not understand,
/// so the payload is never applied blindly.
class BackupVersionException implements Exception {
  const BackupVersionException(this.found, this.supported);

  final Object? found;
  final String supported;

  @override
  String toString() =>
      'Unsupported backup version "$found" (this app supports "$supported").';
}

class BackupRestoreService {
  /// Backup schema version. Written into every export and checked on import;
  /// bump only when the exported shape changes.
  static const String appVersion = '1.1.3';

  /// Preference keys that hold user data and are therefore exportable.
  /// Credentials (tokens, api keys, sessions) never leave the device.
  static const Set<String> _allowedExactKeys = {
    'my_list_v1',
    'continue_watching_sessions_v1',
    'continue_reading_sessions_v1',
    'dizzy_profiles_v1',
    'dizzy_active_profile_v1',
    'dizzy_anime_watchlist_v1',
    'dizzy_anime_history_v1',
    'profile_progress_v1',
  };

  static const List<String> _allowedKeyPrefixes = [
    'my_list',
    'continue_watching',
    'download_',
    'smart_download_',
    'offline_hub_',
    'dizzy_download_',
    'dizzy_watched_episodes',
    'dizzy_profiles',
    'dizzy_active_profile',
    'dizzy_reader_',
    'dizzy_quality_choice',
    'dizzy_anime_',
    'home_',
    'app_',
    'iptv_',
    'pt_iptv_',
    'player_',
    'audiobook_',
    'ux6_',
    'glass_',
    'custom_bg_',
    'genre_preference_scores',
    'profile_progress',
  ];

  /// Redaction deny-list. A future key that matches an allow-listed prefix but
  /// smells like a credential is still dropped (case-insensitive).
  static const List<String> _redactedKeyFragments = [
    'token',
    'secret',
    'password',
    'api_key',
    'auth',
    'cookie',
    'session',
    'debrid',
    'qobuz',
    'restore',
  ];

  static bool _isExportableKey(String key) {
    final k = key.toLowerCase();
    // Exact user-data keys win: continue-watching is allow-listed on purpose
    // even though its name contains "session".
    if (_allowedExactKeys.contains(k)) return true;
    if (_redactedKeyFragments.any(k.contains)) return false;
    return _allowedKeyPrefixes.any(k.startsWith);
  }

  /// Exports user data, installed addons, IPTV portals/playlists and theme
  /// preferences into a formatted JSON string. Secrets are never included.
  static Future<String> exportSettingsJson() async {
    final prefs = await SharedPreferences.getInstance();

    final exportData = <String, dynamic>{
      'version': appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'platform': defaultTargetPlatform.name,
      'settings': {},
      'theme': {},
      'iptv': {},
      'addons': {},
    };

    // 1. Explicit allow-list instead of a blanket prefs dump.
    final settingsMap = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (!_isExportableKey(key)) continue;
      final val = prefs.get(key);
      if (val is String ||
          val is int ||
          val is double ||
          val is bool ||
          val is List<String>) {
        settingsMap[key] = val;
      }
    }
    exportData['settings'] = settingsMap;

    // 2. Current Theme & Background
    final currentBg = CustomBackgroundService.current;
    exportData['theme'] = {
      'paletteId': AppThemeService.currentPalette.value.id,
      'customBg': {
        'imagePath': currentBg.imagePath,
        'imageUrl': currentBg.imageUrl,
        'opacity': currentBg.opacity,
        'blur': currentBg.blur,
        'blendThemeLights': currentBg.blendThemeLights,
        'themeTintOpacity': currentBg.themeTintOpacity,
      },
      'ambientLightsEnabled': HomePageSettings.enableAmbientLights.value,
      'ambientPattern': HomePageSettings.ambientLightPattern.value.name,
      'ambientIntensity': HomePageSettings.ambientLightIntensity.value,
      'ambientSpeed': HomePageSettings.ambientLightSpeed.value,
    };

    // 3. IPTV Custom Portals & Playlists
    try {
      final customPortals = prefs.getStringList('iptv_custom_portals') ?? [];
      final m3uPlaylists = prefs.getString('iptv_m3u_playlists') ?? '[]';
      final favPortals = prefs.getStringList('iptv_favorite_portals') ?? [];

      exportData['iptv'] = {
        'customPortals': customPortals,
        'm3uPlaylists': m3uPlaylists,
        'favoritePortals': favPortals,
      };
    } catch (_) {}

    // 4. Installed Addons
    try {
      final installedAddons = AddonManager.instance.addons
          .map(
            (a) => {
              'baseUrl': a.baseUrl,
              'enabled': a.enabled,
              'enableCatalogs': a.enableCatalogs,
              'enableSearch': a.enableSearch,
              'enableStreams': a.enableStreams,
              'enableSubtitles': a.enableSubtitles,
            },
          )
          .toList();

      exportData['addons'] = {'installed': installedAddons};
    } catch (_) {}

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Imports and applies settings from a JSON string.
  /// Returns a status message on success; throws on failure, including a
  /// [BackupVersionException] for an unsupported schema version.
  static Future<String> importSettingsJson(String jsonStr) async {
    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid backup format: root must be a JSON object.',
      );
    }

    // Refuse an unknown schema instead of importing it blindly.
    final version = decoded['version'];
    if (version is! String || version != appVersion) {
      throw BackupVersionException(version, appVersion);
    }

    final prefs = await SharedPreferences.getInstance();
    int restoredItems = 0;

    // 1. Restore SharedPreferences (allow-listed keys only).
    if (decoded.containsKey('settings') && decoded['settings'] is Map) {
      final settings = decoded['settings'] as Map;
      for (final entry in settings.entries) {
        final key = entry.key.toString();
        // Old or tampered payloads may carry anything: ignore the rest.
        if (!_isExportableKey(key)) continue;
        final dynamic val = entry.value;

        if (val is String) {
          await prefs.setString(key, val);
          restoredItems++;
        } else if (val is int) {
          await prefs.setInt(key, val);
          restoredItems++;
        } else if (val is double) {
          await prefs.setDouble(key, val);
          restoredItems++;
        } else if (val is bool) {
          await prefs.setBool(key, val);
          restoredItems++;
        } else if (val is List) {
          final strList = val.map((e) => e.toString()).toList();
          await prefs.setStringList(key, strList);
          restoredItems++;
        }
      }
    }

    // 2. Restore Theme
    if (decoded.containsKey('theme') && decoded['theme'] is Map) {
      final theme = decoded['theme'] as Map;
      final paletteId = theme['paletteId']?.toString();
      if (paletteId != null) {
        final found = AppThemeService.palettes.firstWhere(
          (p) => p.id == paletteId,
          orElse: () => AppThemeService.palettes.first,
        );
        await AppThemeService.setPalette(found);
      }

      if (theme['customBg'] is Map) {
        final bgMap = Map<String, dynamic>.from(theme['customBg'] as Map);
        if (bgMap['imageUrl'] != null &&
            bgMap['imageUrl'].toString().isNotEmpty) {
          await CustomBackgroundService.setImageUrl(
            bgMap['imageUrl'].toString(),
          );
        }
        if (bgMap['opacity'] is num) {
          await CustomBackgroundService.setOpacity(
            (bgMap['opacity'] as num).toDouble(),
          );
        }
        if (bgMap['blur'] is num) {
          await CustomBackgroundService.setBlur(
            (bgMap['blur'] as num).toDouble(),
          );
        }
      }
    }

    // 3. Restore Addons
    if (decoded.containsKey('addons') && decoded['addons'] is Map) {
      final addonsObj = decoded['addons'] as Map;
      if (addonsObj['installed'] is List) {
        final list = addonsObj['installed'] as List;
        for (final item in list) {
          if (item is Map && item['baseUrl'] != null) {
            final url = item['baseUrl'].toString();
            try {
              final added = await AddonManager.instance.addAddon(url);
              await AddonManager.instance.updateAddonFeature(
                addonId: added.manifest.id,
                enableCatalogs: item['enableCatalogs'] as bool?,
                enableSearch: item['enableSearch'] as bool?,
                enableStreams: item['enableStreams'] as bool?,
                enableSubtitles: item['enableSubtitles'] as bool?,
              );
            } catch (_) {}
          }
        }
      }
    }

    // 4. Restore IPTV
    if (decoded.containsKey('iptv') && decoded['iptv'] is Map) {
      final iptvObj = decoded['iptv'] as Map;
      if (iptvObj['customPortals'] is List) {
        final list = (iptvObj['customPortals'] as List)
            .map((e) => e.toString())
            .toList();
        await prefs.setStringList('iptv_custom_portals', list);
      }
      if (iptvObj['m3uPlaylists'] is String) {
        await prefs.setString(
          'iptv_m3u_playlists',
          iptvObj['m3uPlaylists'] as String,
        );
      }
      if (iptvObj['favoritePortals'] is List) {
        final list = (iptvObj['favoritePortals'] as List)
            .map((e) => e.toString())
            .toList();
        await prefs.setStringList('iptv_favorite_portals', list);
      }
    }

    return 'Successfully restored configuration ($restoredItems settings, addons & portals restored).';
  }
}
