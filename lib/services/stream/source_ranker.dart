import 'dart:math' as math;

import '../../models/stream/stream_model.dart';

/// Context the ranker needs beyond the source itself.
class RankerContext {
  /// addonName → last-good fingerprint (from LastGoodSourceStore).
  final Map<String, String> lastGoodByAddon;

  /// Fingerprint failed during THIS session — never reuse.
  final Set<String> failedThisSession;

  /// Preferred audio language tag (e.g. 'hin', 'eng'), if any.
  final String? preferredLang;

  const RankerContext({
    this.lastGoodByAddon = const {},
    this.failedThisSession = const {},
    this.preferredLang,
  });
}

/// Scores and orders stream sources so playback starts on the source
/// most likely to work, and failover has a pre-computed fallback chain.
///
/// Weights are additive; higher score = better. Ordering is stable:
/// ties break by original list position (first offered = first kept).
class SourceRanker {
  static const int _wAddonHistory = 40;
  static const int _wDebrid = 25;
  static const int _wHttpDirect = 20;
  static const int _wSeeders = 15;
  static const int _wResolution = 10;
  static const int _wPreferredLang = 5;
  static const int _penaltyRecentFailure = 30;

  /// Stable identity for a source across retries/scrapes.
  /// addon + url/infoHash is enough to recognize "the same stream".
  static String fingerprint(StreamSource s) {
    final id = s.url ?? s.infoHash ?? s.externalUrl ?? s.title ?? '';
    return '${s.addonName}::$id';
  }

  static int score(StreamSource s, RankerContext ctx) {
    var score = 0;

    // 1. Addon that worked before for this title's history.
    if (ctx.lastGoodByAddon.containsKey(s.addonName)) score += _wAddonHistory;

    // 2. Debrid direct streams (Torbox etc.) — fastest + most reliable.
    final url = (s.url ?? '').toLowerCase();
    final name = (s.name ?? s.title ?? '').toLowerCase();
    if (url.contains('torbox') ||
        url.contains('debrid') ||
        url.contains('real-debrid') ||
        url.contains('premiumize') ||
        name.contains('debrid') ||
        name.contains('torbox')) {
      score += _wDebrid;
    }

    // 3. Plain HTTP direct stream beats torrents.
    if (s.url != null && s.url!.isNotEmpty && s.infoHash == null) {
      score += _wHttpDirect;
    }

    // 4. Seeder count, log-scaled 0.._wSeeders (1000+ = full weight).
    final seeders = _parseSeeders(s);
    if (seeders != null) {
      score += (_wSeeders *
              (_log2(seeders + 1) / _log2(1001)))
          .clamp(0, _wSeeders)
          .round();
    }

    // 5. Resolution hint in name/description.
    score += _resolutionScore(s);

    // 6. Audio language match.
    if (ctx.preferredLang != null && _langMatches(s, ctx.preferredLang!)) {
      score += _wPreferredLang;
    }

    // 7. Failed this session — sink hard.
    if (ctx.failedThisSession.contains(fingerprint(s))) {
      score -= _penaltyRecentFailure;
    }

    return score;
  }

  /// Returns sources ordered best→worst, preserving input order on ties.
  static List<StreamSource> order(
    Iterable<StreamSource> sources,
    RankerContext ctx,
  ) {
    final list = sources.toList();
    final scores = {for (final s in list) fingerprint(s): score(s, ctx)};
    final indexed = list.asMap().entries.toList();
    indexed.sort((a, b) {
      final d = scores[fingerprint(b.value)]! - scores[fingerprint(a.value)]!;
      if (d != 0) return d;
      return a.key.compareTo(b.key); // stable: original order on ties
    });
    return indexed.map((e) => e.value).toList();
  }

  // ── helpers ────────────────────────────────────────────────────────

  static double _log2(num x) {
    if (x <= 1) return 0;
    return math.log(x.toDouble()) / math.ln2;
  }

  static int? _parseSeeders(StreamSource s) {
    // Common patterns: " Tracker: 1,234 seeders", "S: 123"
    final text = '${s.name ?? ''} ${s.description ?? ''}';
    final m = RegExp(r'(\d[\d,]*)\s*seeders?', caseSensitive: false)
        .firstMatch(text);
    if (m == null) return null;
    return int.tryParse(m.group(1)!.replaceAll(',', ''));
  }

  static int _resolutionScore(StreamSource s) {
    final text = '${s.name ?? ''} ${s.description ?? ''} ${s.title ?? ''}'
        .toLowerCase();
    if (text.contains('2160') || text.contains('4k')) return _wResolution;
    if (text.contains('1080')) return 8;
    if (text.contains('720')) return 5;
    return 0;
  }

  static bool _langMatches(StreamSource s, String lang) {
    final text = '${s.name ?? ''} ${s.description ?? ''}'.toLowerCase();
    return text.contains(lang.toLowerCase());
  }
}
