import 'dart:convert';

import 'package:dizzy/services/support/support_agent_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// The bundled FAQ must answer common questions offline, and must NEVER
/// confidently answer the wrong one — a wrong answer is worse than "let me
/// pass this to a human".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<FaqEntry> entries;

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/support_kb/support_faq_v1.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    entries = (decoded['entries'] as List)
        .map((m) => FaqEntry.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
    SupportAgentService.seedForTest(entries, version: decoded['version'].toString());
  });

  group('bundled FAQ integrity', () {
    test('bundle parses with a usable number of entries', () {
      expect(entries.length, greaterThanOrEqualTo(20));
      for (final e in entries) {
        expect(e.id, isNotEmpty, reason: 'entry missing id');
        expect(e.triggers, isNotEmpty, reason: '${e.id} has no triggers');
        expect(e.answerEn, isNotEmpty, reason: '${e.id} has no English answer');
      }
    });

    test('every entry has a Hinglish answer too (audience is India-first)', () {
      final missing = entries.where((e) => (e.answerHi ?? '').isEmpty).map((e) => e.id);
      expect(missing, isEmpty, reason: 'missing hi answer: ${missing.join(', ')}');
    });

    test('ids are unique', () {
      final ids = entries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('local matching (tier 1)', () {
    test('exact-ish queries resolve to the right entry', () {
      expect(SupportAgentService.localMatch('video not playing')?.id, 'faq_play_not_working');
      expect(SupportAgentService.localMatch('buffering')?.id, 'faq_buffering');
      expect(SupportAgentService.localMatch('download stuck')?.id, 'faq_download_fails');
      expect(SupportAgentService.localMatch('hindi dub')?.id, 'faq_hindi_dub');
      expect(SupportAgentService.localMatch('otp not received')?.id, 'faq_otp_not_arriving');
    });

    test('Hinglish queries resolve to the same entries', () {
      expect(SupportAgentService.localMatch('video nahi chal raha')?.id, 'faq_play_not_working');
      expect(SupportAgentService.localMatch('gaana nahi chal raha')?.id, 'faq_music_no_play');
      expect(SupportAgentService.localMatch('awaaz nahi aa raha')?.id, 'faq_no_sound');
      expect(SupportAgentService.localMatch('naam badal gaya')?.id, 'faq_username_reset');
    });

    test('off-topic input returns null (routes to human, never guesses)', () {
      expect(SupportAgentService.localMatch('who won the 1996 world cup'), isNull);
      expect(SupportAgentService.localMatch(''), isNull);
      expect(SupportAgentService.localMatch('   '), isNull);
    });

    test('empty bundle degrades safely', () {
      SupportAgentService.seedForTest(const []);
      expect(SupportAgentService.localMatch('buffering'), isNull);
      expect(SupportAgentService.scoreAll('buffering'), isEmpty);
      SupportAgentService.seedForTest(entries);
    });
  });

  group('language detection', () {
    test('devanagari → hi', () {
      expect(SupportAgentService.detectLanguage('गाना नहीं चल रहा'), 'hi');
    });
    test('roman hinglish → hi', () {
      expect(SupportAgentService.detectLanguage('video nahi chal raha kya karu'), 'hi');
      expect(SupportAgentService.detectLanguage('gaana kaise chalaye'), 'hi');
    });
    test('plain english → en', () {
      expect(SupportAgentService.detectLanguage('the video will not play'), 'en');
      expect(SupportAgentService.detectLanguage('download is stuck'), 'en');
    });

    test('answer picks the matching language with English fallback', () {
      final e = entries.firstWhere((x) => x.id == 'faq_buffering');
      expect(SupportAgentService.answerFor(e, 'hi'), e.answerHi);
      expect(SupportAgentService.answerFor(e, 'en'), e.answerEn);
      // Unknown language never yields an empty string.
      expect(SupportAgentService.answerFor(e, 'xx'), isNotEmpty);
    });
  });

  group('scoring shape', () {
    test('an exact trigger phrase outranks scattered common words', () {
      final tokens = SupportAgentService.tokenize('video not playing');
      final exact = entries.firstWhere((e) => e.id == 'faq_play_not_working');
      final other = entries.firstWhere((e) => e.id == 'faq_addons');
      expect(SupportAgentService.score(exact, tokens),
          greaterThan(SupportAgentService.score(other, tokens)));
    });

    test('tokenize strips punctuation and dedupes', () {
      expect(SupportAgentService.tokenize('Video, NOT playing! video'),
          ['video', 'not', 'playing']);
      expect(SupportAgentService.tokenize('   '), isEmpty);
    });
  });
}