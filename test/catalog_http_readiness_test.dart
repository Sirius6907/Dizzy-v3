import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:dizzy/services/config/env_service.dart';
import 'package:dizzy/services/catalog/catalog_service.dart';
import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/net/dizzy_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'flutter/assets',
          (_) async => ByteData.sublistView(
            Uint8List.fromList(
              utf8.encode(
                'SUPABASE_URL=https://catalog-test.invalid\nSUPABASE_ANON_KEY=test-public-key',
              ),
            ),
          ),
        );
    await EnvService.initialize();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('public IMDb lookup works without initializing Supabase auth', () async {
    expect(CloudClient.isReady, isFalse);
    final net = DizzyNet.forTesting(
      transport: (method, uri, headers, body) async {
        expect(uri.queryParameters['tmdb'], '656908');
        expect(uri.queryParameters['type'], 'movie');
        return http.Response(
          '{"items":[{"id":656908,"imdb_id":"tt27988879"}]}',
          200,
        );
      },
    );
    expect(
      await CatalogService.fetchImdbId(
        tmdbId: '656908',
        type: 'movie',
        net: net,
      ),
      'tt27988879',
    );
    expect(CloudClient.isReady, isFalse);
  });

  test('public Home feed works without an anonymous session', () async {
    final net = DizzyNet.forTesting(
      transport: (method, uri, headers, body) async {
        expect(uri.queryParameters['region'], 'IN');
        return http.Response(
          '{"items":[{"id":656908,"title":"Ramayana"}]}',
          200,
        );
      },
    );
    final cards = await CatalogService.fetchFeed(net: net);
    expect(cards?.single.title, 'Ramayana');
    expect(CloudClient.isReady, isFalse);
  });
}
