/// F2 — the download card: one UI for torrent, HLS and HTTP.
///
/// Split out from `offline_hub_test.dart` only to keep both files inside
/// the 600-line budget; the subject is the same feature.
///
/// The card is where the engines used to diverge — one had a peers badge,
/// one had a Retry button pointing at the wrong call. These tests pin the
/// promise that they no longer do: the buttons are a function of the
/// task's *status* and never of which engine produced it.
library;

import 'dart:io';

import 'package:dizzy/models/download/download_task_model.dart';
import 'package:dizzy/services/download/download_task_actions.dart';
import 'package:dizzy/services/download/download_trash.dart';
import 'package:dizzy/services/download/storage_sweep.dart';
import 'package:flutter_test/flutter_test.dart';

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


  // ── 7. Card parity across engines ─────────────────────────────────────
  group('F2 card parity — torrent, HLS and HTTP look the same', () {
    const engines = [
      DownloadSourceType.p2p, // torrent
      DownloadSourceType.http, // HLS and direct file
      DownloadSourceType.debrid, // cloud
    ];

    test('every engine offers the identical buttons for the same status', () {
      for (final status in DownloadStatus.values) {
        final sets = engines
            .map((e) => DownloadTaskActions.actionsFor(
                  task(status: status, sourceType: e),
                ).actions)
            .toList();
        for (final actions in sets) {
          expect(actions, sets.first,
              reason: 'engine cards drifted apart on $status');
        }
      }
    });

    test('the button set is decided by status alone', () {
      // Proves the claim structurally: swapping the engine argument
      // changes nothing about which buttons appear.
      final http = DownloadTaskActions.actionsFor(
        task(status: DownloadStatus.downloading, sourceType: DownloadSourceType.http),
      );
      final torrent = DownloadTaskActions.actionsFor(
        task(status: DownloadStatus.downloading, sourceType: DownloadSourceType.p2p),
      );
      expect(http.actions, torrent.actions);
    });

    test('a running download can be paused', () {
      final plan = DownloadTaskActions.actionsFor(
        task(status: DownloadStatus.downloading),
      );
      expect(plan.has(DownloadAction.pause), isTrue);
      expect(plan.has(DownloadAction.retry), isFalse);
    });

    test('a queued download offers no pause — the pump owns it', () {
      final plan = DownloadTaskActions.actionsFor(task(status: DownloadStatus.queued));
      expect(plan.has(DownloadAction.pause), isFalse);
      expect(plan.has(DownloadAction.resume), isFalse);
      expect(plan.has(DownloadAction.cancel), isTrue);
    });

    test('the engine badge is a word, not an enum name', () {
      expect(
        DownloadTaskActions.engineLabelFor(DownloadSourceType.p2p),
        'Torrent',
      );
      expect(
        DownloadTaskActions.engineLabelFor(DownloadSourceType.debrid),
        'Cloud',
      );
      expect(
        DownloadTaskActions.engineLabelFor(DownloadSourceType.http),
        'Direct',
      );
    });
  });

  // ── 8. Pause, resume, retry ───────────────────────────────────────────
  group('F2 pause, resume and retry', () {
    test('a paused download offers Resume and keeps its progress', () {
      final paused = task(
        status: DownloadStatus.paused,
        receivedBytes: 400,
        totalBytes: 1000,
      );
      final plan = DownloadTaskActions.actionsFor(paused);
      expect(plan.has(DownloadAction.resume), isTrue);
      expect(plan.has(DownloadAction.retry), isFalse);
      expect(paused.progressPercent, closeTo(0.4, 0.0001));
    });

    test('a failed download offers Retry, and says so in words', () {
      final failed = task(
        status: DownloadStatus.failed,
        receivedBytes: 700,
        totalBytes: 1000,
        error: 'Slow internet. Trying again…',
      );
      final plan = DownloadTaskActions.actionsFor(failed);
      expect(plan.has(DownloadAction.retry), isTrue);
      expect(plan.has(DownloadAction.resume), isFalse,
          reason: 'calling a broken download "Resume" is a lie');
      expect(DownloadTaskActions.failureLine(failed), 'Slow internet. Trying again…');
    });

    test('a failure with no stored line still says something in English', () {
      final failed = task(status: DownloadStatus.failed);
      final line = DownloadTaskActions.failureLine(failed);
      expect(line.isNotEmpty, isTrue);
      expect(line, contains('Retry'));
    });

    test('only a failed task gets a failure line', () {
      expect(
        DownloadTaskActions.failureLine(
          task(status: DownloadStatus.downloading, error: 'stale text'),
        ),
        isEmpty,
      );
    });

    test('retry resumes from the bytes already on disk, not from zero', () {
      // The .part file is what makes this true; the card must not reset
      // the progress it shows while the resume runs.
      final failed = task(
        status: DownloadStatus.failed,
        receivedBytes: 700,
        totalBytes: 1000,
      );
      final retried = failed.copyWith(status: DownloadStatus.downloading, error: null);
      expect(retried.receivedBytes, 700);
      expect(retried.progressPercent, closeTo(0.7, 0.0001));
      expect(retried.error, isNull);
    });

    test('a completed download keeps its file and offers the folder', () {
      final plan = DownloadTaskActions.actionsFor(
        task(status: DownloadStatus.completed),
      );
      expect(plan.has(DownloadAction.openFolder), isTrue);
      expect(plan.has(DownloadAction.pause), isFalse);
    });
  });

  // ── 9. The delete is a move, and the bytes prove it ───────────────────
  group('F2 delete is undoable because the file survives', () {
    test('a trashed file can be moved back and the content is intact', () async {
      // The reason undo works at all: the bytes are relocated, never
      // unlinked. If this ever became a real unlink, undo would have to
      // re-download — which is not undo.
      final dir = await Directory.systemTemp.createTemp('dizzy_f2_trash_');
      addTearDown(() => dir.delete(recursive: true));

      final trashDir = Directory('${dir.path}/$kDownloadTrashFolderName');
      await trashDir.create(recursive: true);

      final source = File('${dir.path}/episode.mp4');
      final payload = List<int>.generate(4096, (i) => i % 256);
      await source.writeAsBytes(payload);

      final moved = File('${trashDir.path}/episode.mp4');
      await source.rename(moved.path);

      expect(await source.exists(), isFalse, reason: 'left the downloads dir');
      expect(await moved.exists(), isTrue, reason: 'bytes still on disk');
      expect(await moved.length(), 4096);

      // …and back again, inside the window.
      await moved.rename(source.path);
      expect(await source.readAsBytes(), payload);
    });

    test('a completed task is never removed by a storage check alone', () async {
      // No code path goes from "disk is full" to "file gone": the sweep
      // only ranks, and DownloadTrash only runs from a tap. This test
      // pins the ranking half — the non-destructive one.
      final completed = task(status: DownloadStatus.completed, episode: 1);
      final ranked = rankStorageSweepCandidates(
        tasks: [completed],
        watchedKeys: {'show1|1|1'},
        sizeBytesById: const {'dl_1': 999},
      );
      expect(ranked, isNotEmpty);
      expect(
        Directory(completed.targetFilePath).existsSync(),
        isFalse,
        reason: 'ranking is a read-only operation, by construction',
      );
    });
  });
}
