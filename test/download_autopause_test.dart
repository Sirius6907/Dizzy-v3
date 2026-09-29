import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/download/download_task_model.dart';
import 'package:dizzy/services/download/download_service.dart';

/// P3: offline auto-pause helpers — pure decision, no sockets.
void main() {
  DownloadTask task(String id, DownloadStatus status, {bool netPaused = false}) {
    return DownloadTask(
      id: id,
      title: 'T $id',
      mediaId: 'm_$id',
      type: 'movie',
      sourceType: DownloadSourceType.http,
      sourceName: 'cdn',
      targetFilePath: '/tmp/$id.mp4',
      status: status,
      netPaused: netPaused,
      createdAt: DateTime.utc(2026),
    );
  }

  group('tasksToNetPause', () {
    test('only downloading tasks are net-paused', () {
      final tasks = [
        task('a', DownloadStatus.downloading),
        task('b', DownloadStatus.queued),
        task('c', DownloadStatus.paused),
        task('d', DownloadStatus.completed),
        task('e', DownloadStatus.downloading),
      ];
      final out = DownloadService.tasksToNetPause(tasks);
      expect(out.map((t) => t.id), ['a', 'e']);
    });

    test('empty list pauses nothing', () {
      expect(DownloadService.tasksToNetPause(const []), isEmpty);
    });
  });

  group('tasksToAutoResume', () {
    test('only net-paused tasks resume — user-paused stay put', () {
      final tasks = [
        task('a', DownloadStatus.paused, netPaused: true),
        task('b', DownloadStatus.paused, netPaused: false),
        task('c', DownloadStatus.downloading),
        task('d', DownloadStatus.failed),
      ];
      final out = DownloadService.tasksToAutoResume(tasks);
      expect(out.map((t) => t.id), ['a']);
    });

    test('online return with nothing net-paused resumes nothing', () {
      final tasks = [task('a', DownloadStatus.paused)];
      expect(DownloadService.tasksToAutoResume(tasks), isEmpty);
    });
  });
}
