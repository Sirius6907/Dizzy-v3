/// v1.3.3-T3.3 — title/query matching rules for music search.
///
/// The bug this exists to kill: Odia and mixed-name queries returned the
/// WRONG song. Cause was `contains`-first lookup with a `results.first`
/// fallback — a fuzzy hit beats a correct miss, and a wrong song is far
/// worse than an empty row.
///
/// Rules (site §13 exact-match-or-nothing):
///   1. Exact match wins: case/punctuation/diacritic-insensitive.
///   2. Transliteration aliasing: Odia/Hindi ↔ latin lookalikes.
///   3. Language tag boosts a candidate when the query carries one.
///   4. No exact hit → return null. Never a best guess.
class MusicMatchPolicy {
  const MusicMatchPolicy._();

  /// Latin digraphs commonly used to romanise Odia/Hindi.
  /// Applied to BOTH sides so "jhia" and "jhiya" converge.
  static const Map<String, String> _translit = {
    'aa': 'a', 'ee': 'i', 'ii': 'i', 'oo': 'u', 'uu': 'u',
    'ai': 'ai', 'au': 'au', 'ou': 'o', 'ea': 'i',
    'kh': 'k', 'gh': 'g', 'ch': 'c', 'chh': 'c', 'jh': 'j',
    'th': 't', 'dh': 'd', 'ph': 'f', 'bh': 'b', 'sh': 's',
    'ss': 's', 'tt': 't', 'dd': 'd', 'nn': 'n', 'll': 'l',
    'mm': 'm', 'yy': 'y', 'vv': 'v', 'zz': 'j',
    'x': 'ks', 'q': 'k', 'z': 'j', 'w': 'v',
  };

  /// Normalise for comparison: lowercase, strip punctuation, collapse
  /// whitespace, then fold transliteration pairs. Deliberately lossy — it
  /// only ever feeds an EQUALITY check, never a substring test.
  static String normalize(String raw) {
    var s = raw.toLowerCase().trim();
    // Strip bracketed suffixes: "Song (From \"Film\")" → "song".
    s = s.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ');
    // Strip feature credits: "Song feat. X", "Song ft X".
    s = s.replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*$'), ' ');
    // Punctuation → space.
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final e in _translit.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    // Collapse doubled letters left by the fold ("kkaal" → "kal").
    s = s.replaceAll(RegExp(r'(.)\1+'), r'$1');
    return s.trim();
  }

  /// True when two titles are the same song. Combination-insensitive:
  /// "A B" and "B A" both normalise to a sorted token set comparison.
  static bool titlesMatch(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    // Token-set equality handles word-order differences ("Kal Ho Naa Ho"
    // vs "Naa Ho Kal Ho") without opening the door to partial matches.
    final ta = na.split(' ').where((w) => w.isNotEmpty).toList()..sort();
    final tb = nb.split(' ').where((w) => w.isNotEmpty).toList()..sort();
    return ta.join(' ') == tb.join(' ');
  }

  /// Exact-title picker. Returns the matching candidate's index, or null.
  ///
  /// [year] is a TIEBREAK only, never a way in: a candidate with the right
  /// title and a wrong year still matches, a candidate with a similar title
  /// never does.
  static int? pickExact(
    String wanted, {
    required List<String> candidateTitles,
    int? year,
    List<int?> candidateYears = const [],
    String lang = '',
    List<String> candidateLangs = const [],
  }) {
    final hits = <int>[];
    for (var i = 0; i < candidateTitles.length; i++) {
      if (titlesMatch(wanted, candidateTitles[i])) hits.add(i);
    }
    if (hits.isEmpty) return null;
    if (hits.length == 1) return hits.first;

    // Disambiguate duplicates (same song, many uploads).
    if (year != null && candidateYears.length == candidateTitles.length) {
      for (final i in hits) {
        final cy = candidateYears[i];
        if (cy != null && (cy - year).abs() <= 1) return i;
      }
    }
    if (lang.isNotEmpty && candidateLangs.length == candidateTitles.length) {
      for (final i in hits) {
        if (candidateLangs[i].toLowerCase() == lang.toLowerCase()) return i;
      }
    }
    return hits.first; // same song, same title — first is as good as any
  }

  /// Language hint from the query when it carries one, else ''.
  static String languageHint(String query) {
    final q = query.toLowerCase();
    // Odia block is U+0B00–U+0B7F; Devanagari is U+0900–U+097F.
    // NOTE: these ranges use NON-raw Dart strings — inside a raw string
    // (`r'...'`) `\u` is a literal backslash-u and the class matches the
    // letters "u", "0", "B"… which silently matches EVERY query.
    if (RegExp('[\u0B00-\u0B7F]').hasMatch(q)) return 'oriya';
    if (RegExp('[\u0900-\u097F]').hasMatch(q)) return 'hindi';
    // Word-boundary token matching so 'bollywood' never matches substring 'ollywood'.
    final words = q.split(RegExp(r'[^a-z0-9]+')).toSet();
    const hints = {
      'bollywood': 'hindi', 'ollywood': 'oriya', 'oliywood': 'oriya',
      'sambalpuri': 'oriya', 'odia': 'oriya', 'oriya': 'oriya',
      'hindi': 'hindi', 'punjabi': 'punjabi', 'bhangra': 'punjabi',
      'tamil': 'tamil', 'telugu': 'telugu', 'bengali': 'bengali',
      'english': 'english',
    };
    for (final e in hints.entries) {
      if (words.contains(e.key)) return e.value;
    }
    return '';
  }
}