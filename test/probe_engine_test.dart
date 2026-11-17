/// Pure-logic tests for the source probe.
///
/// The probe reads TMDB payloads, classifies what a scraper returned and builds
/// the exact open plan handed to mpv. Those three decisions decide whether a
/// "does not play" report is about the scraper or about the player, so they are
/// pinned here — no network, no window, no tokens.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/player/player_settings.dart';

import '../tool/player_probe/probe_engine.dart';

StreamSource _source({
  String? url,
  String? title,
  String? externalUrl,
  String? infoHash,
  Map<String, dynamic>? behaviorHints,
  Map<String, String>? headers,
}) {
  return StreamSource(
    addonName: 'probe-test',
    url: url,
    title: title,
    externalUrl: externalUrl,
    infoHash: infoHash,
    behaviorHints: behaviorHints,
    headers: headers,
  );
}

void main() {
  group('ProbeMetadata.fromTmdbDetail', () {
    test('reads movie title, release year and imdb id', () {
      final meta = ProbeMetadata.fromTmdbDetail(
        {
          'title': 'Fight Club',
          'release_date': '1999-10-15',
          'imdb_id': 'tt0137523',
        },
        ProbeKind.movie,
      );

      expect(meta, isNotNull);
      expect(meta!.title, 'Fight Club');
      expect(meta.year, 1999);
      expect(meta.imdbId, 'tt0137523');
      expect(meta.scrapeType, 'movie');
    });

    test('reads series name and first air date', () {
      final meta = ProbeMetadata.fromTmdbDetail(
        {
          'name': 'Game of Thrones',
          'first_air_date': '2011-04-17',
          'original_name': 'Game of Thrones',
        },
        ProbeKind.series,
      );

      expect(meta, isNotNull);
      expect(meta!.title, 'Game of Thrones');
      expect(meta.year, 2011);
      expect(meta.scrapeType, 'series');
    });

    test('prefers an explicit imdb id over the payload field', () {
      final meta = ProbeMetadata.fromTmdbDetail(
        {
          'title': 'Fight Club',
          'release_date': '1999-10-15',
          'imdb_id': 'tt0137523',
        },
        ProbeKind.movie,
        imdbId: 'tt9999999',
      );

      expect(meta!.imdbId, 'tt9999999');
    });

    test('drops a non-imdb id instead of passing it to scrapers', () {
      final meta = ProbeMetadata.fromTmdbDetail(
        {'title': 'Fight Club', 'imdb_id': '0137523'},
        ProbeKind.movie,
      );

      expect(meta!.imdbId, isNull);
    });

    test('returns null when the payload has no usable title', () {
      expect(ProbeMetadata.fromTmdbDetail(null, ProbeKind.movie), isNull);
      expect(
        ProbeMetadata.fromTmdbDetail({'title': '   '}, ProbeKind.movie),
        isNull,
      );
      // A series payload must not fall back to the movie title field.
      expect(
        ProbeMetadata.fromTmdbDetail({'title': 'Only Movies'}, ProbeKind.series),
        isNull,
      );
    });
  });

  group('classifySource', () {
    test('HLS / DASH / progressive', () {
      expect(
        classifySource(_source(url: 'https://cdn.test/master.m3u8?t=1')),
        SourceShape.hls,
      );
      expect(
        classifySource(_source(url: 'https://cdn.test/manifest.mpd')),
        SourceShape.dash,
      );
      expect(
        classifySource(_source(url: 'https://cdn.test/movie.1080p.mkv')),
        SourceShape.progressive,
      );
    });

    test('embed = embed hint or external page without a media url', () {
      expect(
        classifySource(
          _source(
            url: 'https://provider.test/embed/1',
            behaviorHints: {'dizzyEmbed': true},
          ),
        ),
        SourceShape.embed,
      );
      expect(
        classifySource(_source(externalUrl: 'https://provider.test/watch/1')),
        SourceShape.embed,
      );
    });

    test('torrent = info hash or magnet link', () {
      expect(
        classifySource(
          _source(url: 'https://torrserver.test/stream?link=abc', infoHash: 'abc'),
        ),
        SourceShape.torrent,
      );
      expect(
        classifySource(_source(url: 'magnet:?xt=urn:btih:abc')),
        SourceShape.torrent,
      );
    });

    test('empty url is unknown, not playable-by-accident', () {
      expect(classifySource(_source()), SourceShape.unknown);
    });

    test('only embeds and torrents are excluded from mpv', () {
      expect(SourceShape.hls.opensInMpv, isTrue);
      expect(SourceShape.dash.opensInMpv, isTrue);
      expect(SourceShape.progressive.opensInMpv, isTrue);
      expect(SourceShape.embed.opensInMpv, isFalse);
      expect(SourceShape.torrent.opensInMpv, isFalse);
    });
  });

  group('buildOpenPlan', () {
    test('sanitises :: so mpv does not read it as a protocol prefix', () {
      final plan = buildOpenPlan(
        _source(url: 'https://cdn.test/x::y/index.m3u8'),
      );

      expect(plan.url, contains('%3A%3A'));
      expect(plan.url, isNot(contains('::')));
    });

    test('applies the same CDN headers the app applies', () {
      final plan = buildOpenPlan(
        _source(url: 'https://valhallastream.test/hls/master.m3u8'),
      );
      final expected = PlayerSettings.resolveStreamHeaders(
        'https://valhallastream.test/hls/master.m3u8',
      );

      expect(plan.headers, isNotNull);
      expect(plan.headers!['Referer'], 'https://www.rivestream.app/');
      expect(plan.headers!['User-Agent'], expected['User-Agent']);
    });

    test('merges proxyHeaders.request over the resolved headers', () {
      final plan = buildOpenPlan(
        _source(
          url: 'https://cdn.test/index.m3u8',
          behaviorHints: {
            'proxyHeaders': {
              'request': {'X-Proxy': 'yes', 'Referer': 'https://proxy.test/'},
            },
          },
        ),
      );

      expect(plan.headers!['X-Proxy'], 'yes');
      expect(plan.headers!['Referer'], 'https://proxy.test/');
    });

    test('flags live sources without flags inflating normal VOD', () {
      final live = buildOpenPlan(
        _source(
          url: 'https://cdn.test/index.m3u8',
          behaviorHints: {'isLive': true},
        ),
      );
      final vod = buildOpenPlan(_source(url: 'https://cdn.test/index.m3u8'));

      expect(live.isLive, isTrue);
      expect(vod.isLive, isFalse);
      expect(vod.headers, isNotNull);
    });

    test('detects a TorrServer stream url', () {
      final plan = buildOpenPlan(
        _source(
          url: 'http://127.0.0.1:8090/stream?link=abc&index=0',
          infoHash: 'abc',
        ),
      );

      expect(plan.isTorrentStream, isTrue);
    });
  });

  group('ProbeRun', () {
    test('summary counts shapes so a run reads at a glance', () {
      final run = ProbeRun(
        scraperName: 'a111477',
        sources: [
          _source(url: 'https://cdn.test/a.m3u8'),
          _source(url: 'https://cdn.test/b.m3u8'),
          _source(url: 'https://cdn.test/c.mp4'),
          _source(externalUrl: 'https://provider.test/embed/1'),
        ],
        elapsed: const Duration(milliseconds: 1250),
      );

      expect(run.isEmpty, isFalse);
      expect(run.shapeCounts[SourceShape.hls], 2);
      expect(run.shapeCounts[SourceShape.progressive], 1);
      expect(run.shapeCounts[SourceShape.embed], 1);
      expect(run.summary, contains('a111477'));
      expect(run.summary, contains('1250ms'));
    });

    test('an empty run says 0 sources instead of looking like a player bug', () {
      final run = ProbeRun(
        scraperName: 'kisskh',
        sources: const [],
        elapsed: const Duration(milliseconds: 800),
      );

      expect(run.summary, contains('0 sources'));
    });

    test('an errored run keeps the error visible', () {
      final run = ProbeRun(
        scraperName: 'vidlink',
        sources: const [],
        elapsed: const Duration(seconds: 45),
        error: 'TimeoutException after 0:00:45.000000',
      );

      expect(run.summary, startsWith('vidlink: ERROR'));
    });
  });

  group('describeSource', () {
    test('labels shape, quality and title for the results table', () {
      final text = describeSource(
        _source(
          url: 'https://cdn.test/Fight.Club.1999.mkv',
          title: 'Fight Club 1080p',
        ),
      );

      expect(text, contains('MP4'));
      expect(text, contains('1080p'));
    });
  });
}
