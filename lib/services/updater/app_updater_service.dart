import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud/remote_config_service.dart';
import '../device/device_identity_v2.dart';
import 'update_policy.dart';

class AppUpdaterService {
  static const String githubRepo = 'Sirius6907/Dizzy-v3';
  static const String githubApiUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';
  static const String _keyDismissedVersion = 'dismissed_update_version';

  /// Channel to read THIS install's own signing-cert fingerprint (MainActivity).
  static const MethodChannel _signingChannel = MethodChannel(
    'com.sirius6907.dizzyv3/signing',
  );

  /// Release-key fingerprint (CN=Sirius) — every release since v1.1.7.
  static const String releaseCertSha256 =
      'c513faef1906c5d67f01f7ff27946d52fe727773e72324e294c58de5711a1974';

  /// Debug-key fingerprint of the machine that built v1.1.3/v1.1.4.
  /// Installs from those releases must fetch legacy-signed assets to stay
  /// updatable IN PLACE (Android rejects updates signed with another key).
  static const String legacyCertSha256 =
      '5e70235900d8a44c350bae08d8949e6491f3724e572d3c9b021a85376ccf1548';

  /// SHA-256 of this install's signing cert, or null when unavailable
  /// (non-Android platforms, channel errors).
  static Future<String?> installedCertSha256() async {
    try {
      return await _signingChannel.invokeMethod<String>('getCertSha256');
    } catch (e) {
      debugPrint('[AppUpdaterService] cert lookup failed: $e');
      return null;
    }
  }

  static Future<void> dismissVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDismissedVersion, version);
      debugPrint('[AppUpdaterService] Dismissed update version: $version');
    } catch (e) {
      debugPrint('[AppUpdaterService] Error dismissing update version: $e');
    }
  }

  static Future<bool> isVersionDismissed(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getString(_keyDismissedVersion);
      return dismissed == version;
    } catch (e) {
      return false;
    }
  }

  static Future<void> clearDismissedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDismissedVersion);
    } catch (_) {}
  }

  Future<UpdateInfo?> checkForUpdates({bool ignoreDismissed = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Phase I1: beta opt-in reads the releases list (prereleases included);
      // stable keeps the classic /releases/latest endpoint (prereleases are
      // excluded by GitHub itself there).
      final channel = RemoteConfigService.updateChannel;
      final endpoint = channel == UpdatePolicy.betaChannel
          ? 'https://api.github.com/repos/$githubRepo/releases?per_page=5'
          : githubApiUrl;

      // v1.1.9 (Task 17): 8s cap — no update-check hang on dead networks.
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        // /releases/latest → object; /releases → array (first is newest).
        final Map<String, dynamic> data = decoded is List
            ? (decoded.isNotEmpty
                  ? Map<String, dynamic>.from(decoded.first as Map)
                  : <String, dynamic>{})
            : Map<String, dynamic>.from(decoded as Map);
        if (data.isEmpty || data['tag_name'] == null) return null;

        final latestVersion = (data['tag_name'] as String).replaceFirst(
          'v',
          '',
        );
        final releaseNotes =
            data['body'] as String? ?? 'No release notes available';
        final publishedAt = DateTime.parse(data['published_at']);

        if (_isNewerVersion(currentVersion, latestVersion)) {
          if (!ignoreDismissed && await isVersionDismissed(latestVersion)) {
            debugPrint(
              '[AppUpdaterService] Update $latestVersion is newer but was dismissed by user.',
            );
            return null;
          }

          // Phase I1 — server rollout + channel gate (soft offer only; the
          // min_app_version force path in UpdateGate is never gated by these).
          // Bucket uses the STABLE hwid so reinstalls keep their bucket.
          final ident = await DeviceIdentityV2.stableHwid();
          final isPrerelease = data['prerelease'] == true;
          final offered = UpdatePolicy.shouldOffer(
            stableHwid: ident.hash,
            rolloutPercent: RemoteConfigService.rolloutPercent,
            channel: RemoteConfigService.updateChannel,
            isPrerelease: isPrerelease,
          );
          if (!offered) {
            debugPrint(
              '[AppUpdaterService] $latestVersion held back by rollout/channel gate '
              '(bucket=${UpdatePolicy.hashBucket(ident.hash)}, '
              'rollout=${RemoteConfigService.rolloutPercent}%, '
              'channel=${RemoteConfigService.updateChannel}, prerelease=$isPrerelease).',
            );
            return null;
          }

          final assets = data['assets'] as List;

          // In-place update channel: read this install's own signing cert so
          // debug-key installs (v1.1.3/v1.1.4) fetch legacy-signed assets —
          // Android only accepts updates signed with the SAME key, so serving
          // the matching variant is what lets every old install keep updating.
          String? cert;
          if (!kIsWeb && Platform.isAndroid) {
            cert = await installedCertSha256();
          }
          final legacyChannel = cert == legacyCertSha256;
          if (legacyChannel) {
            debugPrint(
              '[AppUpdaterService] Legacy-signed install ($cert) — using legacy asset channel.',
            );
          }

          final downloadUrl = _findAssetForPlatform(
            assets,
            legacyChannel: legacyChannel,
          );

          // sha256 of the chosen asset (GitHub asset "digest") — handed to
          // OtaUpdate so a truncated/corrupt download is caught BEFORE the
          // Android installer ever sees the file.
          String? sha256;
          if (downloadUrl != null) {
            for (final a in assets) {
              if (a['browser_download_url'] == downloadUrl) {
                final digest = a['digest'];
                if (digest is String && digest.startsWith('sha256:')) {
                  sha256 = digest.substring('sha256:'.length);
                }
                break;
              }
            }
          }

          return UpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            downloadUrl: downloadUrl ?? data['html_url'],
            sha256: sha256,
            releaseNotes: releaseNotes,
            publishedAt: publishedAt,
            isMacOS: kIsWeb ? false : Platform.isMacOS,
            isIOS: kIsWeb ? false : Platform.isIOS,
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return null;
    }
  }

  /// Detects the current CPU architecture and finds the matching release asset.
  String? _findAssetForPlatform(List assets, {bool legacyChannel = false}) {
    if (kIsWeb) return null;

    Abi? abi;
    try {
      abi = Abi.current();
      debugPrint('Detected system ABI: $abi');
    } catch (e) {
      debugPrint('Error detecting ABI: $e');
    }

    if (Platform.isAndroid) {
      return _findAndroidAsset(assets, abi, legacyChannel: legacyChannel);
    } else if (Platform.isWindows) {
      return _findWindowsAsset(assets, abi);
    } else if (Platform.isLinux) {
      return _findLinuxAsset(assets, abi);
    } else if (Platform.isMacOS) {
      return _findMacOSAsset(assets, abi);
    }
    return null;
  }

  /// Picks the Android release asset matching [archKeywords].
  ///
  /// Fallback order is deliberate: exact arch match first, then the standard
  /// `release` build, and the fat Universal APK LAST. The Universal is a
  /// by-design base-versionCode build (no abiCode*1000 override), so serving
  /// it ahead of split builds would hand version-downgraded APKs to old
  /// installs (INSTALL_FAILED_VERSION_DOWNGRADE, "package not valid").
  ///
  /// [legacyChannel]=true keeps ONLY `legacy`-named assets (installs whose own
  /// cert is the pre-v1.1.7 debug key), falling back to normal assets while a
  /// release has no legacy variant yet. The normal channel EXCLUDES legacy
  /// assets so release-key installs never fetch them. Static for testability.
  static Map<dynamic, dynamic>? pickAndroidAsset(
    List<dynamic> assets, {
    required List<String> archKeywords,
    required bool legacyChannel,
  }) {
    var apks = assets
        .where(
          (a) => ((a['name'] as String?) ?? '').toLowerCase().endsWith('.apk'),
        )
        .toList();

    if (legacyChannel) {
      final legacy = apks
          .where((a) => (a['name'] as String).toLowerCase().contains('legacy'))
          .toList();
      if (legacy.isNotEmpty) {
        apks = legacy;
      } else {
        debugPrint(
          '[AppUpdaterService] No legacy assets in this release yet — falling back to normal channel.',
        );
      }
    } else {
      apks = apks
          .where((a) => !(a['name'] as String).toLowerCase().contains('legacy'))
          .toList();
    }

    if (apks.isEmpty) return null;

    // 1. Try exact architecture match
    for (final keyword in archKeywords) {
      final match = apks
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) {
        debugPrint('Matched APK ($keyword): ${match['name']}');
        return match;
      }
    }

    // 2. Prefer the standard release APK over the fat Universal: the
    // Universal carries the base versionCode (no abiCode*1000 override)
    // while per-ABI/split builds carry the high code old installs need.
    final standardRelease = apks
        .where((a) => (a['name'] as String).toLowerCase().contains('release'))
        .firstOrNull;
    if (standardRelease != null) {
      debugPrint('Using standard release APK: ${standardRelease['name']}');
      return standardRelease;
    }

    // 3. Last resort before first-available: the fat Universal APK.
    // Kept here (not earlier) because its base versionCode lags the
    // split builds — serving it first would downgrade-block old installs.
    final universal = apks
        .where((a) => (a['name'] as String).toLowerCase().contains('universal'))
        .firstOrNull;
    if (universal != null) {
      debugPrint('Falling back to universal APK: ${universal['name']}');
      return universal;
    }

    // 4. Last resort: first available APK
    debugPrint('Using first available APK: ${apks.first['name']}');
    return apks.first;
  }

  /// Android: match arm64-v8a, armeabi-v7a, x86_64, or fall back to universal
  String? _findAndroidAsset(
    List assets,
    Abi? abi, {
    bool legacyChannel = false,
  }) {
    // Determine architecture keywords to search for
    List<String> archKeywords = [];
    if (abi == Abi.androidArm64) {
      archKeywords = ['arm64-v8a', 'arm64_v8a', 'arm64', 'v8a', 'aarch64'];
    } else if (abi == Abi.androidArm) {
      archKeywords = [
        'armeabi-v7a',
        'armeabi_v7a',
        'armeabi',
        'v7a',
        'armv7',
        'arm-v7a',
      ];
    } else if (abi == Abi.androidX64) {
      archKeywords = ['x86_64', 'x86-64', 'x64'];
    } else if (abi == Abi.androidIA32) {
      archKeywords = ['x86', 'x86_32', 'ia32'];
    } else {
      // Default to arm64-v8a on modern Android if ABI couldn't be determined
      archKeywords = ['arm64-v8a', 'arm64', 'v8a'];
    }

    final match = pickAndroidAsset(
      assets,
      archKeywords: archKeywords,
      legacyChannel: legacyChannel,
    );
    return match?['browser_download_url'];
  }

  /// Windows: match x64 or arm64 installer (.exe prioritized over .zip)
  String? _findWindowsAsset(List assets, Abi? abi) {
    final windowsAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return (name.contains('windows') ||
              name.contains('win') ||
              name.contains('setup') ||
              name.endsWith('.exe')) &&
          (name.endsWith('.exe') ||
              name.endsWith('.msix') ||
              name.endsWith('.zip'));
    }).toList();

    if (windowsAssets.isEmpty) return null;

    // 1. Look for installer .exe matching setup/installer
    final setupExe = windowsAssets
        .where(
          (a) =>
              (a['name'] as String).toLowerCase().endsWith('.exe') &&
              ((a['name'] as String).toLowerCase().contains('setup') ||
                  (a['name'] as String).toLowerCase().contains('install')),
        )
        .firstOrNull;
    if (setupExe != null) {
      debugPrint('Selected Windows Setup installer: ${setupExe['name']}');
      return setupExe['browser_download_url'];
    }

    // 2. Look for any .exe
    final anyExe = windowsAssets
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.exe'))
        .firstOrNull;
    if (anyExe != null) {
      debugPrint('Selected Windows exe: ${anyExe['name']}');
      return anyExe['browser_download_url'];
    }

    // 3. Match architecture in remaining assets (.zip/.msix)
    List<String> archKeywords;
    if (abi == Abi.windowsArm64) {
      archKeywords = ['arm64', 'aarch64'];
    } else {
      archKeywords = ['x64', 'x86_64', 'amd64', 'win64'];
    }

    for (final keyword in archKeywords) {
      final match = windowsAssets
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) return match['browser_download_url'];
    }

    return windowsAssets.first['browser_download_url'];
  }

  /// Linux: match arm64 or x64 AppImage/deb
  String? _findLinuxAsset(List assets, Abi? abi) {
    final linuxAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return name.contains('linux') ||
          name.endsWith('.appimage') ||
          name.endsWith('.deb') ||
          name.endsWith('.tar.gz');
    }).toList();

    if (linuxAssets.isEmpty) return null;

    if (linuxAssets.length == 1) {
      return linuxAssets.first['browser_download_url'];
    }

    List<String> archKeywords;
    if (abi == Abi.linuxArm64) {
      archKeywords = ['arm64', 'aarch64'];
    } else {
      archKeywords = ['x64', 'x86_64', 'amd64'];
    }
    for (final keyword in archKeywords) {
      final match = linuxAssets
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) return match['browser_download_url'];
    }

    return linuxAssets.first['browser_download_url'];
  }

  /// macOS: match dmg or zip
  String? _findMacOSAsset(List assets, Abi? abi) {
    final macAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return name.contains('mac') ||
          name.contains('darwin') ||
          name.endsWith('.dmg') ||
          name.endsWith('.pkg');
    }).toList();

    if (macAssets.isNotEmpty) {
      return macAssets.first['browser_download_url'];
    }
    return null;
  }

  bool _isNewerVersion(String current, String latest) {
    // Strip any suffix like "-test" or "-beta" for comparison
    final currentClean = current.split('-').first;
    final latestClean = latest.split('-').first;
    final currentParts = currentClean
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final latestParts = latestClean
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();

    for (int i = 0; i < 3; i++) {
      final currentPart = i < currentParts.length ? currentParts[i] : 0;
      final latestPart = i < latestParts.length ? latestParts[i] : 0;

      if (latestPart > currentPart) return true;
      if (latestPart < currentPart) return false;
    }
    return false;
  }

  Future<void> openDownloadPage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;

  /// sha256 of the chosen asset (GitHub asset digest), verified by the OTA
  /// plugin before install. Null when the release provides no digest.
  final String? sha256;
  final String releaseNotes;
  final DateTime publishedAt;
  final bool isMacOS;
  final bool isIOS;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.sha256,
    required this.releaseNotes,
    required this.publishedAt,
    required this.isMacOS,
    this.isIOS = false,
  });
}
