/// F1 — One-Tap Instant Play.
///
/// The user-facing promise this file pins down:
///   1. the first valid source plays itself, with no server-picker step;
///   2. a dead source moves to the next one, quietly and in Easy English;
///   3. Data Saver caps auto quality at 720p, always;
///   4. weak/straining devices prefer H.264 and only fall back to AV1;
///   5. language tags pick the audio track (the Hindi-dub gate);
///   6. auto-skip is ON by default — and previews never auto-skip.
///
/// All six are pure decisions, so none of these tests touch the network,
/// mpv or SharedPreferences.
library;

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/player/audio_track_preference.dart';
import 'package:dizzy/services/player/auto_skip_policy.dart';
import 'package:dizzy/services/player/bandwidth_meter.dart';
import 'package:dizzy/services/player/quality_service.dart';
import 'package:dizzy/services/player/smart_quality_policy.dart';
import 'package:dizzy/services/stream/instant_play_gate.dart';
import 'package:dizzy/services/system/resource_governor.dart';
import 'package:dizzy/utils/perf/performance_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StreamSource src(String tag, {String? url}) => StreamSource(
    addonName: tag,
    title: tag,
    url: url ?? 'https://cdn.example.com/$tag.mp4',
  );

  group('F1 · race — first valid source wins, no picker gate', () {
    test('first playable source opens; every later one is ignored', () {
      final gate = InstantPlayGate(
        autoplayEnabled: () => true,
        autoFailover: () => true,
      );
      final first = src('a');
      expect(gate.offer(first), InstantPlayDecision.playNow);
      expect(gate.hasPlayed, isTrue);

      // A later, equally-valid source must NOT interrupt playback.
      expect(gate.offer(src('b')), InstantPlayDecision.ignore);
      expect(gate.offer(src('c')), InstantPlayDecision.ignore);
    });

    test('unplayable entries never win the race', () {
      final gate = InstantPlayGate(
        autoplayEnabled: () => true,
        autoFailover: () => true,
      );
      // A listing row with neither URL nor infoHash is not a video.
      final empty = StreamSource(addonName: 'meta', title: 'no link here');
      expect(InstantPlayGate.isValidCandidate(empty), isFalse);
      expect(gate.offer(empty), InstantPlayDecision.ignore);
      expect(gate.hasPlayed, isFalse);

      // …and the first real source still wins right after.
      expect(gate.offer(src('real')), InstantPlayDecision.playNow);
    });

    test('autoplay disabled ⇒ nothing auto-opens', () {
      final gate = InstantPlayGate(
        autoplayEnabled: () => false,
        autoFailover: () => true,
      );
      expect(gate.offer(src('a')), InstantPlayDecision.ignore);
      expect(gate.hasPlayed, isFalse);
    });

    test('a magnet/torrent source counts as playable', () {
      final torrent = StreamSource(
        addonName: 't',
        title: 't',
        infoHash: 'abc123',
      );
      expect(InstantPlayGate.isValidCandidate(torrent), isTrue);
      expect(torrent.magnetUrl, contains('magnet:'));
    });
  });

  group('F1 · failover — dead source advances, quietly', () {
    test('a dead source moves to the next-ranked one', () {
      final gate = InstantPlayGate(
        autoplayEnabled: () => true,
        autoFailover: () => true,
      );
      final primary = src('primary');
      final backup = src('backup');
      final spare = src('spare');
      gate.offer(primary);

      final next = gate.advance(chain: [backup, spare], failed: primary);
      expect(next, same(backup));
      expect(gate.switches, 1);
      expect(gate.isDead(primary), isTrue);
    });

    test('never re-tries a source that already died', () {
      final gate = InstantPlayGate(
        autoplayEnabled: () => true,
        autoFailover: () => true,
      );
      final a = src('a');
      final b = src('b');
      gate.offer(a);

      expect(gate.advance(chain: [b], failed: a), same(b));
      // `b` dies too — the chain must not hand `b` back.
      expect(gate.advance(chain: [b], failed: b), isNull);
    });

    test('exhausted chain and switch cap both hand over to the picker', () {
      final gate = InstantPlayGate(
        autoplayEnabled: () => true,
        autoFailover: () => true,
        maxSwitches: 1,
      );
      final a = src('a');
      final b = src('b');
      gate.offer(a);
      expect(gate.advance(chain: [b], failed: a), same(b));

      // Cap of 1 is spent → the user decides, no more silent switching.
      expect(gate.advance(chain: [src('c')], failed: b), isNull);
      expect(gate.switches, 1);
    });

    test('autoFailover off ⇒ the picker takes over immediately', () {
      final gate = InstantPlayGate(
        autoplayEnabled: () => true,
        autoFailover: () => false,
      );
      final a = src('a');
      gate.offer(a);
      expect(gate.advance(chain: [src('b')], failed: a), isNull);
    });

    test('the user-facing line is Easy English, no tech words', () {
      expect(kTryingNextSourceMessage, 'Trying next source…');
      for (final banned in ['http', 'mp4', 'magnet', 'mpv', '404', 'codec']) {
        expect(
          kTryingNextSourceMessage.toLowerCase().contains(banned),
          isFalse,
          reason: '"$banned" must never reach the user',
        );
      }
    });

    test('reset() forgets dead sources for a fresh episode', () {
      final gate = InstantPlayGate(
        autoplayEnabled: () => true,
        autoFailover: () => true,
      );
      final a = src('a');
      final b = src('b');
      gate.offer(a);
      gate.advance(chain: [b], failed: a);
      expect(gate.deadFingerprints, isNotEmpty);

      gate.reset();
      expect(gate.deadFingerprints, isEmpty);
      expect(gate.switches, 0);
      expect(gate.hasPlayed, isFalse);
    });
  });

  group('F1 · smart quality — Data Saver caps auto at 720p', () {
    test('Data Saver clamps 1080p/4K targets down to 720p', () {
      expect(
        SmartQualityPolicy.applyDataSaverCeiling(
          QualityChoice.q1080,
          dataSaver: true,
        ),
        QualityChoice.q720,
      );
      expect(
        SmartQualityPolicy.applyDataSaverCeiling(
          QualityChoice.q2160,
          dataSaver: true,
        ),
        QualityChoice.q720,
      );
      // 480p/720p are already under the ceiling and stay put.
      expect(
        SmartQualityPolicy.applyDataSaverCeiling(
          QualityChoice.q480,
          dataSaver: true,
        ),
        QualityChoice.q480,
      );
    });

    test('without Data Saver the ceiling never applies', () {
      for (final q in QualityChoice.values) {
        expect(
          SmartQualityPolicy.applyDataSaverCeiling(q, dataSaver: false),
          q,
        );
      }
    });

    test('auto ladder applies the ceiling on a fast link', () {
      expect(
        SmartQualityPolicy.autoLadderStep(
          bandwidthTarget: QualityChoice.q2160,
          dataSaver: true,
        ),
        QualityChoice.q720,
      );
      // A thin bandwidth window (null) keeps the current rung — no flip-flop.
      expect(
        SmartQualityPolicy.autoLadderStep(
          bandwidthTarget: null,
          dataSaver: false,
        ),
        isNull,
      );
    });

    test('Data Saver also holds on a real measured window', () {
      final m = BandwidthMeter();
      var buffered = 20.0;
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 12; i++) {
        buffered += 4.0;
        m.addSample(
          at: t0.add(Duration(seconds: i)),
          bufferedAheadSec: buffered,
          assumedBitrateBps: 6000000,
        );
      }
      expect(m.isStable, isTrue);
      final step = SmartQualityPolicy.autoLadderStep(
        bandwidthTarget: m.stableTarget(dataSaver: false),
        dataSaver: true,
      );
      expect(step, QualityChoice.q720);
    });
  });

  group('F1 · weak device prefers H.264, AV1 only as fallback', () {
    StreamSource av1(String badge) => StreamSource(
      addonName: 'a',
      title: 'Show $badge AV1',
      url: 'https://cdn/x.mp4',
    );
    StreamSource h264(String badge) => StreamSource(
      addonName: 'a',
      title: 'Show $badge x264',
      url: 'https://cdn/x.mp4',
    );

    test('budget device / low-RAM / low-end mode all read as strained', () {
      DeviceCapability cap({
        bool lowEnd = false,
        DeviceTier tier = DeviceTier.flagship,
        bool lowRam = false,
        ResourceLevel level = ResourceLevel.normal,
      }) => SmartQualityPolicy.capability(
        lowEndDeviceMode: lowEnd,
        deviceTier: tier,
        lowRamDevice: lowRam,
        resourceLevel: level,
      );

      expect(cap(), DeviceCapability.strong);
      expect(cap(tier: DeviceTier.budget), DeviceCapability.strained);
      expect(cap(lowRam: true), DeviceCapability.strained);
      expect(cap(lowEnd: true), DeviceCapability.strained);
      expect(cap(level: ResourceLevel.caution), DeviceCapability.strained);
      expect(cap(level: ResourceLevel.critical), DeviceCapability.strained);
      // mid-tier desktop-class devices are NOT penalised.
      expect(cap(tier: DeviceTier.midTier), DeviceCapability.strong);
    });

    test('strained device skips the AV1 file when an H.264 twin exists', () {
      final chosen = SmartQualityPolicy.pickProgressive(
        ranked: [av1('1080p'), h264('1080p')],
        choice: QualityChoice.q1080,
        capability: DeviceCapability.strained,
      );
      expect(chosen, isNotNull);
      expect(chosen!.codec, isNot('AV1'));
    });

    test('AV1 is still used as a last resort (a picture that plays)', () {
      final onlyAv1 = SmartQualityPolicy.pickProgressive(
        ranked: [av1('1080p')],
        choice: QualityChoice.q1080,
        capability: DeviceCapability.strained,
      );
      expect(onlyAv1, isNotNull);
      expect(onlyAv1!.codec, 'AV1');
    });

    test('a strong device takes the AV1 file without dodging', () {
      final chosen = SmartQualityPolicy.pickProgressive(
        ranked: [av1('1080p'), h264('1080p')],
        choice: QualityChoice.q1080,
        capability: DeviceCapability.strong,
      );
      expect(chosen!.codec, 'AV1');
    });

    test('Auto never forces a progressive reopen', () {
      expect(
        SmartQualityPolicy.pickProgressive(
          ranked: [av1('1080p')],
          choice: QualityChoice.auto,
          capability: DeviceCapability.strained,
        ),
        isNull,
      );
    });
  });

  group('F1 · audio gate — language tags pick the track', () {
    AudioTrackOption t(int i, {String? lang, String? title}) =>
        AudioTrackOption(index: i, language: lang, title: title);

    test('Hindi mode picks the Hindi track even when English is first', () {
      final picked = AudioTrackPreference.pick(
        tracks: [
          t(1, lang: 'eng', title: 'English'),
          t(2, lang: 'hin', title: 'Hindi'),
        ],
        hindi: true,
      );
      expect(picked, 2);
    });

    test('English mode picks the English track even when Hindi is first', () {
      final picked = AudioTrackPreference.pick(
        tracks: [
          t(1, lang: 'hin', title: 'Hindi'),
          t(2, lang: 'eng', title: 'English'),
        ],
        hindi: false,
      );
      expect(picked, 2);
    });

    test('region-suffixed tags still match (hin_IN / en-US)', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [
            t(1, lang: 'en-US'),
            t(2, lang: 'hin_IN'),
          ],
          hindi: true,
        ),
        2,
      );
      expect(
        AudioTrackPreference.pick(
          tracks: [
            t(1, lang: 'hin_IN'),
            t(2, lang: 'en-US'),
          ],
          hindi: false,
        ),
        2,
      );
    });

    test('falls back to the label when the container carries no tag', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [
            t(1, title: 'English 5.1'),
            t(2, title: 'Hindi Dub'),
          ],
          hindi: true,
        ),
        2,
      );
    });

    test('no match ⇒ null (never force a wrong-language track)', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [t(1, lang: 'jpn', title: 'Japanese')],
          hindi: true,
        ),
        isNull,
      );
      expect(AudioTrackPreference.pick(tracks: const [], hindi: true), isNull);
    });

    test('English mode does not claim unlabelled audio is English', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [
            t(1),
            t(2, lang: 'hin', title: 'Hindi'),
          ],
          hindi: false,
        ),
        isNull,
      );
    });

    test('Hindi mode falls back to an explicit English tag', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [t(1), t(2, lang: ' ENG_us ')],
          hindi: true,
        ),
        2,
      );
    });

    test('Hindi mode falls back to an explicit English label', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [t(1, lang: 'jpn'), t(2, title: 'English 5.1')],
          hindi: true,
        ),
        2,
      );
    });

    test('Hindi label takes precedence over an English tag', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [t(1, lang: 'eng'), t(2, title: 'Hindi Dub')],
          hindi: true,
        ),
        2,
      );
    });

    test('explicit Hindi tag takes precedence over a Hindi label', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [t(1, title: 'Hindi'), t(2, lang: ' HI-in ')],
          hindi: true,
        ),
        2,
      );
    });

    for (final tag in ['tam', 'te-IN', 'jpn', 'fr', 'eng']) {
      test('$tag tag overrides a misleading Hindi label', () {
        expect(
          AudioTrackPreference.pick(
            tracks: [
              t(1, lang: tag, title: 'Hindi Dub'),
              t(2, title: 'Hindi'),
              t(3, lang: 'eng'),
            ],
            hindi: true,
          ),
          2,
        );
      });
    }

    test('foreign tag cannot supply the English label fallback', () {
      for (final hindi in [true, false]) {
        expect(
          AudioTrackPreference.pick(
            tracks: [t(1, lang: 'tam', title: 'English')],
            hindi: hindi,
          ),
          isNull,
        );
      }
    });

    test('foreign Hindi label is skipped in favor of real English', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [
            t(1, lang: 'tel', title: 'Hindi'),
            t(2, lang: 'eng'),
          ],
          hindi: true,
        ),
        2,
      );
    });

    for (final tag in [null, '', 'und', 'unknown', 'mul']) {
      test('unspecified tag $tag permits an explicit Hindi label', () {
        expect(
          AudioTrackPreference.pick(
            tracks: [t(1, lang: 'eng'), t(2, lang: tag, title: 'Hindi')],
            hindi: true,
          ),
          2,
        );
      });
    }

    test('English fallback prefers a tag over a label', () {
      expect(
        AudioTrackPreference.pick(
          tracks: [t(1, title: 'English'), t(2, lang: 'eng')],
          hindi: true,
        ),
        2,
      );
    });

    for (final label in ['Hindi', 'HIN 5.1', '[hi] Dub']) {
      test('recognizes explicit Hindi label $label', () {
        expect(
          AudioTrackPreference.pick(
            tracks: [t(1, lang: 'eng'), t(2, title: label)],
            hindi: true,
          ),
          2,
        );
      });
    }

    for (final label in ['English', 'ENG 5.1', '[en] Dub']) {
      test('recognizes explicit English fallback label $label', () {
        expect(
          AudioTrackPreference.pick(
            tracks: [t(1), t(2, title: label)],
            hindi: true,
          ),
          2,
        );
      });
    }

    for (final label in [
      '',
      'Unknown',
      'Original audio',
      'Multi Audio',
      'Dual Audio',
      'Bollywood',
      'Hindipop',
      'Englishman',
      'Enhanced ending',
    ]) {
      test('$label is not an explicit track language', () {
        for (final hindi in [true, false]) {
          expect(
            AudioTrackPreference.pick(
              tracks: [t(1, title: label), t(2, lang: 'und')],
              hindi: hindi,
            ),
            isNull,
          );
        }
      });
    }
  });

  group('F1 · auto-skip is ON by default, previews never', () {
    bool auto(String type) => AutoSkipPolicy.shouldAutoSkip(
      type,
      autoSkipIntro: true,
      autoSkipRecap: true,
      autoSkipCredits: true,
    );

    test('intro / recap / credits all auto-skip when enabled', () {
      expect(auto('intro'), isTrue);
      expect(auto('recap'), isTrue);
      expect(auto('credits'), isTrue);
      // Case and padding from providers must not matter.
      expect(auto('  Intro '), isTrue);
      expect(auto('CREDITS'), isTrue);
    });

    test('preview NEVER auto-skips, whatever the toggles say', () {
      expect(auto('preview'), isFalse);
      expect(
        AutoSkipPolicy.shouldAutoSkip(
          'preview',
          autoSkipIntro: true,
          autoSkipRecap: true,
          autoSkipCredits: true,
        ),
        isFalse,
      );
    });

    test('an unknown type is never auto-skipped (no free pass to yank)', () {
      expect(auto('trailer'), isFalse);
      expect(auto(''), isFalse);
      expect(auto('PREVIEW'), isFalse);
    });

    test('turning a toggle off restores the manual skip button', () {
      expect(
        AutoSkipPolicy.shouldAutoSkip(
          'intro',
          autoSkipIntro: false,
          autoSkipRecap: true,
          autoSkipCredits: true,
        ),
        isFalse,
      );
      // …and only for that type.
      expect(
        AutoSkipPolicy.shouldAutoSkip(
          'recap',
          autoSkipIntro: false,
          autoSkipRecap: true,
          autoSkipCredits: true,
        ),
        isTrue,
      );
    });
  });
}
