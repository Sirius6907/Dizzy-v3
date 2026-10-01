import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/download/download_task_model.dart';
import '../cloud/announcement_service.dart';
import '../download/download_service.dart';
import 'notification_inbox.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';

/// Phase J2 — the event → notification wiring.
///
/// Two sources feed the Center today:
///  * downloads (terminal transitions off the shared tasks notifier);
///  * announcements (polled every [announcementPoll]; the first pass after
///    attach only seeds what the in-app banner already shows, so a user is
///    never told twice about the same notice).
///
/// Everything is fail-soft: a notifier throwing must not break the feature
/// that raised it.
class NotificationTriggers {
  NotificationTriggers._();

  static bool _attached = false;
  static bool _seededAnnouncements = false;
  static final Map<String, DownloadStatus> _lastStatus =
      <String, DownloadStatus>{};
  static final Set<String> _annSeen = <String>{};
  static Timer? _poll;

  static bool get attached => _attached;

  static Future<void> attach({
    Duration announcementPoll = const Duration(minutes: 5),
  }) async {
    if (_attached) return;
    _attached = true;
    await NotificationInbox.load();
    await NotificationService.initialize();

    DownloadService.instance.tasksNotifier.addListener(_onDownloads);
    AnnouncementService.active.addListener(_onAnnouncements);
    // Seed the baseline so pre-existing state never fires a notification.
    _onDownloads();
    _onAnnouncements();

    _poll?.cancel();
    _poll = Timer.periodic(announcementPoll, (_) {
      // Ignore errors: a poll failure means "no news", not a crash.
      unawaited(AnnouncementService.refresh().catchError((_) {}));
    });
  }

  static void detach() {
    _attached = false;
    _poll?.cancel();
    _poll = null;
    DownloadService.instance.tasksNotifier.removeListener(_onDownloads);
    AnnouncementService.active.removeListener(_onAnnouncements);
    _lastStatus.clear();
    _annSeen.clear();
    _seededAnnouncements = false;
  }

  static String _downloadTitle(DownloadTask t) =>
      (t.episodeTitle == null || t.episodeTitle!.isEmpty)
      ? t.title
      : '${t.title} — ${t.episodeTitle}';

  static void _onDownloads() {
    try {
      final tasks = DownloadService.instance.tasksNotifier.value;
      final live = <String>{};
      for (final t in tasks) {
        live.add(t.id);
        final prev = _lastStatus[t.id];
        _lastStatus[t.id] = t.status;
        if (prev == null || prev == t.status) continue; // first sight / no-op
        if (t.status == DownloadStatus.completed) {
          unawaited(
            NotificationService.push(
              NotificationKind.download,
              'Download finished',
              _downloadTitle(t),
            ),
          );
        } else if (t.status == DownloadStatus.failed) {
          final why = (t.error == null || t.error!.isEmpty)
              ? 'Check your connection and try again'
              : t.error!;
          unawaited(
            NotificationService.push(
              NotificationKind.download,
              'Download stopped',
              '${_downloadTitle(t)} — $why',
            ),
          );
        }
      }
      _lastStatus.removeWhere((id, _) => !live.contains(id));
    } catch (e) {
      debugPrint('[Notify] download watch failed (soft): $e');
    }
  }

  static void _onAnnouncements() {
    try {
      final list = AnnouncementService.active.value;
      if (!_seededAnnouncements) {
        // First sight — the in-app banner already shows these.
        _seededAnnouncements = true;
        for (final a in list) {
          _annSeen.add(a.id);
        }
        return;
      }
      for (final a in list) {
        if (_annSeen.add(a.id)) {
          unawaited(
            NotificationService.push(
              NotificationKind.announcement,
              a.title,
              a.body,
              id: 'ann-${a.id}',
            ),
          );
        }
      }
      // Dismissed ones drop out of `active`; forget them so a re-show of
      // the same notice after an admin re-activates it notifies again.
      _annSeen.removeWhere((id) => !list.any((a) => a.id == id));
    } catch (e) {
      debugPrint('[Notify] announcement watch failed (soft): $e');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    detach();
    _attached = false;
  }
}
