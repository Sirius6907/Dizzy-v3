import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/download/download_task_model.dart';
import 'package:dizzy/services/download/download_error_text.dart';
import 'package:dizzy/services/download/download_service.dart';
import 'package:dizzy/services/errors/app_error_log.dart';

DownloadTask _task(String id, DownloadStatus status, {bool netPaused = false}) {
  return DownloadTask(
    id: id,
    title: 'T',
    mediaId: 'm',
    type: 'movie',
    sourceType: DownloadSourceType.http,
    sourceName: 'Direct',
    targetFilePath: '/tmp/$id.mp4',
    status: status,
    netPaused: netPaused,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('DownloadErrorText.classify', () {
    test('timeout/socket → E_NET_TIMEOUT', () {
      expect(DownloadErrorText.classify('SocketException: connection reset'),
          equals('E_NET_TIMEOUT'));
      expect(
          DownloadErrorText.classify(
              'ClientException: connection timed out after 20s'),
          equals('E_NET_TIMEOUT'));
    });
    test('http codes map correctly', () {
      expect(DownloadErrorText.classify('Server returned HTTP 403: Forbidden'),
          equals('E_HTTP_401_403'));
      expect(DownloadErrorText.classify('Server returned HTTP 404: Not Found'),
          equals('E_HTTP_404_410'));
      expect(DownloadErrorText.classify('Server returned HTTP 503: busy'),
          equals('E_HTTP_5XX'));
      expect(DownloadErrorText.classify('range_not_satisfiable'),
          equals('E_HTTP_416_RANGE'));
    });
    test('space / file / engines', () {
      expect(
          DownloadErrorText.classify('Insufficient free disk space'),
          equals('E_SPACE_FULL'));
      expect(DownloadErrorText.classify('Empty download URL'),
          equals('E_FILE_GONE'));
      expect(DownloadErrorText.classify('TorrServer could not resolve'),
          equals('E_P2P_ENGINE'));
      expect(DownloadErrorText.classify('Debrid cloud returned no links'),
          equals('E_DEBRID_RESOLVE'));
      expect(DownloadErrorText.classify('m3u8 playlist parse failed'),
          equals('E_HLS_PARSE'));
    });
    test('unknown falls back to E_UNKNOWN', () {
      expect(DownloadErrorText.classify('weird gibberish xyz'),
          equals('E_UNKNOWN'));
    });
  });

  group('DownloadErrorText.easyText — no tech words', () {
    const banned = [
      'http',
      'socket',
      'exception',
      'torrserver',
      'magnet',
      'hls',
      'm3u8',
      'debrid',
      'range',
      '401',
      '404',
      '416',
      'url'
    ];
    test('all codes produce easy lines without banned words', () {
      const codes = [
        'E_NET_TIMEOUT',
        'E_HTTP_401_403',
        'E_HTTP_404_410',
        'E_HTTP_416_RANGE',
        'E_HTTP_5XX',
        'E_SPACE_FULL',
        'E_FILE_GONE',
        'E_P2P_ENGINE',
        'E_DEBRID_RESOLVE',
        'E_HLS_PARSE',
        'E_UNKNOWN',
      ];
      for (final code in codes) {
        final line = DownloadErrorText.easyText(code).toLowerCase();
        expect(line.isNotEmpty, isTrue, reason: code);
        for (final word in banned) {
          expect(line.contains(word), isFalse, reason: '$code contains $word');
        }
      }
    });
  });

  group('net pause/resume policy (pure)', () {
    test('only downloading tasks are net-paused', () {
      final tasks = [
        _task('a', DownloadStatus.downloading),
        _task('b', DownloadStatus.paused),
        _task('c', DownloadStatus.queued),
        _task('d', DownloadStatus.failed),
      ];
      final result = DownloadService.tasksToNetPause(tasks);
      expect(result.map((t) => t.id), equals(['a']));
    });

    test('only net-paused tasks auto-resume (never user-paused)', () {
      final tasks = [
        _task('a', DownloadStatus.paused, netPaused: true),
        _task('b', DownloadStatus.paused, netPaused: false),
        _task('c', DownloadStatus.downloading, netPaused: true),
      ];
      final result = DownloadService.tasksToAutoResume(tasks);
      expect(result.map((t) => t.id), equals(['a']));
    });

    test('netPaused survives JSON round-trip', () {
      final task = _task('x', DownloadStatus.paused, netPaused: true);
      final back = DownloadTask.fromJson(task.toJson());
      expect(back.netPaused, isTrue);
    });

    test('old JSON without netPaused defaults to false', () {
      final task = _task('y', DownloadStatus.paused);
      final json = task.toJson()..remove('netPaused');
      final back = DownloadTask.fromJson(json);
      expect(back.netPaused, isFalse);
    });
  });

  group('AppErrorLog.shouldThrottle (pure)', () {
    test('same code+screen within 24h throttles', () {
      const now = 1000000000000;
      expect(
          AppErrorLog.shouldThrottle(
              now - const Duration(hours: 1).inMilliseconds, now),
          isTrue);
    });
    test('after 24h it sends again', () {
      const now = 1000000000000;
      expect(
          AppErrorLog.shouldThrottle(
              now - const Duration(hours: 25).inMilliseconds, now),
          isFalse);
    });
  });
}
