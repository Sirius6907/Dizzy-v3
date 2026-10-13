import 'package:dizzy/services/errors/app_error_log.dart';
import 'package:dizzy/services/errors/session_trail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => SessionTrail.resetForTest());

  group('v1.3.3-T2.3 session trail', () {
    test('records enum tokens and keeps insertion order', () {
      expect(SessionTrail.record('nav_home'), isTrue);
      expect(SessionTrail.record('play_start'), isTrue);
      expect(SessionTrail.events, ['nav_home', 'play_start']);
      expect(SessionTrail.wire(), 'nav_home>play_start');
    });

    test('rejects free text and stays clean', () {
      expect(SessionTrail.record('Dune Part Two'), isFalse);
      expect(SessionTrail.record('https://cdn.example/x.m3u8'), isFalse);
      expect(SessionTrail.record('Error: no element'), isFalse);
      expect(SessionTrail.events, isEmpty);
    });

    test('ring buffer drops oldest past capacity', () {
      for (var i = 0; i < SessionTrail.capacity + 5; i++) {
        SessionTrail.record('nav_p$i');
      }
      expect(SessionTrail.events.length, SessionTrail.capacity);
      expect(SessionTrail.events.first, 'nav_p5');
      expect(SessionTrail.events.last, 'nav_p${SessionTrail.capacity + 4}');
    });

    test('wire() trims oldest tokens to fit the budget', () {
      for (var i = 0; i < SessionTrail.capacity; i++) {
        SessionTrail.record('navigate_to_screen_number_$i');
      }
      final w = SessionTrail.wire();
      expect(w.length, lessThanOrEqualTo(SessionTrail.maxWireLength));
      // Newest token survives the trim.
      expect(w.endsWith('navigate_to_screen_number_19'), isTrue);
    });

    test('reset clears the trail', () {
      SessionTrail.record('nav_home');
      SessionTrail.reset();
      expect(SessionTrail.events, isEmpty);
      expect(SessionTrail.wire(), isEmpty);
    });

    test('route names map to fixed enum tokens only', () {
      expect(SessionTrail.navTokenFor('/home'), 'nav_home');
      expect(SessionTrail.navTokenFor('/settings/appearance'), 'nav_settings');
      expect(SessionTrail.navTokenFor('PlayerScreen'), 'nav_player');
      expect(SessionTrail.navTokenFor('/dune-part-two'), 'nav_other');
      expect(SessionTrail.navTokenFor(null), 'nav_unknown');
      // A hostile route name can never reach the wire as free text.
      final t = SessionTrail.navTokenFor('/q?title=Dune Part Two');
      expect(SessionTrail.sanitizeToken(t), t);
      expect(t, 'nav_other');
    });
  });

  group('trail privacy gate in the error payload', () {
    test('valid trail rides along', () {
      final p = AppErrorLog.buildPayload(
        deviceCode: '1234567',
        platform: 'android',
        appVersion: '1.3.3',
        screen: 'player',
        code: 'e_play_open',
        trail: 'nav_home>play_start',
      );
      expect(p['trail'], 'nav_home>play_start');
    });

    test('one bad token voids the whole trail', () {
      final p = AppErrorLog.buildPayload(
        deviceCode: '1234567',
        platform: 'android',
        appVersion: '1.3.3',
        screen: 'player',
        code: 'e_play_open',
        trail: 'nav_home>Dune Part Two>play_start',
      );
      expect(p.containsKey('trail'), isFalse);
    });

    test('empty trail is omitted entirely', () {
      final p = AppErrorLog.buildPayload(
        deviceCode: '1234567',
        platform: 'android',
        appVersion: '1.3.3',
        screen: 'player',
        code: 'e_play_open',
      );
      expect(p.containsKey('trail'), isFalse);
    });
  });
}