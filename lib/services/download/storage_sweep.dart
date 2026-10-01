/// F2 — storage guard: low disk, suggest (never silently do) a cleanup.
///
/// The rule from the brief: "under 500MB free, suggest deleting watched
/// episodes — ask first, one-tap undo for 7 days. **Never** delete silently."
///
/// That last sentence is load-bearing, so this file produces *suggestions*
/// and nothing else. The only way a file is removed is a user tap
/// ([DownloadTrash] does the removal), and even then it is a move, not a
/// delete — see that file for why undo is only honest if the bytes survive.
///
/// Three pure decisions, unit-tested without a disk:
///
///  1. [shouldSuggest] — is the disk tight enough to interrupt the user?
///     The threshold is [StorageGuard.criticalFreeBytes] rather than a new
///     constant, so the suggestion appears exactly when downloads start
///     failing. One number, one meaning, both code paths.
///  2. [candidates] — which saved episodes to *offer*, worst-to-keep first.
///  3. [undo math] — how long the undo stays live ([undoWindow]).
///
/// "Watched" is not something the app can ask a service about — a finished
/// episode is deleted from continue-watching rather than archived, and
/// watched state lives in Trakt/Simkl behind a sign-in. So the caller
/// supplies the watched set ([WatchedEpisodeLedger]) and this file only
/// ranks. Policy stays here; I/O stays in the ledger.
library;

import '../../models/download/download_task_model.dart';
import '../../utils/perf/storage_guard.dart';

/// How many episodes one suggestion may offer. Small on purpose: a screen
/// of twenty delete buttons is a screen nobody reads, and the user can
/// always come back for more once the first batch frees space.
const int kStorageSweepMaxSuggestions = 5;

/// The line that opens the suggestion. Easy English, no file sizes, no
/// jargon — the user is not being asked to do arithmetic.
const String kStorageTightTitle = 'Phone storage is almost full';

/// The body of the suggestion. One sentence, one decision.
const String kStorageTightBody =
    'You watched these already. Delete a few to free up space?';

/// Shown while an undo is still possible.
const String kStorageUndoLabel = 'Undo';

/// Shown after the undo window closes.
const String kStorageUndoExpired = 'Undo window closed. Deleted for good.';

/// One suggested cleanup: the episode, why it is safe to offer, and how
/// much space it would give back.
class StorageSweepSuggestion {
  /// The download task that would be trashed.
  final DownloadTask task;

  /// Bytes this would free. Real numbers only — measured at the time the
  /// suggestion was built, never estimated from a guess.
  final int bytes;

  const StorageSweepSuggestion({required this.task, required this.bytes});

  /// Stable key for the trash ledger.
  String get taskId => task.id;

  /// "Frees 1.20 GB" — the whole point of the prompt, in the user's units.
  String get reclaimLabel => 'Frees ${DownloadTask.formatBytes(bytes)}';
}

/// The whole "should we interrupt?" question, as one pure call.
///
/// [freeBytes] / [totalBytes] of 0 mean the disk probe failed. A failed
/// probe must never nag the user about a problem we invented, so unknown
/// space says "no suggestion" — exactly as [StorageGuard.decideCritical]
/// already does for the download path.
bool shouldSuggestStorageCleanup({
  required int freeBytes,
  required int totalBytes,
}) {
  if (totalBytes <= 0) return false;
  if (freeBytes < StorageGuard.criticalFreeBytes) return true;
  final used = (totalBytes - freeBytes) / totalBytes;
  return used > StorageGuard.criticalUsedFraction;
}

/// Rank saved episodes into the order they should be *offered*.
///
/// Only completed, watched episodes are eligible. A download that is still
/// running, or one the user never finished, is never on this list — the
/// suggestion must be free of consequences the user did not agree to.
///
/// Order: watched before unwatched, then **oldest first**, then biggest
/// first. Oldest-first is the deliberate choice. Biggest-first frees space
/// faster, but it also puts the episode the user downloaded most recently
/// at the top of the list, which reads as "delete what I just got". An
/// episode finished months ago and not rewatched since is the one most
/// likely to be safe to give back.
List<StorageSweepSuggestion> rankStorageSweepCandidates({
  required List<DownloadTask> tasks,
  required Set<String> watchedKeys,
  required Map<String, int> sizeBytesById,
  int limit = kStorageSweepMaxSuggestions,
}) {
  if (limit <= 0) return const <StorageSweepSuggestion>[];

  final eligible = <DownloadTask>[];
  for (final task in tasks) {
    if (task.status != DownloadStatus.completed) continue;
    if (watchedKeys.contains(storageSweepKeyFor(task))) eligible.add(task);
  }

  // Stable sort: the comparator must be a total order or the list order
  // would leak the insertion order of `tasks` into the UI.
  eligible.sort((a, b) {
    final byWatched = _watchedRank(
      b,
      watchedKeys,
    ).compareTo(_watchedRank(a, watchedKeys));
    if (byWatched != 0) return byWatched;
    final aAt = a.completedAt ?? a.createdAt;
    final bAt = b.completedAt ?? b.createdAt;
    final byAge = aAt.compareTo(bAt); // oldest first
    if (byAge != 0) return byAge;
    final bySize = (sizeBytesById[b.id] ?? b.totalBytes).compareTo(
      sizeBytesById[a.id] ?? a.totalBytes,
    );
    if (bySize != 0) return bySize;
    return a.id.compareTo(b.id);
  });

  return eligible
      .take(limit)
      .map(
        (t) => StorageSweepSuggestion(
          task: t,
          bytes: sizeBytesById[t.id] ?? t.totalBytes,
        ),
      )
      .toList(growable: false);
}

int _watchedRank(DownloadTask task, Set<String> watchedKeys) =>
    watchedKeys.contains(storageSweepKeyFor(task)) ? 0 : 1;

/// The key that ties a download to the episode it is, so the watched
/// ledger and the task list can be compared without either side knowing
/// the other's storage format. `mediaId|season|episode`.
String storageSweepKeyFor(DownloadTask task) => storageSweepKey(
  mediaId: task.mediaId,
  season: task.season,
  episode: task.episode,
);

String storageSweepKey({
  required String mediaId,
  required int? season,
  required int? episode,
}) => '$mediaId|${season ?? 0}|${episode ?? 0}';

/// How long an undo stays live. Seven days, by the brief.
///
/// Long enough that "I deleted that by accident" is still plausible a week
/// later; short enough that the trash folder cannot become a second
/// permanent copy of the library.
const Duration kStorageUndoWindow = Duration(days: 7);

/// Whether an undo is still available for something trashed at
/// [trashedAt]. Exactly at the boundary the undo is gone — the window is
/// half-open, so a 7-day-old entry is expired, not "just barely alive".
bool canUndoStorageSweep({
  required DateTime? trashedAt,
  required DateTime now,
}) {
  if (trashedAt == null) return false;
  return now.difference(trashedAt) < kStorageUndoWindow;
}

/// How much longer the undo will live, or null once it is gone. The UI
/// shows this as a countdown so the user knows undo is not permanent.
Duration? storageSweepUndoRemaining({
  required DateTime? trashedAt,
  required DateTime now,
}) {
  if (trashedAt == null) return null;
  final remaining = kStorageUndoWindow - now.difference(trashedAt);
  return remaining.isNegative ? null : remaining;
}
