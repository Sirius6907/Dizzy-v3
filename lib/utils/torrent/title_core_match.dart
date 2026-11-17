/// Core-title matching for the title-searching torrent scrapers.
///
/// Why: a release is indexed under its CORE name ("Dahaan (2026) [Odia]"),
/// while the app asks for the full catalogue name ("Dahaan: The Evil
/// Within"). The scraper compared the two verbatim, so every correctly
/// indexed release of a subtitled title was thrown away - measured as
/// "sources kam" for exactly the regional titles the owner complained about.
///
/// The rule stays conservative: the CORE name (subtitle, brackets and stop
/// words removed) must be equal, or the candidate must extend the core
/// ("Dahaan" -> "Dahaan The Evil Within"), or the two must be one edit apart
/// AND the core must be long enough for that to mean anything
/// ("Madhumalati" / "Madhumallati"). Short cores never get the edit
/// allowance, so "Murabi" can never be answered by "Murali".
library;

/// Strips subtitles, brackets and stop words, then compares on letters and
/// digits only.
abstract final class TitleCoreMatch {
  static final RegExp _brackets = RegExp(r'\([^)]*\)');
  static final RegExp _trailingSubtitle = RegExp(r':\s*[^:]*$');
  static final RegExp _trailingDash = RegExp(r'[–—\-]\s*[^–—\-]*$');
  static final RegExp _stop = RegExp(
    r'\b(the|a|an|of|and|part|ka|ki|ke|with)\b',
    caseSensitive: false,
  );

  /// The core of a title: lowercase, letters and digits only.
  static String core(String title) {
    var s = title.toLowerCase();
    s = s.replaceAll(_brackets, ' ');
    s = s.replaceAll(_trailingSubtitle, ' ');
    s = s.replaceAll(_trailingDash, ' ');
    s = s.replaceAll(_stop, ' ');
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  /// Damerau-Levenshtein distance (a transposition counts as one edit).
  static int editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final d = List.generate(
      a.length + 1,
      (i) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var best = d[i - 1][j] + 1;
        if (d[i][j - 1] + 1 < best) best = d[i][j - 1] + 1;
        if (d[i - 1][j - 1] + cost < best) best = d[i - 1][j - 1] + cost;
        if (i > 1 &&
            j > 1 &&
            a[i - 1] == b[j - 2] &&
            a[i - 2] == b[j - 1]) {
          final sub = d[i - 2][j - 2] + 1;
          if (sub < best) best = sub;
        }
        d[i][j] = best;
      }
    }
    return d[a.length][b.length];
  }

  /// Does [candidate] plausibly name the same film as [requested]?
  ///
  /// [candidateYear] / [year] are the release years when known; a known
  /// year that disagrees by more than one year rejects the match.
  static bool matches({
    required String requested,
    required String candidate,
    int? year,
    int? candidateYear,
  }) {
    if (year != null &&
        candidateYear != null &&
        (candidateYear - year).abs() > 1) {
      return false;
    }
    final a = core(requested);
    final b = core(candidate);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    // The candidate carries extra words ("Dahaan" -> "Dahaan Evil Within").
    if (a.length >= 5 && b.startsWith(a)) return true;
    // One spelling slip, but only when the core is long enough that the
    // similarity cannot be a coincidence.
    if (a.length >= 8 && editDistance(a, b) <= 1) return true;
    return false;
  }
}
