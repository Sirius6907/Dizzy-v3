/// F5 — "Because you watched X".
///
/// Every rail on Discover Daily carries a reason. We already know what a
/// person played; we do **not** need a paid model to tell them what to play
/// next. The whole rule set lives here, in pure functions, so it is unit
/// tested without a player, a network, or a login.
///
/// Three rules, and they are the product:
///
///   1. A rail is always caused by something real from the history.
///   2. A title never re-suggests itself, and never appears on two rails.
///   3. No history is not an error — it is the "start anywhere" rail.
///
/// Zero Flutter, zero storage, zero network here on purpose: the widget and
/// the service ask this file, they never re-derive the answer.
library;

/// One thing a person has played or saved, flattened out of the player model
/// so this file stays free of Flutter and of `ContinueWatchingItem`.
class WatchSignal {
  /// Stable media id. Used to keep a title off its own rail.
  final String mediaId;

  final String title;

  /// `'movie'` or `'series'`. Anything else is treated as a movie.
  final String type;

  /// Genre names, free-form. Compared case-insensitively.
  final List<String> genres;

  final DateTime watchedAt;

  /// Watched fraction, `0.0..1.0`. Unknown length reads as `0.0`.
  final double progress;

  const WatchSignal({
    required this.mediaId,
    required this.title,
    required this.type,
    this.genres = const [],
    required this.watchedAt,
    this.progress = 0.0,
  });

  bool get isSeries => type.trim().toLowerCase() == 'series';

  bool get isUsable =>
      mediaId.trim().isNotEmpty && title.trim().isNotEmpty;
}

/// One candidate title from the local catalog.
class RailCandidate {
  final String id;
  final String title;
  final String type;
  final List<String> genres;

  /// Catalog rating when known. Drives the no-history fallback order.
  final double? rating;

  /// Where this candidate came from — kept so the UI can group rails and so
  /// a test can prove we did not silently drop a section.
  final String origin;

  const RailCandidate({
    required this.id,
    required this.title,
    required this.type,
    this.genres = const [],
    this.rating,
    this.origin = '',
  });

  bool get isUsable => id.trim().isNotEmpty && title.trim().isNotEmpty;
}

/// A single card inside a rail, with the reason it earned the place.
class RailPick {
  final String id;
  final String title;
  final String type;

  /// Title of the history item that caused this pick. Empty for the
  /// no-history rail, which is caused by nothing on purpose.
  final String because;

  /// Higher is a stronger match. Deterministic — see [HistoryRailPolicy].
  final double score;

  const RailPick({
    required this.id,
    required this.title,
    required this.type,
    required this.because,
    required this.score,
  });
}

/// One horizontal row on Discover Daily.
class DiscoverRail {
  final String id;

  /// Easy English headline, e.g. "Because you watched Fight Club".
  final String title;

  /// One short line under the headline.
  final String subtitle;

  final List<RailPick> picks;

  const DiscoverRail({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.picks,
  });

  bool get isEmpty => picks.isEmpty;
}

/// Local, deterministic ranking of "what should I watch next".
abstract final class HistoryRailPolicy {
  /// How many history seeds become rails. More seeds means more rows but a
  /// thinner reason for each, so the count is deliberately small.
  static const int maxSeeds = 3;

  /// Cards per rail.
  static const int picksPerRail = 14;

  /// A seed is only interesting if it has a title and an id.
  static const int maxCandidates = 400;

  /// Words dropped before title tokens are compared. Without this, "the" and
  /// "of" make every title look like every other title.
  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'of', 'and', 'or', 'in', 'on', 'at', 'to', 'for',
    'with', 'is', 'it', 'my', 'your',
  };

  static String _norm(String raw) => raw.trim().toLowerCase();

  static Set<String> _genreKeys(List<String> genres) {
    final out = <String>{};
    for (final g in genres) {
      final k = _norm(g);
      if (k.isNotEmpty) out.add(k);
    }
    return out;
  }

  static Set<String> _titleTokens(String title) {
    final cleaned = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'));
    final out = <String>{};
    for (final w in cleaned) {
      if (w.length < 3) continue;
      if (_stopWords.contains(w)) continue;
      out.add(w);
    }
    return out;
  }

  /// Pick the seeds that earn a rail: freshest first, one row per title,
  /// never the same media twice.
  static List<WatchSignal> seedsFrom(
    List<WatchSignal> signals, {
    int maxSeeds = maxSeeds,
  }) {
    final usable = signals.where((s) => s.isUsable).toList()
      ..sort((a, b) {
        final byTime = b.watchedAt.compareTo(a.watchedAt);
        return byTime != 0 ? byTime : a.mediaId.compareTo(b.mediaId);
      });

    final seen = <String>{};
    final out = <WatchSignal>[];
    for (final s in usable) {
      if (!seen.add(s.mediaId)) continue;
      out.add(s);
      if (out.length >= maxSeeds) break;
    }
    return out;
  }

  /// Score one candidate against one seed.
  ///
  /// Genre overlap dominates because it is the only signal that survives a
  /// title nobody has heard of yet. Title words are a small tie-breaker, and
  /// [genreScores] (the local, anonymous taste map) breaks ties between two
  /// candidates with the same genres.
  static double scoreCandidate({
    required RailCandidate candidate,
    required WatchSignal seed,
    Map<String, double> genreScores = const {},
  }) {
    final seedGenres = _genreKeys(seed.genres);
    final candGenres = _genreKeys(candidate.genres);

    var genreOverlap = 0.0;
    for (final g in candGenres) {
      if (seedGenres.contains(g)) genreOverlap += 1.0;
    }

    final seedTokens = _titleTokens(seed.title);
    final candTokens = _titleTokens(candidate.title);
    var wordOverlap = 0.0;
    for (final w in candTokens) {
      if (seedTokens.contains(w)) wordOverlap += 1.0;
    }

    var taste = 0.0;
    for (final g in candGenres) {
      taste += genreScores[_norm(g)] ?? 0.0;
    }
    if (taste > 1.0) taste = 1.0;

    final typeMatch = _norm(candidate.type) == _norm(seed.type) ? 1.0 : 0.0;
    // A little bonus for finishing something: a finished show is a stronger
    // taste statement than a title abandoned after one scene.
    final finishedBonus = seed.progress >= 0.9 ? 0.25 : 0.0;

    return genreOverlap * 3.0 +
        wordOverlap * 1.5 +
        taste * 2.0 +
        typeMatch * 0.75 +
        finishedBonus;
  }

  /// Build one rail for [seed].
  ///
  /// [claimed] is every id already used by an earlier rail, so a title never
  /// shows up twice on the screen. Ordering is score-desc then id-asc, which
  /// makes the whole screen stable across rebuilds — a rail that reshuffles
  /// on every frame is a rail nobody trusts.
  static DiscoverRail? railFor(
    WatchSignal seed, {
    required List<RailCandidate> candidates,
    Set<String> claimed = const {},
    Map<String, double> genreScores = const {},
    int picksPerRail = picksPerRail,
  }) {
    if (!seed.isUsable) return null;

    final scored = <(RailCandidate, double)>[];
    for (final c in candidates) {
      if (!c.isUsable) continue;
      if (_norm(c.id) == _norm(seed.mediaId)) continue;
      if (claimed.contains(c.id)) continue;
      final s = scoreCandidate(
        candidate: c,
        seed: seed,
        genreScores: genreScores,
      );
      if (s <= 0) continue;
      scored.add((c, s));
    }
    if (scored.isEmpty) return null;

    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$1.id.compareTo(b.$1.id);
    });

    final picks = scored
        .take(picksPerRail)
        .map((e) => RailPick(
              id: e.$1.id,
              title: e.$1.title,
              type: e.$1.type,
              because: seed.title,
              score: e.$2,
            ))
        .toList();

    if (picks.isEmpty) return null;

    return DiscoverRail(
      id: 'rail:seed:${seed.mediaId}',
      title: RailCopy.railTitle(seed.title),
      subtitle: RailCopy.railSubtitle(picks.length),
      picks: picks,
    );
  }

  /// Every "because you watched" rail, top seed first.
  static List<DiscoverRail> railsFrom(
    List<WatchSignal> signals, {
    required List<RailCandidate> candidates,
    Map<String, double> genreScores = const {},
    int maxSeeds = maxSeeds,
  }) {
    final seeds = seedsFrom(signals, maxSeeds: maxSeeds);
    final claimed = <String>{};
    final rails = <DiscoverRail>[];
    for (final seed in seeds) {
      final rail = railFor(
        seed,
        candidates: candidates,
        claimed: claimed,
        genreScores: genreScores,
      );
      if (rail == null) continue;
      claimed.addAll(rail.picks.map((p) => p.id));
      rails.add(rail);
    }
    return rails;
  }

  /// The rail a brand-new person gets.
  ///
  /// There is no history to blame, so this row is caused by nothing and says
  /// so. Ordering falls back to catalog order, then rating, then id — always
  /// deterministic, never a random shuffle that changes on every rebuild.
  static DiscoverRail fallbackRail(
    List<RailCandidate> candidates, {
    Map<String, double> genreScores = const {},
    int picksPerRail = picksPerRail,
    Set<String> claimed = const {},
  }) {
    final usable = candidates
        .where((c) => c.isUsable && !claimed.contains(c.id))
        .toList();

    if (usable.isEmpty) {
      return const DiscoverRail(
        id: 'rail:start-anywhere',
        title: RailCopy.fallbackTitle,
        subtitle: RailCopy.fallbackSubtitle,
        picks: [],
      );
    }

    usable.sort((a, b) {
      final ta = _tasteTotal(a, genreScores);
      final tb = _tasteTotal(b, genreScores);
      if (ta != tb) return tb.compareTo(ta);
      final ra = a.rating ?? -1.0;
      final rb = b.rating ?? -1.0;
      if (ra != rb) return rb.compareTo(ra);
      return a.id.compareTo(b.id);
    });

    final picks = usable
        .take(picksPerRail)
        .map((c) => RailPick(
              id: c.id,
              title: c.title,
              type: c.type,
              because: '',
              score: _tasteTotal(c, genreScores),
            ))
        .toList();

    return DiscoverRail(
      id: 'rail:start-anywhere',
      title: RailCopy.fallbackTitle,
      subtitle: RailCopy.fallbackSubtitle,
      picks: picks,
    );
  }

  /// All rails for a Discover screen: history rails first, then the
  /// start-anywhere row only when there is room left.
  static List<DiscoverRail> discoverRails({
    required List<WatchSignal> signals,
    required List<RailCandidate> candidates,
    Map<String, double> genreScores = const {},
  }) {
    final capped = candidates.take(maxCandidates).toList();
    final rails = railsFrom(
      signals,
      candidates: capped,
      genreScores: genreScores,
    );
    if (rails.isNotEmpty) return rails;

    final fallback = fallbackRail(capped, genreScores: genreScores);
    return fallback.isEmpty ? const [] : [fallback];
  }

  static double _tasteTotal(RailCandidate c, Map<String, double> genreScores) {
    var t = 0.0;
    for (final g in _genreKeys(c.genres)) {
      t += genreScores[g] ?? 0.0;
    }
    if (t > 1.0) t = 1.0;
    return t;
  }
}

/// Every rail headline, in one place.
///
/// Easy English: short sentences, no tech words, no error codes. The copy
/// test reads this file's output, so a new line cannot leak jargon.
abstract final class RailCopy {
  const RailCopy._();

  /// "Because you watched Fight Club"
  static String railTitle(String seedTitle) {
    final t = seedTitle.trim();
    if (t.isEmpty) return fallbackTitle;
    return 'Because you watched $t';
  }

  /// "14 picks for you"
  static String railSubtitle(int count) =>
      count <= 0 ? 'Nothing new yet' : '$count picks for you';

  static const String fallbackTitle = 'Start anywhere tonight';

  static const String fallbackSubtitle = 'Easy picks to begin with';
}
