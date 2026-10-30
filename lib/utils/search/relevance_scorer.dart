/// Advanced relevance scoring utility for search results.
///
/// v1.3.3 India pass: Unicode-aware normalisation (Devanagari titles used to
/// normalise to an empty string and score 0), accent folding, one-typo
/// tolerance (including transpositions), and Devanagari→Latin transliteration
/// so "पठान" finds "Pathaan" and vice versa.
class RelevanceScorer {
  /// Calculate a numeric relevance score for a [title] given a search [query].
  /// Higher score means higher relevance.
  static double score({required String title, required String query}) {
    final cleanTitle = _normalize(title);
    final cleanQuery = _normalize(query);

    if (cleanTitle.isEmpty || cleanQuery.isEmpty) return 0.0;

    var best = _core(cleanTitle, cleanQuery);

    // Cross-script pass: only when transliteration actually changes a side.
    final latinTitle = _latinize(cleanTitle);
    final latinQuery = _latinize(cleanQuery);
    if (latinTitle != cleanTitle || latinQuery != cleanQuery) {
      if (latinTitle.isNotEmpty && latinQuery.isNotEmpty) {
        final alt = _core(latinTitle, latinQuery);
        if (alt > best) best = alt;
      }
    }
    return best;
  }

  /// Sort comparator: relevance first, then the newer title wins the tie.
  /// Negative means [titleA] sorts before [titleB].
  static int compare({
    required String titleA,
    int? yearA,
    required String titleB,
    int? yearB,
    required String query,
  }) {
    final sa = score(title: titleA, query: query);
    final sb = score(title: titleB, query: query);
    if (sa != sb) return sb.compareTo(sa);
    return (yearB ?? 0).compareTo(yearA ?? 0);
  }

  static double _core(String cleanTitle, String cleanQuery) {
    final strippedTitle = _stripArticles(cleanTitle);
    final strippedQuery = _stripArticles(cleanQuery);

    // 1. Exact Match (with or without leading "the/a/an")
    if (cleanTitle == cleanQuery || strippedTitle == strippedQuery) {
      return 10000.0;
    }

    double totalScore = 0.0;

    // 2. Direct Substring Match of FULL QUERY (e.g. "vampire diaries" inside title)
    if (cleanTitle.contains(cleanQuery) ||
        strippedTitle.contains(strippedQuery)) {
      totalScore += 5000.0;
    }

    // 3. Prefix Match of FULL QUERY
    if (cleanTitle.startsWith(cleanQuery) ||
        strippedTitle.startsWith(strippedQuery)) {
      totalScore += 3000.0;
    }

    // 4. Word Token Matching
    final queryTokens = cleanQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final titleTokens = cleanTitle
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet();

    if (queryTokens.isNotEmpty) {
      int matchedCount = 0;

      for (int i = 0; i < queryTokens.length; i++) {
        final qToken = queryTokens[i];
        if (titleTokens.contains(qToken)) {
          matchedCount++;
        } else {
          // Substring token match
          final isPartialMatch = titleTokens.any(
            (t) => t.contains(qToken) || qToken.contains(t),
          );
          if (isPartialMatch) {
            matchedCount++;
          }
        }
      }

      final tokenMatchRatio = matchedCount / queryTokens.length;

      // CRITICAL: If multi-word query and NOT all query tokens matched, severely cap score
      if (queryTokens.length > 1 && tokenMatchRatio < 1.0) {
        totalScore = (totalScore + (tokenMatchRatio * 200.0)) * 0.1;
      } else {
        totalScore += tokenMatchRatio * 1000.0;
        if (tokenMatchRatio == 1.0) {
          totalScore +=
              2000.0; // Huge bonus when ALL search terms exist in title
        }
      }
    }

    // 5. One-typo tolerance — only when nothing stronger matched, so typo
    // hits can never outrank a real substring/prefix/token hit.
    if (totalScore == 0.0) {
      totalScore += _fuzzyScore(cleanTitle, cleanQuery);
    }

    return totalScore;
  }

  /// 1200 for a whole-title typo, 1100 for a single word typo. Short queries
  /// (under 5 chars) never fuzzy-match: "jawan" → "jawx" is noise, not a hit.
  static double _fuzzyScore(String title, String query) {
    if (query.length < 5) return 0.0;
    final allow = query.length >= 8 ? 2 : 1;

    for (final t in {title, _stripArticles(title)}) {
      if (t.isEmpty) continue;
      if ((t.length - query.length).abs() > allow) continue;
      if (_osa(t, query) <= allow) return 1200.0;
    }

    final titleTokens = title.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    for (final q in query.split(RegExp(r'\s+')).where((q) => q.length >= 5)) {
      final qAllow = q.length >= 8 ? 2 : 1;
      for (final t in titleTokens) {
        if ((t.length - q.length).abs() > qAllow) continue;
        if (_osa(t, q) <= qAllow) return 1100.0;
      }
    }
    return 0.0;
  }

  /// Optimal string alignment distance (Levenshtein + adjacent swap = 1).
  static int _osa(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final d = List.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var best = d[i - 1][j] + 1;
        final ins = d[i][j - 1] + 1;
        if (ins < best) best = ins;
        final sub = d[i - 1][j - 1] + cost;
        if (sub < best) best = sub;
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          final transposed = d[i - 2][j - 2] + 1;
          if (transposed < best) best = transposed;
        }
        d[i][j] = best;
      }
    }
    return d[a.length][b.length];
  }

  static String _stripArticles(String s) {
    return s
        .replaceAll(RegExp(r'^(?:the|a|an)\s+', caseSensitive: false), '')
        .trim();
  }

  static const Map<String, String> _fold = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i',
    'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o',
    'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ù': 'u', 'ú': 'u',
    'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss', 'æ': 'ae',
    'š': 's', 'ž': 'z', 'ł': 'l', 'đ': 'd',
  };

  static String _normalize(String input) {
    final lower = input.toLowerCase();
    final folded = StringBuffer();
    for (final ch in lower.split('')) {
      folded.write(_fold[ch] ?? ch);
    }
    return folded
        .toString()
        // Unicode-aware: keeps Devanagari letters/numbers, drops punctuation.
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Devanagari → Latin, enough for Bollywood/Tollywood title lookups.
  static const Map<String, String> _consonants = {
    'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'n',
    'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'n',
    'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
    'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
    'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm',
    'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh',
    'ष': 'sh', 'स': 's', 'ह': 'h', 'ळ': 'l',
    'क़': 'q', 'ख़': 'kh', 'ग़': 'g', 'ज़': 'z', 'ड़': 'r',
    'ढ़': 'rh', 'फ़': 'f',
  };

  static const Map<String, String> _independentVowels = {
    'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u', 'ऊ': 'oo',
    'ऋ': 'ri', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au', 'ऑ': 'o',
    'ऍ': 'e', 'ऎ': 'e', 'ॐ': 'om',
  };

  /// Matras that already carry the consonant's vowel — no inherent "a".
  static const Map<String, String> _vowelSigns = {
    'ा': 'aa', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo', 'ृ': 'ri',
    'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au', 'ॉ': 'o', 'ॅ': 'e',
    '्': '',
  };

  static const Map<String, String> _marks = {
    'ं': 'n', 'ँ': 'n', 'ः': 'h',
  };

  static const Map<String, String> _digits = {
    '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
    '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
  };

  static String _latinize(String s) {
    if (!s.runes.any((r) => r >= 0x0900 && r <= 0x097F)) return s;
    final chars = s.split('');
    final out = StringBuffer();
    var i = 0;
    while (i < chars.length) {
      final pair = i + 1 < chars.length ? chars[i] + chars[i + 1] : '';
      final pairConsonant = pair.isEmpty ? null : _consonants[pair];
      if (pairConsonant != null) {
        out.write(pairConsonant);
        if (_inherentAfter(chars, i + 2)) out.write('a');
        i += 2;
        continue;
      }
      final ch = chars[i];
      final consonant = _consonants[ch];
      if (consonant != null) {
        out.write(consonant);
        if (_inherentAfter(chars, i + 1)) out.write('a');
      } else if (_independentVowels[ch] != null) {
        out.write(_independentVowels[ch]);
      } else if (_vowelSigns[ch] != null) {
        out.write(_vowelSigns[ch]);
      } else if (_marks[ch] != null) {
        out.write(_marks[ch]);
      } else if (_digits[ch] != null) {
        out.write(_digits[ch]);
      } else if (ch == ' ') {
        out.write(' ');
      }
      i++;
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Hindi drops the word-final inherent vowel: पठान → "pathaan", not
  /// "pathaana". Matras, virama, nukta and word boundaries all suppress it.
  static bool _inherentAfter(List<String> chars, int idx) {
    if (idx >= chars.length) return false;
    final next = chars[idx];
    if (_vowelSigns.containsKey(next)) return false;
    if (next == '़' || next == ' ') return false;
    return true;
  }
}
