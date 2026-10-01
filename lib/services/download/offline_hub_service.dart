/// F2 — the offline hub: settings, live link, and the two interruptions.
///
/// Everything the hub *decides* lives in a pure policy file next to this
/// one ([AutoNextPolicy], [DownloadQualityPolicy], [StorageSweep]). What is
/// left here is the stateful shell: persisted settings, a live network
/// watch, and the two things that interrupt the user — "shall I download
/// the next episode on mobile data?" and "your storage is full, want to
/// tidy up?".
///
/// Both interruptions are the same shape, and that shape is the privacy
/// contract: **ask once, remember the answer, never interrupt again for
/// that episode.** Neither ever acts without a user tap.
///
/// The hub is deliberately the *only* thing the rest of the app talks to
/// for these features, so the player does not grow a second opinion about
/// when to download.
library;

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/download/download_task_model.dart';
import '../../utils/download/download_path_helper.dart';
import '../../utils/platform/storage_space_helper.dart';
import 'auto_next_policy.dart';
import 'download_network.dart';
import 'download_quality_profile.dart';
import 'download_service.dart';
import 'download_trash.dart';
import 'storage_sweep.dart';
import 'watched_episode_ledger.dart';

/// A pending question for the user. Exactly one can be outstanding, and it
/// is always answerable — [AutoNextPolicy] refuses to ask with no network.
class AutoNextAsk {
  /// Key that identifies the episode being offered, so an answer cannot be
  /// applied to a different episode.
  final String episodeKey;

  /// Display name for the dialog. Episode title when we have one.
  final String title;

  /// The prompt to show verbatim — [kAutoNextMeteredPrompt].
  final String message;

  const AutoNextAsk({
    required this.episodeKey,
    required this.title,
    required this.message,
  });
}

class OfflineHubService {
  OfflineHubService._();
  static final OfflineHubService instance = OfflineHubService._();

  static const _kAutoNextEnabled = 'offline_hub_auto_next_v1';
  static const _kQualityOverride = 'offline_hub_quality_override_v1';
  static const _kMeteredAutoNextAllowed = 'offline_hub_metered_auto_next_v1';

  // ── Settings ───────────────────────────────────────────────────────────

  /// Auto-next the next episode. **Defaults ON** — on WiFi the promise is
  /// that the next episode is simply there, with no tap. Metered links are
  /// still asked every time; see [AutoNextPolicy].
  final ValueNotifier<bool> autoNextEnabled = ValueNotifier<bool>(true);

  /// Settings override for the quality profile. Defaults to Automatic.
  final ValueNotifier<DownloadQualityOverride> qualityOverride =
      ValueNotifier<DownloadQualityOverride>(DownloadQualityOverride.auto);

  /// True once the user has said "yes, download on mobile data" to the
  /// *current* pending question. Reset as soon as it is answered, so the
  /// next episode on mobile data asks again. A permanent mobile-data
  /// opt-in is a different (deliberate) setting, not this flag.
  final ValueNotifier<bool> meteredAutoNextAllowed = ValueNotifier<bool>(false);

  // ── Live link ──────────────────────────────────────────────────────────

  /// The current link. Seeded to [DownloadNetwork.unknown] rather than
  /// [DownloadNetwork.wifi]: before the first probe we have no idea, and
  /// "unknown" is the answer that asks instead of spending.
  final ValueNotifier<DownloadNetwork> network =
      ValueNotifier<DownloadNetwork>(DownloadNetwork.unknown);

  // ── Interruptions ──────────────────────────────────────────────────────

  /// The outstanding "download next on mobile data?" question, or null.
  final ValueNotifier<AutoNextAsk?> pendingAutoNextAsk =
      ValueNotifier<AutoNextAsk?>(null);

  /// Live storage-cleanup suggestions. Empty means "leave the user alone".
  final ValueNotifier<List<StorageSweepSuggestion>> storageSuggestions =
      ValueNotifier<List<StorageSweepSuggestion>>(const <StorageSweepSuggestion>[]);

  /// Free bytes on the downloads partition, or null when unknown. Real
  /// number, refreshed with every [refreshStorageSuggestions].
  final ValueNotifier<int?> freeBytes = ValueNotifier<int?>(null);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      // Absent key ⇒ the default. A user who has never opened Settings
      // gets the promised behaviour, not a false opt-out.
      autoNextEnabled.value = prefs.getBool(_kAutoNextEnabled) ?? true;
      qualityOverride.value = DownloadQualityOverride.fromName(
        prefs.getString(_kQualityOverride),
      );
      meteredAutoNextAllowed.value = prefs.getBool(_kMeteredAutoNextAllowed) ?? false;
    } catch (_) {
      // Defaults already hold. An unreadable store must not disable the
      // feature; it must only lose the user's customisation.
    }

    await WatchedEpisodeLedger.initialize();
    _startNetworkWatch();
    unawaited(refreshStorageSuggestions());
  }

  Future<void> setAutoNextEnabled(bool value) async {
    autoNextEnabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAutoNextEnabled, value);
    } catch (_) {}
    if (!value) pendingAutoNextAsk.value = null;
  }

  Future<void> setQualityOverride(DownloadQualityOverride value) async {
    qualityOverride.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kQualityOverride, value.name);
    } catch (_) {}
  }

  // ── Network ────────────────────────────────────────────────────────────

  void _startNetworkWatch() {
    if (_connectivitySub != null) return;
    try {
      _connectivitySub =
          Connectivity().onConnectivityChanged.listen(_onConnectivity);
      Connectivity().checkConnectivity().then(_onConnectivity).catchError((_) {});
    } catch (_) {
      // Best-effort. Without the watcher the link stays `unknown`, which
      // asks instead of spending — the safe direction for a failed probe.
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final kind = classifyConnectivity(results);
    if (network.value == kind) return;
    network.value = kind;
    // Coming back online retires the "waiting" answer so the caller can
    // offer again on the link that actually exists now.
    if (kind != DownloadNetwork.offline) meteredAutoNextAllowed.value = false;
  }

  /// The quality profile that applies right now, honouring the override.
  DownloadQualityProfile activeProfile() => DownloadQualityPolicy.pick(
        network: network.value,
        override: qualityOverride.value,
      );

  // ── Auto-next ──────────────────────────────────────────────────────────

  /// The episode the user should be asked about, or queued outright.
  ///
  /// This is the entry point the player calls after a download starts. It
  /// never downloads by itself: on WiFi it *reports* [AutoNextDecision
  /// .queueNow] and the caller acts; on mobile data it raises
  /// [pendingAutoNextAsk] and waits. Keeping the action with the caller is
  /// what makes "did we ask first?" auditable — the policy file cannot
  /// reach a download on its own.
  ///
  /// [nextEpisodeKey] identifies the candidate ("mediaId|s|e"), and
  /// [alreadySaved] is the caller's dedup answer.
  AutoNextDecision considerNextEpisode({
    required String nextEpisodeKey,
    required String title,
    required bool hasNextEpisode,
    required bool alreadySaved,
  }) {
    final decision = AutoNextPolicy.decide(
      autoNextEnabled: autoNextEnabled.value,
      network: network.value,
      hasNextEpisode: hasNextEpisode,
      alreadySaved: alreadySaved,
    );
    switch (decision) {
      case AutoNextDecision.askFirst:
        // One outstanding question at a time. A second episode arriving
        // while the first is still unanswered must not replace it — the
        // user is mid-decision, and swapping the question under them is
        // how an app starts feeling pushy. It is offered again once this
        // one is answered.
        pendingAutoNextAsk.value ??= AutoNextAsk(
          episodeKey: nextEpisodeKey,
          title: title,
          message: kAutoNextMeteredPrompt,
        );
      case AutoNextDecision.off:
      case AutoNextDecision.waitingForNetwork:
      case AutoNextDecision.alreadySaved:
      case AutoNextDecision.nothingNext:
      case AutoNextDecision.queueNow:
        break;
    }
    return decision;
  }

  /// Answer the outstanding question. [yes] queues, [no] leaves the episode
  /// alone. The question is retired either way — the same episode is never
  /// nagged about twice.
  void answerAutoNextAsk({required bool yes}) {
    if (yes) meteredAutoNextAllowed.value = true;
    pendingAutoNextAsk.value = null;
  }

  /// Clear the one-shot "yes". Called once the queued download starts, so
  /// the *next* episode on mobile data asks again.
  void consumeMeteredAutoNextAllowance() {
    meteredAutoNextAllowed.value = false;
  }

  // ── Storage guard ──────────────────────────────────────────────────────

  /// Probe the disk and, when it is tight, rank watched episodes to offer.
  ///
  /// This only ever *computes* suggestions. The user taps to act, and
  /// [DownloadTrash] turns that tap into a move the undo can reverse. There
  /// is no code path from "disk is full" to "file is gone".
  Future<List<StorageSweepSuggestion>> refreshStorageSuggestions() async {
    int? free;
    int total = 0;
    try {
      final dir = await DownloadPathHelper.getDownloadsDirectoryPath();
      final info = await StorageSpaceHelper.getAvailableSpace(dir);
      free = info?.freeBytes;
      total = info?.totalBytes ?? 0;
    } catch (_) {
      // Probe failed. Unknown space never nags the user.
      freeBytes.value = free;
      storageSuggestions.value = const <StorageSweepSuggestion>[];
      return storageSuggestions.value;
    }

    freeBytes.value = free;
    if (free == null ||
        !shouldSuggestStorageCleanup(freeBytes: free, totalBytes: total)) {
      storageSuggestions.value = const <StorageSweepSuggestion>[];
      return storageSuggestions.value;
    }

    final tasks = DownloadService.instance.tasksNotifier.value;
    final sizes = await measureTaskSizes(tasks);
    final suggestions = rankStorageSweepCandidates(
      tasks: tasks,
      watchedKeys: WatchedEpisodeLedger.watchedKeys(),
      sizeBytesById: sizes,
    );
    storageSuggestions.value = suggestions;
    return suggestions;
  }

  /// Real file sizes for the completed tasks, falling back to the recorded
  /// total when the file has already gone. Never estimates.
  static Future<Map<String, int>> measureTaskSizes(List<DownloadTask> tasks) async {
    final sizes = <String, int>{};
    for (final task in tasks) {
      if (task.status != DownloadStatus.completed) continue;
      try {
        final file = File(task.targetFilePath);
        sizes[task.id] = await file.exists() ? await file.length() : task.totalBytes;
      } catch (_) {
        sizes[task.id] = task.totalBytes;
      }
    }
    return sizes;
  }

  /// Act on a suggestion. Only ever called from a user tap.
  Future<TrashEntry?> trashSuggested(StorageSweepSuggestion suggestion) async {
    final entry = await DownloadTrash.trash(suggestion.task);
    await refreshStorageSuggestions();
    return entry;
  }

  /// Reverse a trash, inside the undo window.
  Future<bool> undoTrash(String taskId) async {
    final ok = await DownloadTrash.undo(taskId);
    await refreshStorageSuggestions();
    return ok;
  }

  /// Clear suggestions without acting. The user dismissed the prompt.
  void dismissStorageSuggestions() {
    storageSuggestions.value = const <StorageSweepSuggestion>[];
  }

  /// Re-arm [initialize] for a test that swapped the backing store.
  ///
  /// The one-shot init guard is right in production — a singleton must not
  /// re-read preferences behind the UI's back — but it would otherwise make
  /// "absent key means ON" and "stored false is honoured" untestable in the
  /// same file, which are exactly the two halves of that promise.
  @visibleForTesting
  void resetForTest() {
    _initialized = false;
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }
}
