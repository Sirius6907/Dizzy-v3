import 'dart:async';

import 'app_updater_service.dart';
import 'update_prefs.dart';
import 'update_stager.dart';
import 'update_state_machine.dart';

/// Phase I2/I3 — one entry point that owns "check → remember notes → maybe
/// silently stage".
///
/// Plan §2d: Wi-Fi + auto-download ON → silent staged download in background;
/// otherwise the existing UpdateDialog (manual path) stays the flow.
class UpdateOrchestrator {
  UpdateOrchestrator._();

  /// Boot hook: rehydrate the persisted state machine so a process killed
  /// mid-download never leaves the Hub row lying about in-flight work.
  static Future<void> restore() => UpdateStateMachine.restore();

  /// Checks for an update. When an update is offered its release notes are
  /// cached (Hub "What's new") and — if the user opted in — the APK is staged
  /// in the background.
  ///
  /// Returns the offered [UpdateInfo] (so the caller may show the manual
  /// dialog), or null when nothing was offered (up to date / dismissed /
  /// rollout-held-back).
  static Future<UpdateInfo?> autoStageIfDue({
    bool ignoreDismissed = false,
  }) async {
    final info = await AppUpdaterService().checkForUpdates(
      ignoreDismissed: ignoreDismissed,
    );
    if (info == null) return null;

    // I3: cache notes for the Hub changelog view.
    try {
      await UpdatePrefs.rememberRelease(
        version: info.latestVersion,
        notes: info.releaseNotes,
        publishedAt: info.publishedAt.toIso8601String(),
      );
    } catch (_) {}

    final auto = await UpdatePrefs.autoDownload;
    if (!auto) return info;
    if (UpdateStateMachine.state.value == UpdateRunState.downloading ||
        UpdateStateMachine.state.value == UpdateRunState.ready) {
      return info; // already staged / staging
    }

    final wifiOnly = await UpdatePrefs.wifiOnly;
    unawaited(
      UpdateStager.stage(
        info.downloadUrl,
        info.latestVersion,
        expectedSha256: info.sha256,
        requireWifi: wifiOnly,
      ).catchError((_) => null),
    );
    return info;
  }
}
