import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../notification/notification_prefs.dart';
import '../notification/notification_service.dart';
import 'update_state_machine.dart';

/// Minimal [Sink<Digest>] collector so we can read the final hash without
/// pulling in package:convert (crypto does not re-export AccumulatorSink).
class _DigestCollector implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Phase I2 — silent staged download.
///
/// Downloads the APK to app-private external storage with progress, verifies
/// the GitHub asset digest (sha256) BEFORE the file is ever offered to the
/// Android installer, then hands the path to a native `installApk` channel
/// that renders it through the same FileProvider the OTA plugin already
/// registers.
class UpdateStager {
  UpdateStager._();

  static const MethodChannel _installChannel = MethodChannel(
    'com.sirius6907.dizzyv3/install',
  );

  /// Static so the wire-up is unit-testable without a platform channel.
  static const String apkMime = 'application/vnd.android.package-archive';

  static Future<bool> isOnWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi);
    } catch (e) {
      debugPrint('[UpdateStager] connectivity probe failed: $e');
      // Unknown → allow; never block updates on a probe failure.
      return true;
    }
  }

  static Future<Directory> _stageDir() async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/staged_updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Path of an already-staged file for [version] (null until _stageDir ran
  /// in this process — the state machine is the source of truth for "ready").
  static Future<File> fileFor(String version) async {
    final dir = await _stageDir();
    return File('${dir.path}/Dizzy_$version.apk');
  }

  /// Downloads + verifies [url] into the stage dir.
  ///
  /// Returns the staged file path, or null — in which case
  /// [UpdateStateMachine.reason] explains why (download/checksum/wifi).
  static Future<String?> stage(
    String url,
    String version, {
    required String? expectedSha256,
    void Function(double progress)? onProgress,
    bool requireWifi = false,
  }) async {
    if (requireWifi && !await isOnWifi()) {
      await UpdateStateMachine.set(
        UpdateRunState.failed,
        version: version,
        failReason: UpdateFailReason.wifiBlocked,
      );
      return null;
    }

    await UpdateStateMachine.set(
      UpdateRunState.downloading,
      progressValue: 0,
      version: version,
    );

    try {
      final dir = await _stageDir();
      final out = File('${dir.path}/Dizzy_$version.apk');
      final partial = File('${out.path}.part');

      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(url));
        req.followRedirects = true;
        final resp = await req.close();
        if (resp.statusCode != 200) {
          throw HttpException('HTTP ${resp.statusCode}');
        }

        final total = resp.contentLength > 0 ? resp.contentLength : -1;
        var received = 0;
        final sink = partial.openWrite();
        final digestSink = _DigestCollector();
        final hasher = sha256.startChunkedConversion(digestSink);
        try {
          await for (final chunk in resp) {
            sink.add(chunk);
            hasher.add(chunk);
            received += chunk.length;
            if (total > 0) {
              final p = (received / total).clamp(0.0, 1.0);
              UpdateStateMachine.progress.value = p;
              onProgress?.call(p);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        hasher.close();
        final actual = digestSink.value?.toString() ?? '';

        // Checksum verify BEFORE the installer ever sees the file.
        if (expectedSha256 != null && expectedSha256.isNotEmpty) {
          if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
            try {
              if (await partial.exists()) await partial.delete();
            } catch (_) {}
            await UpdateStateMachine.set(
              UpdateRunState.failed,
              version: version,
              failReason: UpdateFailReason.checksumFail,
            );
            return null;
          }
        }

        if (await out.exists()) await out.delete();
        await partial.rename(out.path);

        await UpdateStateMachine.set(
          UpdateRunState.ready,
          progressValue: 1,
          version: version,
        );
        // Phase J2: heads-up that the update is waiting in the Hub.
        unawaited(
          NotificationService.push(
            NotificationKind.update,
            'Update ready to install',
            'Dizzy v$version is downloaded. Open Profile → Updates and tap Install.',
            id: 'update-ready-$version',
          ),
        );
        return out.path;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('[UpdateStager] stage failed: $e');
      await UpdateStateMachine.set(
        UpdateRunState.failed,
        version: version,
        failReason: UpdateFailReason.downloadFail,
      );
      return null;
    }
  }

  /// Hands the staged file to the system installer. The native side resolves
  /// it through the OTA FileProvider (already in the manifest) with a read
  /// grant, so no new permission is introduced.
  static Future<bool> installApk(String path) async {
    if (!File(path).existsSync()) {
      await UpdateStateMachine.set(
        UpdateRunState.failed,
        failReason: UpdateFailReason.installAbort,
      );
      return false;
    }
    try {
      await UpdateStateMachine.set(UpdateRunState.installing);
      final ok = await _installChannel.invokeMethod<bool>('installApk', {
        'path': path,
      });
      if (ok == true) {
        // Handed off — the system installer owns it from here. Recorded as
        // done so a process kill during install never becomes a fake error.
        await UpdateStateMachine.set(UpdateRunState.done);
      } else {
        await UpdateStateMachine.set(
          UpdateRunState.failed,
          failReason: UpdateFailReason.installAbort,
        );
      }
      return ok == true;
    } on PlatformException catch (e) {
      debugPrint('[UpdateStager] install failed: $e');
      await UpdateStateMachine.set(
        UpdateRunState.failed,
        failReason: UpdateFailReason.installAbort,
      );
      return false;
    }
  }

  /// Discards a staged file the user chose not to install.
  static Future<void> discard(String version) async {
    try {
      final f = await fileFor(version);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await UpdateStateMachine.set(UpdateRunState.idle);
  }
}
