// Regression: a dead torrent hash must not be polled to the timeout.
//
// Device evidence (2026-11-16, emulator-5554): after a torrent was dropped
// from the local TorrServer engine, the metadata poller kept asking for it
// every 300ms and got a 404 every time - ~75 wasted requests and ~75 log
// lines over 23 seconds, while the player sat on a black frame.
//
// TorrServer answers 404 for a hash it does not have. That answer is final:
// the torrent can never appear under the same hash, so the wait has to end.
import 'package:flutter_test/flutter_test.dart';
import 'package:torrserver_flutter/torrserver_flutter.dart';

import 'package:dizzy/services/stream/torrent_stream_service.dart';

void main() {
  test('a 404 from the engine means the torrent is gone', () {
    expect(
      TorrentStreamService.isTorrentGone(
        const TorrServerHttpException('Request to /torrents failed', 404, ''),
      ),
      isTrue,
    );
  });

  test('other engine errors are not "gone"', () {
    expect(
      TorrentStreamService.isTorrentGone(
        const TorrServerHttpException('Request to /torrents failed', 500, ''),
      ),
      isFalse,
    );
    expect(
      TorrentStreamService.isTorrentGone(
        const TorrServerHttpException('Request failed', 429, ''),
      ),
      isFalse,
    );
    expect(TorrentStreamService.isTorrentGone(StateError('boom')), isFalse);
    expect(TorrentStreamService.isTorrentGone('not an exception'), isFalse);
  });
}
