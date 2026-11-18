import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/models/continue_watching/continue_watching_item.dart';
import 'package:dizzy/models/movie/movie_detail.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/adult/adult_directory.dart';
import 'package:dizzy/services/adult/adult_log.dart';
import 'package:dizzy/services/adult/adult_media.dart';
import 'package:dizzy/services/continue_watching/continue_watching_service.dart';

void main() {
  group('AdultMedia.isAdultAddonName', () {
    test('flags every curated 18+ addon name', () {
      for (final e in AdultDirectory.entries) {
        expect(
          AdultMedia.isAdultAddonName(e.name),
          isTrue,
          reason: '${e.name} must be recognised as adult',
        );
      }
    });

    test('flags the anime extractor stream names', () {
      expect(AdultMedia.isAdultAddonName('Hentaini'), isTrue);
      expect(AdultMedia.isAdultAddonName('WatchHentai'), isTrue);
    });

    test('leaves normal addons alone', () {
      for (final name in [
        'Torrentio',
        'Cinemeta',
        'flystream',
        'Netflix',
        'ArabicAnime',
        'MegaPlay',
        '',
      ]) {
        expect(
          AdultMedia.isAdultAddonName(name),
          isFalse,
          reason: '$name is not adult',
        );
      }
      expect(AdultMedia.isAdultAddonName(null), isFalse);
    });
  });

  group('AdultMedia.isAdultMediaId', () {
    test('flags the 18+ addon id prefixes', () {
      expect(AdultMedia.isAdultMediaId('asa:12345'), isTrue);
      expect(AdultMedia.isAdultMediaId('TPB:9'), isTrue);
    });

    test('leaves IMDb / TMDB ids alone', () {
      expect(AdultMedia.isAdultMediaId('tt0111161'), isFalse);
      expect(AdultMedia.isAdultMediaId('tmdb:278'), isFalse);
      expect(AdultMedia.isAdultMediaId(''), isFalse);
      expect(AdultMedia.isAdultMediaId(null), isFalse);
    });
  });

  group('AdultMedia.isAdultType', () {
    test('flags adult-only content types', () {
      for (final t in ['porn', 'AdultVideo', 'XXX', 'adult']) {
        expect(AdultMedia.isAdultType(t), isTrue, reason: t);
      }
    });

    test('leaves normal types alone', () {
      for (final t in ['movie', 'series', 'anime', 'tv', '', 'channel']) {
        expect(AdultMedia.isAdultType(t), isFalse, reason: t);
      }
    });
  });

  group('AdultMedia.isAdultUrl', () {
    test('flags every curated directory host', () {
      for (final e in AdultDirectory.entries) {
        expect(
          AdultMedia.isAdultUrl(e.manifestUrl),
          isTrue,
          reason: '${e.manifestUrl} must be an adult host',
        );
      }
    });

    test('flags sub-domains of a curated root', () {
      expect(AdultMedia.isAdultUrl('https://cdn.stravo.site/hls/x.m3u8'), isTrue);
    });

    test('shared baby-beamup host is only adult on the jaxxx path', () {
      expect(
        AdultMedia.isAdultUrl(
          'https://07b88951aaab-jaxxx-v2.baby-beamup.club/manifest.json',
        ),
        isTrue,
      );
      expect(
        AdultMedia.isAdultUrl(
          'https://someone-elses-addon.baby-beamup.club/manifest.json',
        ),
        isFalse,
      );
    });

    test('leaves normal stream hosts alone', () {
      expect(
        AdultMedia.isAdultUrl('https://cdn.flystream.site/master.m3u8'),
        isFalse,
      );
      expect(AdultMedia.isAdultUrl('https://example.com/video.mp4'), isFalse);
      expect(AdultMedia.isAdultUrl(''), isFalse);
      expect(AdultMedia.isAdultUrl(null), isFalse);
    });
  });

  group('AdultMedia.isAdult', () {
    test('any single signal is enough', () {
      expect(AdultMedia.isAdult(addonName: 'TPB 4K Porn'), isTrue);
      expect(AdultMedia.isAdult(mediaId: 'asa:1'), isTrue);
      expect(AdultMedia.isAdult(type: 'xxx'), isTrue);
      expect(
        AdultMedia.isAdult(urls: ['https://asa.00696900.xyz/stream/1']),
        isTrue,
      );
    });

    test('a clean title on a clean addon is not adult', () {
      expect(
        AdultMedia.isAdult(
          addonName: 'Torrentio',
          mediaId: 'tt0137523',
          type: 'movie',
          urls: ['https://cdn.flystream.site/master.m3u8'],
        ),
        isFalse,
      );
    });

    test('titles are never inspected (no fuzzy matching)', () {
      expect(
        AdultMedia.isAdult(
          addonName: 'Cinemeta',
          mediaId: 'tt1234567',
          type: 'movie',
        ),
        isFalse,
        reason: 'the title is not even a parameter — by design',
      );
    });
  });

  group('AdultLog', () {
    test('keeps scheme and host, drops path and query', () {
      expect(
        AdultLog.redactUrl('https://asa.00696900.xyz/series/stepmom-3?t=abc'),
        'https://asa.00696900.xyz/…',
      );
    });

    test('handles empty and hostless values', () {
      expect(AdultLog.redactUrl(''), '<empty>');
      expect(AdultLog.redactUrl(null), '<empty>');
      expect(AdultLog.redactUrl('/local/path'), '<hidden>');
    });

    test('errors print their type only', () {
      final e = StateError('https://asa.00696900.xyz/secret');
      expect(AdultLog.redactError(e), contains('StateError'));
      expect(AdultLog.redactError(e), isNot(contains('secret')));
    });
  });

  group('ContinueWatchingService adult guard', () {
    MovieDetail detail({String id = 'tt0137523', String type = 'movie'}) =>
        MovieDetail(id: id, type: type, name: 'Fight Club');

    test('adult addon name blocks Continue Watching', () {
      final source = StreamSource(
        name: 'TPB 4K',
        addonName: 'TPB 4K Porn',
        url: 'https://tpb-adult-addon.click/stream/1',
      );
      expect(
        ContinueWatchingService.isAdultPlayback(detail(), source),
        isTrue,
      );
    });

    test('adult stream host blocks even with a clean addon name', () {
      final source = StreamSource(
        name: 'Direct',
        addonName: 'DirectHTTP',
        url: 'https://midnight.stravo.site/local/stream/1',
      );
      expect(
        ContinueWatchingService.isAdultPlayback(detail(), source),
        isTrue,
      );
    });

    test('adult id / type blocks', () {
      final source = StreamSource(
        name: 'Direct',
        addonName: 'DirectHTTP',
        url: 'https://example.com/v.mp4',
      );
      expect(
        ContinueWatchingService.isAdultPlayback(
          detail(id: 'asa:42', type: 'porn'),
          source,
        ),
        isTrue,
      );
    });

    test('normal playback is allowed', () {
      final source = StreamSource(
        name: 'Torrentio 1080p',
        addonName: 'Torrentio',
        url: 'https://cdn.flystream.site/master.m3u8',
      );
      expect(
        ContinueWatchingService.isAdultPlayback(detail(), source),
        isFalse,
      );
    });

    test('persisted adult rows are recognised for the startup purge', () {
      final adult = ContinueWatchingItem(
        id: 'tt9999999',
        title: 'Something',
        type: 'movie',
        positionSeconds: 600,
        totalDurationSeconds: 3600,
        lastWatchedAt: DateTime.now(),
        isTorrent: false,
        addonName: 'Stravo',
      );
      final clean = ContinueWatchingItem(
        id: 'tt0137523',
        title: 'Fight Club',
        type: 'movie',
        positionSeconds: 600,
        totalDurationSeconds: 3600,
        lastWatchedAt: DateTime.now(),
        isTorrent: false,
        addonName: 'Torrentio',
      );
      expect(ContinueWatchingService.isAdultItem(adult), isTrue);
      expect(ContinueWatchingService.isAdultItem(clean), isFalse);
    });
  });
}
