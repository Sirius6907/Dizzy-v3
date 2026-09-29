/// F2 — the smart offline hub.
///
/// These tests are mostly about the things that would be *invisible* in a
/// demo and expensive in a real user's month: spending mobile data
/// without asking, deleting a file the user wanted, and offering a Retry
/// button that quietly does nothing.
///
/// The policies are pure, so the suite runs the real production functions
/// rather than re-implementations — a test that mirrors the logic proves
/// nothing. Where a rule is stated as an invariant ("metered may only ever
/// ask"), the test asserts the invariant across every input combination
/// instead of one hand-picked case.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dizzy/models/download/download_task_model.dart';
import 'package:dizzy/services/download/auto_next_policy.dart';
import 'package:dizzy/services/download/download_network.dart';
import 'package:dizzy/services/download/download_quality_profile.dart';
import 'package:dizzy/services/download/download_trash.dart';
import 'package:dizzy/services/download/offline_hub_service.dart';
import 'package:dizzy/services/download/storage_sweep.dart';
import 'package:dizzy/services/player/quality_service.dart';
import 'package:dizzy/utils/perf/storage_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DownloadTask task({
  String id = 'dl_1',
  DownloadStatus status = DownloadStatus.queued,
  DownloadSourceType sourceType = DownloadSourceType.http,
  int? season = 1,
  int? episode = 1,
  int totalBytes = 1000,
  int receivedBytes = 0,
  DateTime? completedAt,
  String? error,
}) {
  final at = completedAt ?? DateTime(2026, 1, 1);
  return DownloadTask(
    id: id,
    title: 'Show S01E01',
    mediaId: 'show1',
    type: 'series',
    season: season,
    episode: episode,
    sourceType: sourceType,
    sourceName: 'test',
    targetFilePath: '/downloads/$id.mp4',
    status: status,
    totalBytes: totalBytes,
    receivedBytes: receivedBytes,
    error: error,
    netPaused: false,
    createdAt: at,
    completedAt: status == DownloadStatus.completed ? at : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 1. Auto-next on WiFi ───────────────────────────────────────────────
  group('F2 auto-next — unmetered', () {
    test('WiFi queues the next episode silently', () {
      expect(
        AutoNextPolicy.decide(
          autoNextEnabled: true,
          network: DownloadNetwork.wifi,
          hasNextEpisode: true,
          alreadySaved: false,
        ),
        AutoNextDecision.queueNow,
      );
      expect(AutoNextDecision.queueNow.isAuto, isTrue);
      expect(AutoNextDecision.queueNow.needsAsk, isFalse);
    });

    test('the real hub defaults auto-next ON, with an empty store', () async {
      // A user who has never opened Settings must still get the promised
      // behaviour. This reads the actual singleton rather than restating
      // the default, so a future "opt-in" flip cannot pass unnoticed.
      OfflineHubService.instance.resetForTest();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await OfflineHubService.instance.initialize();
      expect(OfflineHubService.instance.autoNextEnabled.value, isTrue);

      final decision = AutoNextPolicy.decide(
        autoNextEnabled: OfflineHubService.instance.autoNextEnabled.value,
        network: DownloadNetwork.wifi,
        hasNextEpisode: true,
        alreadySaved: false,
      );
      expect(decision, AutoNextDecision.queueNow);
    });

    test('a stored opt-out is honoured', () async {
      OfflineHubService.instance.resetForTest();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'offline_hub_auto_next_v1': false,
      });
      await OfflineHubService.instance.initialize();
      expect(OfflineHubService.instance.autoNextEnabled.value, isFalse);
    });

    test('toggle off silences even on WiFi', () {
      expect(
        AutoNextPolicy.decide(
          autoNextEnabled: false,
          network: DownloadNetwork.wifi,
          hasNextEpisode: true,
          alreadySaved: false,
        ),
        AutoNextDecision.off,
      );
    });

    test('an already-saved next episode is never queued twice', () {
      expect(
        AutoNextPolicy.decide(
          autoNextEnabled: true,
          network: DownloadNetwork.wifi,
          hasNextEpisode: true,
          alreadySaved: true,
        ),
        AutoNextDecision.alreadySaved,
      );
    });

    test('end of season queues nothing and asks nothing', () {
      expect(
        AutoNextPolicy.decide(
          autoNextEnabled: true,
          network: DownloadNetwork.wifi,
          hasNextEpisode: false,
          alreadySaved: false,
        ),
        AutoNextDecision.nothingNext,
      );
    });
  });

  // ── 2. Auto-next on mobile data ───────────────────────────────────────
  group('F2 auto-next — metered asks first', () {
    test('mobile data asks, in the exact Easy English line', () {
      expect(
        AutoNextPolicy.decide(
          autoNextEnabled: true,
          network: DownloadNetwork.mobile,
          hasNextEpisode: true,
          alreadySaved: false,
        ),
        AutoNextDecision.askFirst,
      );
      expect(kAutoNextMeteredPrompt, 'Download next on mobile data?');
    });

    test('an unclassifiable network is treated as metered, not free', () {
      // A VPN riding a phone hotspot must not be mistaken for WiFi.
      expect(
        AutoNextPolicy.decide(
          autoNextEnabled: true,
          network: DownloadNetwork.unknown,
          hasNextEpisode: true,
          alreadySaved: false,
        ),
        AutoNextDecision.askFirst,
      );
      expect(DownloadNetwork.unknown.isUnmetered, isFalse);
    });

    test('offline never asks — there is no answer to give yet', () {
      expect(
        AutoNextPolicy.decide(
          autoNextEnabled: true,
          network: DownloadNetwork.offline,
          hasNextEpisode: true,
          alreadySaved: false,
        ),
        AutoNextDecision.waitingForNetwork,
      );
    });

    test('INVARIANT: no metered link can ever auto-download', () {
      // Exhaustive over every combination, not one hand-picked case.
      for (final toggle in [true, false]) {
        for (final network in DownloadNetwork.values) {
          for (final hasNext in [true, false]) {
            for (final saved in [true, false]) {
              final decision = AutoNextPolicy.decide(
                autoNextEnabled: toggle,
                network: network,
                hasNextEpisode: hasNext,
                alreadySaved: saved,
              );
              if (network.needsConsent) {
                expect(
                  decision.isAuto,
                  isFalse,
                  reason: 'metered link ${network.name} must never auto-download '
                      '(toggle=$toggle hasNext=$hasNext saved=$saved)',
                );
              }
            }
          }
        }
      }
    });

    test('the prompt is Easy English — no jargon, no plan names', () {
      const banned = [
        'metered',
        'bandwidth',
        'gigabyte',
        'gb',
        'bandwidth cap',
        'wifi off',
        'mobile data limit',
        'roaming',
      ];
      final text = kAutoNextMeteredPrompt.toLowerCase();
      for (final word in banned) {
        expect(text.contains(word), isFalse, reason: 'prompt leaks "$word"');
      }
    });
  });

  // ── 3. Connectivity classification ────────────────────────────────────
  group('F2 network classification', () {
    test('WiFi is free to spend on', () {
      expect(
        classifyConnectivity([ConnectivityResult.wifi]),
        DownloadNetwork.wifi,
      );
    });

    test('cellular is metered', () {
      expect(
        classifyConnectivity([ConnectivityResult.mobile]),
        DownloadNetwork.mobile,
      );
      expect(DownloadNetwork.mobile.needsConsent, isTrue);
    });

    test('a VPN riding WiFi still rides WiFi', () {
      expect(
        classifyConnectivity([ConnectivityResult.vpn, ConnectivityResult.wifi]),
        DownloadNetwork.wifi,
      );
    });

    test('no transport at all is offline, not metered', () {
      expect(
        classifyConnectivity([ConnectivityResult.none]),
        DownloadNetwork.offline,
      );
    });

    test('a failed probe (empty list) is unknown, never offline', () {
      // Mistaking a failed probe for "no internet" would silently stall
      // every queued download; mistaking it for WiFi would spend data.
      expect(classifyConnectivity(const []), DownloadNetwork.unknown);
    });

    test('labels are plain words a user recognises', () {
      expect(DownloadNetwork.wifi.label, 'WiFi');
      expect(DownloadNetwork.mobile.label, 'Mobile data');
      expect(DownloadNetwork.offline.label, 'No internet');
    });
  });

  // ── 4. Quality profiles ───────────────────────────────────────────────
  group('F2 quality profiles', () {
    test('each link gets its own rung when set to Automatic', () {
      expect(
        DownloadQualityPolicy.autoFor(DownloadNetwork.wifi),
        DownloadQualityProfile.wifi1080,
      );
      expect(
        DownloadQualityPolicy.autoFor(DownloadNetwork.mobile),
        DownloadQualityProfile.data720,
      );
    });

    test('an unclassifiable link takes the cheap rung, not the dear one', () {
      expect(
        DownloadQualityPolicy.autoFor(DownloadNetwork.unknown),
        DownloadQualityProfile.saver480,
      );
    });

    test('a Settings override beats the link, even a flaky one', () {
      for (final network in DownloadNetwork.values) {
        expect(
          DownloadQualityPolicy.pick(
            network: network,
            override: DownloadQualityOverride.saver480,
          ),
          DownloadQualityProfile.saver480,
          reason: 'override must not flip on ${network.name}',
        );
      }
    });

    test('profiles resolve through the player ladder, not a second copy', () {
      // One definition of "720p" in the app: if this ever drifts, a user
      // downloads a 480p file labelled 720p.
      expect(
        DownloadQualityPolicy.choiceFor(
          network: DownloadNetwork.mobile,
          override: DownloadQualityOverride.auto,
        ),
        QualityChoice.q720,
      );
      expect(
        DownloadQualityPolicy.choiceFor(
          network: DownloadNetwork.wifi,
          override: DownloadQualityOverride.auto,
        ),
        QualityChoice.q1080,
      );
    });

    test('a corrupt stored override degrades to Automatic, not a crash', () {
      expect(
        DownloadQualityOverride.fromName('q9999'),
        DownloadQualityOverride.auto,
      );
      expect(DownloadQualityOverride.fromName(null), DownloadQualityOverride.auto);
      expect(
        DownloadQualityOverride.fromName('saver480'),
        DownloadQualityOverride.saver480,
      );
    });
  });

  // ── 5. Storage guard threshold ────────────────────────────────────────
  group('F2 storage guard', () {
    const mb = 1024 * 1024;
    const gb = 1024 * mb;

    test('under 500MB free suggests a cleanup', () {
      expect(
        shouldSuggestStorageCleanup(freeBytes: 400 * mb, totalBytes: 64 * gb),
        isTrue,
      );
    });

    test('a roomy disk stays silent — no nagging on a healthy phone', () {
      expect(
        shouldSuggestStorageCleanup(freeBytes: 20 * gb, totalBytes: 64 * gb),
        isFalse,
      );
    });

    test('a nearly full disk with headroom still suggests', () {
      expect(
        shouldSuggestStorageCleanup(freeBytes: 6 * gb, totalBytes: 128 * gb),
        isTrue,
      );
    });

    test('a failed disk probe never nags the user', () {
      expect(
        shouldSuggestStorageCleanup(freeBytes: 0, totalBytes: 0),
        isFalse,
      );
    });

    test('the suggestion fires exactly when downloads start failing', () {
      // The invariant that matters is not "under 500MB" on its own — the
      // download path blocks on free-bytes OR on >90% used, so the guard
      // must agree with it on *every* disk, not just one boundary. If the
      // two ever disagree, downloads fail while the app says all is well.
      for (final total in [8 * gb, 64 * gb, 128 * gb, 1024 * gb]) {
        for (final free in [0, 300 * mb, 499 * mb, 500 * mb, 2 * gb, total ~/ 2]) {
          expect(
            shouldSuggestStorageCleanup(freeBytes: free, totalBytes: total),
            StorageGuard.decideCritical(freeBytes: free, totalBytes: total),
            reason: 'guard and download path disagreed at $free/$total',
          );
        }
      }
    });

    test('only completed, watched episodes are ever offered', () {
      final tasks = [
        task(id: 'a', status: DownloadStatus.completed, completedAt: DateTime(2025, 1, 1), episode: 1),
        task(id: 'b', status: DownloadStatus.downloading, episode: 2),
        task(id: 'c', status: DownloadStatus.completed, completedAt: DateTime(2025, 2, 1), episode: 3),
        task(id: 'd', status: DownloadStatus.completed, completedAt: DateTime(2025, 3, 1), episode: 4),
      ];
      final ranked = rankStorageSweepCandidates(
        tasks: tasks,
        watchedKeys: {'show1|1|1', 'show1|1|3'},
        sizeBytesById: const {'a': 100, 'b': 100, 'c': 100, 'd': 100},
      );
      final ids = ranked.map((s) => s.taskId).toSet();
      expect(ids, {'a', 'c'});
      expect(ids.contains('b'), isFalse, reason: 'a running download is not offerable');
      expect(ids.contains('d'), isFalse, reason: 'an unwatched episode is not offerable');
    });

    test('oldest watched episode is offered first', () {
      final tasks = [
        task(id: 'new', status: DownloadStatus.completed, completedAt: DateTime(2026, 6, 1), episode: 1),
        task(id: 'old', status: DownloadStatus.completed, completedAt: DateTime(2024, 1, 1), episode: 2),
      ];
      final ranked = rankStorageSweepCandidates(
        tasks: tasks,
        watchedKeys: {'show1|1|1', 'show1|1|2'},
        sizeBytesById: const {'new': 1, 'old': 1},
      );
      expect(ranked.first.taskId, 'old');
    });

    test('reclaim figures are real numbers, not estimates', () {
      final ranked = rankStorageSweepCandidates(
        tasks: [task(status: DownloadStatus.completed, episode: 1)],
        watchedKeys: {'show1|1|1'},
        sizeBytesById: const {'dl_1': 1536 * 1024 * 1024},
      );
      expect(ranked.single.bytes, 1536 * 1024 * 1024);
      expect(ranked.single.reclaimLabel, contains('GB'));
    });

    test('the offer list is short on purpose', () {
      final tasks = List.generate(
        20,
        (i) => task(
          id: 't$i',
          status: DownloadStatus.completed,
          episode: i + 1,
          completedAt: DateTime(2020, 1, 1 + i),
        ),
      );
      final ranked = rankStorageSweepCandidates(
        tasks: tasks,
        watchedKeys: tasks.map((t) => 'show1|1|${t.episode}').toSet(),
        sizeBytesById: const {},
        limit: kStorageSweepMaxSuggestions,
      );
      expect(ranked.length, kStorageSweepMaxSuggestions);
    });
  });

  // ── 6. Undo window ────────────────────────────────────────────────────
  group('F2 undo window', () {
    final trashedAt = DateTime(2026, 3, 1);

    test('undo is live one second after the delete', () {
      expect(
        canUndoStorageSweep(
          trashedAt: trashedAt,
          now: trashedAt.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('undo is still live on day six', () {
      expect(
        canUndoStorageSweep(
          trashedAt: trashedAt,
          now: trashedAt.add(const Duration(days: 6, hours: 23)),
        ),
        isTrue,
      );
    });

    test('undo is gone at exactly seven days — the window is half-open', () {
      expect(
        canUndoStorageSweep(
          trashedAt: trashedAt,
          now: trashedAt.add(const Duration(days: 7)),
        ),
        isFalse,
      );
    });

    test('a file that was never trashed has no undo', () {
      expect(canUndoStorageSweep(trashedAt: null, now: trashedAt), isFalse);
      expect(storageSweepUndoRemaining(trashedAt: null, now: trashedAt), isNull);
    });

    test('the countdown reports real remaining time, then stops', () {
      expect(
        storageSweepUndoRemaining(
          trashedAt: trashedAt,
          now: trashedAt.add(const Duration(days: 2)),
        ),
        const Duration(days: 5),
      );
      expect(
        storageSweepUndoRemaining(
          trashedAt: trashedAt,
          now: trashedAt.add(const Duration(days: 8)),
        ),
        isNull,
      );
    });

    test('a trash entry survives a save/load round trip', () {
      final entry = TrashEntry(
        taskId: 'dl_1',
        originalPath: '/downloads/a.mp4',
        trashPath: '/downloads/.trash/a.mp4',
        trashedAt: trashedAt,
        bytes: 4096,
      );
      final restored = TrashEntry.fromJson(entry.toJson());
      expect(restored, isNotNull);
      expect(restored!.taskId, 'dl_1');
      expect(restored.bytes, 4096);
      expect(restored.trashedAt, trashedAt);
      expect(restored.canUndo(now: trashedAt.add(const Duration(days: 1))), isTrue);
    });

    test('a corrupt ledger row is dropped, not trusted', () {
      expect(TrashEntry.fromJson(const {'taskId': 'x'}), isNull);
    });
  });
}
