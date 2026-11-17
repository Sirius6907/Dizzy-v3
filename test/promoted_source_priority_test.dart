import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/scraper/scraper_quarantine_service.dart';
import 'package:dizzy/services/stream/source_ranker.dart';
import 'package:dizzy/services/stream/stream_probe_race.dart';
import 'package:dizzy/services/stream/stream_relevance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The 2026-11-16 source-priority round.
///
/// The owner's own probe tool proved that RiveStream and FlaxMovies answer
/// with playable HLS, but the app showed NONE of them:
///   - `flaxmovies` was seeded into the quarantine baseline, so it was
///     skipped for 7 days on every fresh install.
///   - Both scrapers label a row with the CDN/provider name ("Rive -
///     Borealis", "FlaxMovies - Airflix"), never with the content title,
///     so `StreamRelevance` rejected every row as "wrong show".
///   - Nothing ordered the two providers above the other HTTP scrapers.
StreamSource _rive({String title = 'VisionQuest'}) => StreamSource(
  addonName: 'rivestream',
  name: '$title · Borealis · 1080p | Hindi',
  title: '$title · Borealis · 1080p | Hindi',
  description: 'Borealis • 1080p | Hindi • hls • 1.2 GB',
  url: 'https://dash-hls-bridge.example/?url=x',
);

StreamSource _flax({String title = 'VisionQuest'}) => StreamSource(
  addonName: 'flaxmovies',
  name: '$title · Airflix · 1080p',
  title: '$title · Airflix · 1080p',
  description: 'Multi-CDN Stream · 1080p',
  url: 'https://freakyniki.example/?tmdb_id=1',
);

StreamSource _other({String addon = 'lmscript', String name = 'Other 1080p'}) =>
    StreamSource(
      addonName: addon,
      name: name,
      title: name,
      url: 'https://cdn.example/stream.mkv',
    );

void main() {
  group('promoted providers survive the relevance filter', () {
    test('a RiveStream row labelled with the content title is relevant', () {
      expect(
        StreamRelevance.isRelevant(
          source: _rive(),
          title: 'VisionQuest',
          year: 2026,
        ),
        isTrue,
      );
    });

    test('a FlaxMovies row labelled with the content title is relevant', () {
      expect(
        StreamRelevance.isRelevant(
          source: _flax(),
          title: 'VisionQuest',
          year: 2026,
        ),
        isTrue,
      );
    });

    test('a row that names a different show is still rejected', () {
      final wrong = StreamSource(
        addonName: 'lmscript',
        name: 'Castlevania Nocturne 1080p',
        title: 'Castlevania Nocturne 1080p',
        url: 'https://cdn.example/other.mkv',
      );
      expect(
        StreamRelevance.isRelevant(
          source: wrong,
          title: 'VisionQuest',
          year: 2026,
        ),
        isFalse,
      );
    });
  });

  group('the promoted pair leads the source order', () {
    test('rivestream and flaxmovies are the promoted providers', () {
      expect(SourceRanker.promotedProviders, contains('rivestream'));
      expect(SourceRanker.promotedProviders, contains('flaxmovies'));
    });

    test('a promoted source outranks another HTTP source in the chain', () {
      final chain = SourceRanker.buildFailoverChain(
        [_other(), _rive(), _flax()],
        const RankerContext(),
      );
      expect(chain.first.addonName, 'rivestream');
      expect(chain[1].addonName, 'flaxmovies');
      expect(chain.last.addonName, 'lmscript');
    });

    test('tier: promoted < other http < embed < torrent', () {
      final embed = StreamSource(
        addonName: 'vidfast',
        name: 'Embed',
        url: 'https://vidfast.vc/tv/1/1/7',
        behaviorHints: {'dizzyEmbed': true},
      );
      final torrent = StreamSource(
        addonName: 'Torrentio',
        name: 'Torrent 1080p',
        infoHash: 'abc123',
      );
      expect(SourceRanker.tierOf(_rive()), lessThan(SourceRanker.tierOf(_other())));
      expect(SourceRanker.tierOf(_other()), lessThan(SourceRanker.tierOf(embed)));
      expect(SourceRanker.tierOf(embed), lessThan(SourceRanker.tierOf(torrent)));
    });

    test('the promoted pair still leads even when another source has history',
        () {
      final chain = SourceRanker.buildFailoverChain(
        [_other(), _rive()],
        const RankerContext(lastGoodByAddon: {'lmscript': 'x'}),
      );
      expect(chain.first.addonName, 'rivestream');
    });
  });

  group('the autoplay race prefers the promoted pair', () {
    test('a promoted source wins over an earlier alive non-promoted one', () async {
      final race = StreamProbeRace(
        isPromoted: (s) => SourceRanker.promotedProviders
            .contains(s.addonName.toLowerCase()),
        probeFn: (s) async {
          await Future.delayed(
            Duration(milliseconds: s.addonName == 'lmscript' ? 10 : 60),
          );
          return true;
        },
      );

      race.offer(_other());
      race.offer(_rive());

      final winner = await race.winner;
      expect(winner, isNotNull);
      expect(winner!.addonName, 'rivestream');
      race.close();
    });

    test('without a promoted source the fallback still wins', () async {
      final race = StreamProbeRace(
        isPromoted: (s) => SourceRanker.promotedProviders
            .contains(s.addonName.toLowerCase()),
        probeFn: (_) async => true,
      );

      race.offer(_other());

      final winner = await race.winner;
      expect(winner!.addonName, 'lmscript');
      race.close();
    });
  });

  group('quarantine must not silence a promoted provider', () {
    test('flaxmovies is not quarantined on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      await ScraperQuarantineService.initialize();
      expect(ScraperQuarantineService.isQuarantined('flaxmovies'), isFalse);
      expect(ScraperQuarantineService.isQuarantined('rivestream'), isFalse);
    });
  });
}
