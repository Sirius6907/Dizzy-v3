import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../cloud/cloud_client.dart';
import '../errors/session_trail.dart';

/// v1.3.3-T4 — offline-first support brain.
///
/// Three tiers, cheapest first:
///   1. OFFLINE FAQ — bundled JSON, scored locally, zero network. This is
///      the tier that answers most "how do I…" questions instantly.
///   2. ONLINE RAG — Supabase Edge `support-answer` (docs + changelog +
///      error-code index). Used when the local score is weak.
///   3. TICKET — nothing matched: open a ticket with the T2.3 trail
///      attached so a human sees the path into the problem.
///
/// Language: the user's first message decides (roman/English → English,
/// Hinglish/Hindi → Hinglish). We never ask.
class SupportAgentService {
  SupportAgentService._();

  static final SupportAgentService instance = SupportAgentService._();

  /// Below this score a local answer is not trusted enough to show alone.
  /// Tuned so a single weak keyword hit routes to tier 2 instead of
  /// confidently answering the wrong question.
  static const double localThreshold = 1.6;

  static List<FaqEntry> _entries = const [];
  static bool _loaded = false;
  static String _bundleVersion = 'v1';

  static String get bundleVersion => _bundleVersion;
  static int get entryCount => _entries.length;

  /// Load the bundled FAQ once. Fail-soft: a bad asset leaves tier 1 empty
  /// and every query falls through to the online tier.
  static Future<void> initialize({AssetBundle? bundle}) async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await (bundle ?? rootBundle)
          .loadString('assets/support_kb/support_faq_v1.json');
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _bundleVersion = (decoded['version'] ?? 'v1').toString();
        final list = decoded['entries'];
        if (list is List) {
          _entries = list
              .whereType<Map>()
              .map((m) => FaqEntry.fromJson(Map<String, dynamic>.from(m)))
              .where((e) => e.id.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      AppLogShim.d('[Support] FAQ bundle load failed (soft): $e');
    }
  }

  /// Test-only: inject entries without touching the asset bundle.
  @visibleForTesting
  static void seedForTest(List<FaqEntry> entries, {String version = 'test'}) {
    _entries = entries;
    _bundleVersion = version;
    _loaded = true;
  }

  /// Tier 1: best local match, or null when nothing scores high enough.
  static FaqEntry? localMatch(String query) {
    final scored = scoreAll(query);
    if (scored.isEmpty || scored.first.score < localThreshold) return null;
    return scored.first.entry;
  }

  /// Ranked local matches, best first. Pure — unit testable.
  static List<ScoredFaq> scoreAll(String query) {
    final tokens = tokenize(query);
    if (tokens.isEmpty || _entries.isEmpty) return const [];
    final out = <ScoredFaq>[];
    for (final e in _entries) {
      final s = score(e, tokens);
      if (s > 0) out.add(ScoredFaq(entry: e, score: s));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// Score one entry against query tokens.
  ///
  /// Weighting (deliberately simple, no BM25 corpus stats — the bundle is
  /// 24 entries, so IDF buys nothing and costs a re-tune per entry):
  ///   * full query appears in a trigger phrase  → 3.0
  ///   * each matching trigger token             → 1.0
  ///   * each matching answer token              → 0.35 (weak signal)
  /// An exact-phrase hit must beat any pile of scattered words, otherwise
  /// a long answer with common words outranks the exact question.
  @visibleForTesting
  static double score(FaqEntry e, List<String> queryTokens) {
    final q = queryTokens.join(' ');
    var s = 0.0;
    for (final trigger in e.triggers) {
      final t = trigger.toLowerCase();
      if (t.contains(q) && q.isNotEmpty) {
        s += 3.0;
        break;
      }
    }
    final triggerText = e.triggers.join(' ').toLowerCase();
    for (final tok in queryTokens) {
      if (triggerText.contains(tok)) s += 1.0;
    }
    final answerText =
        '${e.answerEn} ${e.answerHi ?? ''}'.toLowerCase();
    for (final tok in queryTokens) {
      if (tok.length >= 4 && answerText.contains(tok)) s += 0.35;
    }
    return s;
  }

  /// Lowercase word tokens, punctuation stripped, 2+ chars, deduped in
  /// order — keeps scoring stable and cheap.
  @visibleForTesting
  static List<String> tokenize(String raw) {
    final cleaned = raw.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    final seen = <String>{};
    final out = <String>[];
    for (final w in cleaned.split(RegExp(r'\s+'))) {
      if (w.length < 2) continue;
      if (seen.add(w)) out.add(w);
    }
    return out;
  }

  /// Which language to answer in, from the user's own message.
  /// Hinglish/Hindi (roman or devanagari) → 'hi'; else 'en'.
  static String detectLanguage(String message) {
    final m = message.toLowerCase();
    if (RegExp(r'[\u0900-\u097F]').hasMatch(m)) return 'hi';
    const hindiRoman = [
      'nahi', 'nahin', 'kaise', 'kya', 'kyun', 'kyu', 'hai', 'hain', 'ho',
      'raha', 'rahi', 'gaya', 'gayi', 'karo', 'karna', 'chala', 'chal',
      'nahi', 'mujhe', 'mera', 'meri', 'aap', 'tum', 'bhai', 'dost',
      'kuch', 'bahut', 'thoda', 'achha', 'theek', 'kaam', 'bata', 'do',
    ];
    for (final w in tokenize(m)) {
      if (hindiRoman.contains(w)) return 'hi';
    }
    return 'en';
  }

  /// The answer text for a language, falling back to English.
  static String answerFor(FaqEntry e, String lang) {
    if (lang == 'hi') {
      final hi = e.answerHi;
      if (hi != null && hi.trim().isNotEmpty) return hi;
    }
    return e.answerEn;
  }

  /// Full three-tier ask. Tier 1 answers offline and instantly; only a weak
  /// local score costs a network round-trip. Never throws — a total failure
  /// returns a ticket-style result so the UI always has something to show.
  ///
  /// [logQuestion] must be false when telemetry consent is off: the server
  /// already treats an empty question as "log the match only".
  static Future<SupportAnswer> ask(
    String message, {
    bool logQuestion = true,
  }) async {
    final lang = detectLanguage(message);
    final local = localMatch(message);

    if (local != null) {
      final scored = scoreAll(message);
      unawaitedLog(
        question: logQuestion ? message : '',
        matchedId: local.id,
        score: scored.isNotEmpty ? scored.first.score : 0,
        lang: lang,
        tier: 'local',
      );
      return SupportAnswer(
        text: answerFor(local, lang),
        lang: lang,
        tier: SupportTier.local,
        matchedId: local.id,
        suggestTicket: false,
      );
    }

    // Tier 2 — server KB (+LLM phrasing when a key is configured).
    try {
      if (CloudClient.isReady) {
        final res = await CloudClient.db.functions.invoke(
          'support-answer',
          body: {
            'question': logQuestion ? message : '',
            'lang': lang,
            'trail': SessionTrail.wire(),
          },
        );
        final data = res.data;
        if (data is Map) {
          final text = (data['answer'] ?? '').toString().trim();
          final tier = (data['tier'] ?? 'none').toString();
          if (text.isNotEmpty) {
            return SupportAnswer(
              text: text,
              lang: lang,
              tier: tier == 'llm' ? SupportTier.llm : SupportTier.kb,
              matchedId: (data['matched_id'] ?? '').toString(),
              suggestTicket: data['suggest_ticket'] == true,
            );
          }
          return SupportAnswer(
            text: '',
            lang: lang,
            tier: SupportTier.none,
            matchedId: '',
            suggestTicket: true,
          );
        }
      }
    } catch (e) {
      AppLogShim.d('[Support] online tier failed (soft): $e');
    }

    // Tier 3 — nothing matched: hand it to a human.
    return SupportAnswer(
      text: '',
      lang: lang,
      tier: SupportTier.none,
      matchedId: '',
      suggestTicket: true,
    );
  }

  /// Fire-and-forget answer logging; a failure here is not worth a retry
  /// (it is analytics for KB improvement, not user-facing).
  static void unawaitedLog({
    required String question,
    required String matchedId,
    required double score,
    required String lang,
    required String tier,
  }) {
    if (!CloudClient.isReady) return;
    CloudClient.db.rpc('support_log_answer', params: {
      'p_question': question,
      'p_matched': matchedId,
      'p_score': score,
      'p_lang': lang,
      'p_tier': tier,
      'p_escalated': false,
    }).then((_) {}, onError: (_) {});
  }

  /// Open a ticket (tier 3). Returns the ticket id, or null when offline /
  /// unauthenticated — the UI then offers a plain "try later" state.
  static Future<String?> openTicket({
    required String topic,
    String deviceCode = 'unknown',
    List<String> codes = const [],
  }) async {
    try {
      if (!CloudClient.isReady) return null;
      final res = await CloudClient.db.rpc('support_open_ticket', params: {
        'p_topic': topic,
        'p_device_code': deviceCode,
        'p_platform': _platformName(),
        'p_version': '',
        'p_codes': codes,
        'p_trail': SessionTrail.wire(),
        'p_ai_answered': false,
      });
      final id = res?.toString();
      return (id == null || id.isEmpty) ? null : id;
    } catch (e) {
      AppLogShim.d('[Support] ticket failed (soft): $e');
      return null;
    }
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }
}

/// Which tier produced the answer.
enum SupportTier { local, kb, llm, none }

/// One support answer, ready for the chat bubble.
class SupportAnswer {
  final String text;
  final String lang;
  final SupportTier tier;
  final String matchedId;
  final bool suggestTicket;

  const SupportAnswer({
    required this.text,
    required this.lang,
    required this.tier,
    required this.matchedId,
    required this.suggestTicket,
  });

  bool get hasText => text.trim().isNotEmpty;
}

/// One offline FAQ record.
class FaqEntry {
  final String id;
  final String topic;
  final List<String> triggers;
  final String answerEn;
  final String? answerHi;

  const FaqEntry({
    required this.id,
    required this.topic,
    required this.triggers,
    required this.answerEn,
    this.answerHi,
  });

  factory FaqEntry.fromJson(Map<String, dynamic> json) {
    final a = json['a'];
    final ans = a is Map ? Map<String, dynamic>.from(a) : const <String, dynamic>{};
    final qList = json['q'];
    return FaqEntry(
      id: (json['id'] ?? '').toString(),
      topic: (json['topic'] ?? 'other').toString(),
      triggers: qList is List
          ? qList.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
      answerEn: (ans['en'] ?? '').toString(),
      answerHi: ans['hi']?.toString(),
    );
  }
}

/// An entry with its local score.
class ScoredFaq {
  final FaqEntry entry;
  final double score;
  const ScoredFaq({required this.entry, required this.score});
}

/// Minimal indirection so this file does not depend on the logger, which
/// would create an import cycle with the error pipeline.
class AppLogShim {
  const AppLogShim._();
  static void d(Object? message) {
    if (kDebugMode) {
      // ignore: avoid_print
      debugPrint('$message');
    }
  }
}