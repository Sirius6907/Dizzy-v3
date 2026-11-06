import '../../models/stream/stream_model.dart';

/// Decides whether a scraped stream plausibly belongs to the title and
/// episode the user asked for.
///
/// Providers sometimes answer an id lookup with a completely different show
/// (the emulator got `Castlevania Nocturne (2023)` for the 2026 series
/// `Nocturne`) or return the first episode for every episode request. Both
/// cases play the wrong content. The rule is deliberately conservative:
/// reject only on positive evidence of a mismatch, never because metadata is
/// missing.
abstract final class StreamRelevance {
  /// Number tokens that are part of the requested title are never read as a
  /// release year (`Blade Runner 2049`).
  static bool isRelevant({
    required StreamSource source,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    final text = [
      source.title,
      source.name,
      source.description,
    ].whereType<String>().join(' ').trim();
    if (text.isEmpty) return true;

    if (season != null && episode != null) {
      final range = _episodeRange(text);
      if (range != null) {
        if (range.season != season) return false;
        if (episode < range.first || episode > range.last) return false;
      } else {
        final single = _seasonOnly(text);
        if (single != null && single != season) return false;
      }
    }

    if (year != null) {
      final years = _years(text, requestedTitle: title);
      if (years.isNotEmpty && !years.any((y) => (y - year).abs() <= 1)) {
        return false;
      }
    }

    if (!_titlePortionMatches(text, title, source.addonName)) return false;

    return true;
  }

  static bool _titlePortionMatches(
    String text,
    String requestedTitle,
    String addonName,
  ) {
    final prefix = _titlePrefix(text);
    if (prefix.trim().isEmpty) return true;
    final requested = _titleTokens(requestedTitle);
    final source = _titleTokens(prefix);
    if (requested.isEmpty || source.isEmpty) return true;

    // A provider prefixes a *different* show name: "Castlevania Nocturne"
    // for a request named "Nocturne". Providers truncate long titles all the
    // time, so only the leading word is treated as the show name; trailing
    // release tags are not.
    final first = source.first;
    if (first.length < 4) return true;
    if (requested.contains(first)) return true;
    if (_titleNoise.contains(first)) return true;
    if (source.length == 1 &&
        _titleTokens(addonName).join(' ') == source.first) {
      return true;
    }
    return false;
  }

  static final RegExp _titleCutRe = RegExp(
    r'[\(\[]\s*(?:19|20)\d{2}'
    r'|(?:^|[.\s_\-])(?:19|20)\d{2}(?=[.\s_\]\)\-]|$)'
    r'|\bS\d{1,2}\s*[.\-_ ]?\s*E\d{1,3}\b'
    r'|\b\d{1,2}x\d{2,3}\b'
    r'|\b(?:2160p|1080p|720p|480p|4k|uhd|web-?dl|webrip|bluray|blu-ray|brrip|hdrip|dvdrip|hevc|x265|x264|h\.?26[45]|av1|aac|ac3|eac3|ddp|atmos|hdr10\+?|dv)\b',
    caseSensitive: false,
  );

  static String _titlePrefix(String text) {
    final m = _titleCutRe.firstMatch(text);
    return m == null ? text : text.substring(0, m.start);
  }

  static final RegExp _tokenSplit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static List<String> _titleTokens(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final token in raw.toLowerCase().split(_tokenSplit)) {
      if (token.isEmpty || _titleStopWords.contains(token)) continue;
      if (seen.add(token)) out.add(token);
    }
    return out;
  }

  static const Set<String> _titleStopWords = {
    'the',
    'a',
    'an',
    'and',
    'of',
    'to',
    'in',
    'at',
    'on',
  };

  /// Audio/release markers that can sit before the title without being part
  /// of it.
  static const Set<String> _titleNoise = {
    'hindi',
    'english',
    'tamil',
    'telugu',
    'malayalam',
    'kannada',
    'punjabi',
    'marathi',
    'bengali',
    'multi',
    'dual',
    'dubbed',
    'original',
  };

  static final RegExp _episodeRe = RegExp(
    r'\bS(\d{1,2})\s*[.\-_ ]?\s*E(\d{1,3})(?:\s*[-–]\s*E?(\d{1,3}))?\b',
    caseSensitive: false,
  );

  static final RegExp _crossEpisodeRe = RegExp(
    r'\b(\d{1,2})x(\d{2,3})\b',
    caseSensitive: false,
  );

  static final RegExp _seasonOnlyRe = RegExp(
    r'\bS(\d{1,2})\b(?!\s*[.\-_ ]?E\d)',
    caseSensitive: false,
  );

  /// Parenthesised/bracketed years are always release years.
  static final RegExp _bracketedYearRe = RegExp(r'[\(\[]((?:19|20)\d{2})[\)\]]');

  /// A bare year is only a release year when separated from other tokens
  /// (`Oppenheimer.2023.1080p`), never part of `1920x1080`.
  static final RegExp _bareYearRe = RegExp(
    r'(?:^|[.\s_])?((?:19|20)\d{2})(?=[.\s_\)\]]|$)',
  );

  static ({int season, int first, int last})? _episodeRange(String text) {
    final m = _episodeRe.firstMatch(text);
    if (m != null) {
      final season = int.parse(m.group(1)!);
      final first = int.parse(m.group(2)!);
      final last = int.tryParse(m.group(3) ?? '') ?? first;
      return (season: season, first: first, last: last < first ? first : last);
    }
    final x = _crossEpisodeRe.firstMatch(text);
    if (x != null) {
      final season = int.parse(x.group(1)!);
      final ep = int.parse(x.group(2)!);
      return (season: season, first: ep, last: ep);
    }
    return null;
  }

  static int? _seasonOnly(String text) {
    final m = _seasonOnlyRe.firstMatch(text);
    return m == null ? null : int.parse(m.group(1)!);
  }

  static Set<int> _years(String text, {required String requestedTitle}) {
    final out = <int>{};
    for (final m in _bracketedYearRe.allMatches(text)) {
      out.add(int.parse(m.group(1)!));
    }
    final titleDigits = RegExp(r'\d{4}')
        .allMatches(requestedTitle)
        .map((m) => m.group(0)!)
        .toSet();
    for (final m in _bareYearRe.allMatches(text)) {
      final token = m.group(1)!;
      if (titleDigits.contains(token)) continue;
      out.add(int.parse(token));
    }
    return out;
  }
}
