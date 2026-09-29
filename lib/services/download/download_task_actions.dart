/// F2 — one download card, whatever engine is behind it.
///
/// A task can arrive from three very different places: a torrent swarm, an
/// HLS playlist, or a plain HTTP file. Historically that produced three
/// slightly different cards — one with a peers badge, one without, one
/// whose Retry button pointed at the wrong thing. The user does not know
/// or care which engine saved their file, so the card must not either.
///
/// This file is the single contract: **status in, buttons out**. It is
/// pure and takes no engine into account, which is the whole point —
/// [actionsFor] cannot drift per engine because it never reads one. The
/// widget in `lib/widgets/download/` renders whatever this returns, and
/// the parity test asserts that across all three `DownloadSourceType`s the
/// answer is identical for the same status.
///
/// The one engine-specific thing a card may show is the *badge* — and even
/// that is a label lookup, not a behaviour difference (see [engineLabel]).
library;

import '../../models/download/download_task_model.dart';

/// A button the card may show. The widget maps each to an icon + label.
enum DownloadAction {
  /// Stop a running download. The .part file is kept so resume is exact.
  pause,

  /// Continue a paused download from where it stopped.
  resume,

  /// Start a failed download again from where it stopped.
  retry,

  /// Open the file's folder on disk.
  openFolder,

  /// Remove the task from the list.
  cancel,
}

/// What [actionsFor] returns, with the label the card prints.
class DownloadActionSet {
  final List<DownloadAction> actions;

  /// Engine badge: user-facing words only. "Torrent" and "Direct" are
  /// things people recognise; the enum names are not.
  final String engineLabel;

  const DownloadActionSet(this.actions, {required this.engineLabel});

  bool has(DownloadAction action) => actions.contains(action);
}

abstract final class DownloadTaskActions {
  /// The buttons for [task] — a function of its status alone.
  ///
  /// This is the parity guarantee, stated as code: no branch below reads
  /// `task.sourceType`. Adding an engine cannot add a button.
  static DownloadActionSet actionsFor(DownloadTask task) {
    final actions = <DownloadAction>[];
    switch (task.status) {
      case DownloadStatus.downloading:
        actions.add(DownloadAction.pause);
      case DownloadStatus.paused:
        // Paused by the user OR by the network watcher. Either way the
        // button reads the same and does the same thing.
        actions.add(DownloadAction.resume);
      case DownloadStatus.failed:
        // Retry and resume are the same call today, but they are separate
        // buttons: a failed download says "Retry" and a paused one says
        // "Resume", because "resume" on something that broke is a lie.
        actions.add(DownloadAction.retry);
      case DownloadStatus.queued:
        // Queued is not paused and not running: the engine has not started
        // it (a slot is busy, or the link is down). There is nothing to
        // pause, and re-running it would fight the queue pump.
        break;
      case DownloadStatus.completed:
        actions.add(DownloadAction.openFolder);
      case DownloadStatus.canceled:
        break;
    }
    actions.add(DownloadAction.openFolder);
    actions.add(DownloadAction.cancel);
    return DownloadActionSet(
      List<DownloadAction>.unmodifiable(actions),
      engineLabel: engineLabelFor(task.sourceType),
    );
  }

  /// Easy English badge. Never an enum name, never a URL.
  static String engineLabelFor(DownloadSourceType type) {
    switch (type) {
      case DownloadSourceType.p2p:
        return 'Torrent';
      case DownloadSourceType.debrid:
        return 'Cloud';
      case DownloadSourceType.http:
        return 'Direct';
    }
  }

  /// The line under the title for a failure. Always the Easy English text
  /// already stored on the task, never raw exception text — the technical
  /// detail has already gone to `AppErrorLog` on the failure path.
  static String failureLine(DownloadTask task) {
    if (task.status != DownloadStatus.failed) return '';
    return task.error ?? "Couldn't save. Tap Retry.";
  }
}
