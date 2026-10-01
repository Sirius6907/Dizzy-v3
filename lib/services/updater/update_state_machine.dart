import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase I3 — staged-update state machine.
///
/// idle → downloading → ready → installing → done, with `failed` reachable
/// from downloading/installing. Persisted so a process kill mid-download does
/// not leave the Hub row stuck on a state the app has forgotten about.
enum UpdateRunState { idle, downloading, ready, installing, done, failed }

/// Failure classes (plan: "report-error telemetry via report-error pipeline
/// (enum-only: DOWNLOAD_FAIL/CHECKSUM_FAIL/INSTALL_ABORT)").
enum UpdateFailReason {
  none,
  downloadFail,
  checksumFail,
  installAbort,
  wifiBlocked,
}

class UpdateStateMachine {
  UpdateStateMachine._();

  static const String kStateKey = 'update_run_state';
  static const String kMetaKey = 'update_run_meta';

  static final ValueNotifier<UpdateRunState> state =
      ValueNotifier<UpdateRunState>(UpdateRunState.idle);
  static final ValueNotifier<double> progress = ValueNotifier<double>(0);

  static String targetVersion = '';
  static UpdateFailReason reason = UpdateFailReason.none;

  /// Pure transition table — [canTransition] is what the tests pin.
  static bool canTransition(UpdateRunState from, UpdateRunState to) {
    if (from == to) return true;
    switch (from) {
      case UpdateRunState.idle:
        return to == UpdateRunState.downloading ||
            to == UpdateRunState.done; // already-installed no-op
      case UpdateRunState.downloading:
        return to == UpdateRunState.ready ||
            to == UpdateRunState.failed ||
            to == UpdateRunState.idle; // cancelled
      case UpdateRunState.ready:
        return to == UpdateRunState.installing ||
            to == UpdateRunState.idle; // discarded
      case UpdateRunState.installing:
        return to == UpdateRunState.done ||
            to == UpdateRunState.failed ||
            to == UpdateRunState.idle;
      case UpdateRunState.done:
        return to == UpdateRunState.idle;
      case UpdateRunState.failed:
        // A retry always starts a fresh download.
        return to == UpdateRunState.downloading || to == UpdateRunState.idle;
    }
  }

  static Future<void> set(
    UpdateRunState next, {
    double? progressValue,
    String? version,
    UpdateFailReason failReason = UpdateFailReason.none,
  }) async {
    if (!canTransition(state.value, next)) {
      debugPrint('[UpdateStateMachine] blocked ${state.value} → $next');
      return;
    }
    state.value = next;
    if (progressValue != null) progress.value = progressValue.clamp(0.0, 1.0);
    if (version != null) targetVersion = version;
    if (next != UpdateRunState.failed) reason = UpdateFailReason.none;
    if (next == UpdateRunState.failed) reason = failReason;
    if (next == UpdateRunState.idle) {
      progress.value = 0;
      targetVersion = '';
      reason = UpdateFailReason.none;
    }
    if (next == UpdateRunState.ready || next == UpdateRunState.done) {
      progress.value = 1;
    }
    await _persist();
  }

  /// Restores the last persisted run. A stale `downloading`/`installing` that
  /// the OS killed becomes `failed` — the file is gone and the UI must not
  /// lie about an in-flight download.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kStateKey);
      if (raw == null) return;
      final parsed = UpdateRunState.values.asNameMap()[raw];
      final metaRaw = prefs.getString(kMetaKey);
      final meta = metaRaw == null
          ? <String, dynamic>{}
          : jsonDecode(metaRaw) as Map<String, dynamic>;
      targetVersion = (meta['version'] as String?) ?? '';
      progress.value = ((meta['progress'] as num?) ?? 0).toDouble();
      reason =
          UpdateFailReason.values.asNameMap()[(meta['reason'] as String?) ??
              'none'] ??
          UpdateFailReason.none;

      // A `downloading` the OS killed leaves a partial file — real loss.
      // An `installing` means we already handed the APK to the system
      // installer, so treating it as failed would lie to the user about an
      // install that may well have succeeded.
      if (parsed == UpdateRunState.downloading) {
        // Direct write: restore is a recovery path, not a transition —
        // canTransition(idle → failed) is intentionally false for callers,
        // but a boot-time rollback must still land.
        state.value = UpdateRunState.failed;
        reason = UpdateFailReason.downloadFail;
        await _persist();
        return;
      }
      if (parsed == UpdateRunState.installing) {
        state.value = UpdateRunState.done;
        progress.value = 1;
        await _persist();
        return;
      }
      if (parsed != null) state.value = parsed;
    } catch (e) {
      debugPrint('[UpdateStateMachine] restore failed: $e');
      state.value = UpdateRunState.idle;
    }
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kStateKey, state.value.name);
      await prefs.setString(
        kMetaKey,
        jsonEncode({
          'version': targetVersion,
          'progress': progress.value,
          'reason': reason.name,
        }),
      );
    } catch (e) {
      debugPrint('[UpdateStateMachine] persist failed: $e');
    }
  }

  /// Test seam: wipes the in-memory value without touching prefs.
  @visibleForTesting
  static void resetForTest() {
    state.value = UpdateRunState.idle;
    progress.value = 0;
    targetVersion = '';
    reason = UpdateFailReason.none;
  }
}
