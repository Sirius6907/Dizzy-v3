import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/download/download_progress_text.dart';

/// Polish P7: progress honesty frozen — whole %, Easy English.
void main() {
  group('DownloadProgressText', () {
    test('whole percent rounds', () {
      expect(DownloadProgressText.wholePercent(0.423), 42);
      expect(DownloadProgressText.wholePercent(1.5), 100);
      expect(DownloadProgressText.wholePercent(-0.2), 0);
    });

    test('paused line', () {
      expect(
        DownloadProgressText.line(
          progress: 0.42,
          speedLabel: '1 MB/s',
          etaLabel: '3m 0s',
          isPaused: true,
          isFailed: false,
        ),
        'Paused at 42%',
      );
    });

    test('active line has % + speed + eta', () {
      expect(
        DownloadProgressText.line(
          progress: 0.5,
          speedLabel: '2.10 MB/s',
          etaLabel: '3m 10s',
          isPaused: false,
          isFailed: false,
        ),
        '50% • 2.10 MB/s • 3m 10s left',
      );
    });

    test('failed line keeps easy error', () {
      expect(
        DownloadProgressText.line(
          progress: 0.1,
          speedLabel: '0 KB/s',
          etaLabel: '--',
          isPaused: false,
          isFailed: true,
          error: 'Phone storage is full. Free some space.',
        ),
        contains('Phone storage is full'),
      );
    });
  });
}
