import 'dart:io';

import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/media/artwork_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Phase K1b — the lock screen can only show a cover that lives on disk,
/// so this service mirrors a track's remote artwork into the app cache.
///
/// What matters: it happens once per track (the media watcher ticks every
/// second), a miss is remembered (no endless retries while offline), and a
/// broken cover never throws into playback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ArtworkCacheService.instance;
  late Directory temp;
  var fetches = 0;
  var status = 200;
  var body = <int>[0xFF, 0xD8, 0xFF, 0xE0];
  String? contentType = 'image/jpeg';

  MusicTrack song({
    String id = 'track-1',
    String cover = 'https://cdn.example/cover.jpg',
  }) => MusicTrack(
    id: id,
    title: 'Neon Skyline',
    artist: 'Kite Runner',
    album: 'Night Drive',
    coverUrl: cover,
    durationSeconds: 240,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dizzy_art_');
    fetches = 0;
    status = 200;
    body = <int>[0xFF, 0xD8, 0xFF, 0xE0];
    contentType = 'image/jpeg';
    service.debugReset();
    service.debugDirectoryOverride = temp;
    service.debugFetch = (uri) async {
      fetches++;
      return http.Response.bytes(
        body,
        status,
        headers: contentType == null ? const {} : {'content-type': contentType!},
      );
    };
  });

  tearDown(() async {
    service.debugReset();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('downloads a cover once, then reuses the cached file', () async {
    final first = await service.localPathFor(song());
    expect(first, isNotNull);
    expect(await File(first!).exists(), isTrue);
    expect(first.endsWith('.jpg'), isTrue);

    final again = await service.localPathFor(song());
    expect(again, first);
    expect(fetches, 1, reason: 'one second ticks must not re-download');
  });

  test('a cover already on disk survives a restart without the network', () async {
    final first = await service.localPathFor(song());
    expect(first, isNotNull);

    // Simulates a fresh app launch: memory is empty, the file is not.
    service.debugReset();
    service.debugDirectoryOverride = temp;
    var networkCalls = 0;
    service.debugFetch = (_) async {
      networkCalls++;
      throw const SocketException('offline');
    };

    expect(await service.localPathFor(song()), first);
    expect(networkCalls, 0);
  });

  test('a track without a cover never touches the network', () async {
    expect(await service.localPathFor(song(cover: '   ')), isNull);
    expect(fetches, 0);
  });

  test('a failed download is remembered instead of retried forever', () async {
    status = 404;

    expect(await service.localPathFor(song()), isNull);
    expect(await service.localPathFor(song()), isNull);
    expect(fetches, 1);
  });

  test('a network error is swallowed and leaves the notification plain', () async {
    service.debugFetch = (_) async => throw const SocketException('offline');

    expect(await service.localPathFor(song()), isNull);
    expect(await service.localPathFor(song()), isNull);
  });

  test('different covers get different files', () async {
    final a = await service.localPathFor(song(cover: 'https://cdn/a.jpg'));
    final b = await service.localPathFor(
      song(id: 'track-2', cover: 'https://cdn/b.jpg'),
    );

    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(a, isNot(b));
    expect(fetches, 2);
  });

  test('a png content type keeps the right extension', () async {
    contentType = 'image/png';
    body = <int>[0x89, 0x50, 0x4E, 0x47];

    final path = await service.localPathFor(song());
    expect(path, isNotNull);
    expect(path!.endsWith('.png'), isTrue);
  });
}
