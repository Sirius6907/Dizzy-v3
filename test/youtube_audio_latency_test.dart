import 'dart:async';
import 'dart:convert';

import 'package:dizzy/services/music/youtube_audio_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a playable first client is returned without waiting on slower clients',
    () async {
      final blockedClient = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path == '/watch') {
          return http.Response('"INNERTUBE_API_KEY":"test-key"', 200);
        }
        if (request.url.path == '/youtubei/v1/player') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final context = body['context']['client']['clientName'];
          if (context != 'VISIONOS') return blockedClient.future;
          return http.Response(
            jsonEncode({
              'playabilityStatus': {'status': 'OK'},
              'streamingData': {
                'adaptiveFormats': [
                  {
                    'itag': 140,
                    'url': 'https://rr1---test.googlevideo.com/playable.m4a',
                    'mimeType': 'audio/mp4',
                    'bitrate': 128000,
                    'audioSampleRate': '44100',
                  },
                ],
              },
            }),
            200,
          );
        }
        return http.Response(
          'audio',
          206,
          headers: {'content-type': 'audio/mp4'},
        );
      });
      final extractor = YoutubeAudioExtractor(client: client);
      try {
        final result = await extractor
            .getAudioUrl('test-video')
            .timeout(const Duration(seconds: 1));
        expect(result?.url, 'https://rr1---test.googlevideo.com/playable.m4a');
      } finally {
        blockedClient.complete(http.Response('{}', 200));
        client.close();
      }
    },
  );

  test(
    'an unreachable first client falls back without waiting on later clients',
    () async {
      final blockedClient = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path == '/watch') {
          return http.Response('"INNERTUBE_API_KEY":"test-key"', 200);
        }
        if (request.url.path == '/youtubei/v1/player') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final context = body['context']['client']['clientName'];
          if (context == 'IOS') return blockedClient.future;
          final name = context == 'VISIONOS' ? 'rejected' : 'working';
          return http.Response(
            jsonEncode({
              'playabilityStatus': {'status': 'OK'},
              'streamingData': {
                'adaptiveFormats': [
                  {
                    'itag': 140,
                    'url': 'https://rr1---test.googlevideo.com/$name.m4a',
                    'mimeType': 'audio/mp4',
                    'bitrate': 128000,
                    'audioSampleRate': '44100',
                  },
                ],
              },
            }),
            200,
          );
        }
        return http.Response(
          '',
          request.url.path == '/rejected.m4a' ? 403 : 206,
        );
      });
      final extractor = YoutubeAudioExtractor(client: client);
      try {
        final result = await extractor
            .getAudioUrl('test-video')
            .timeout(const Duration(seconds: 1));
        expect(result?.url, 'https://rr1---test.googlevideo.com/working.m4a');
      } finally {
        blockedClient.complete(http.Response('{}', 200));
        client.close();
      }
    },
  );
}
