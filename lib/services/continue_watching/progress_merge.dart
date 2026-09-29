/// F3 — the one rule that decides who wins when two devices disagree.
///
/// Pure functions, no storage, no platform calls — so the answer is unit
/// tested and the sync code just asks.
///
/// Conflict rule (this is the promise we make to the user):
///
///  **Max progress wins. Progress never goes backwards.**
///
/// A phone that is ahead (you watched on the train) always keeps its spot.
/// A phone that is behind (an old tablet that has been asleep for a month)
/// can add things, but it can never drag you back to where it was. Losing
/// twenty minutes of a series because you opened an old device is the kind
/// of bug that makes people stop trusting a product, so it cannot happen here.
///
/// The only other thing we carry across is metadata: a later `lastWatchedAt`
/// wins the title/poster/source fields, because that device has the fresher
/// copy of the information. Progress itself is decided by the max rule above
/// and never by the timestamp.
library;

/// A single resume point, flattened out of [ContinueWatchingItem] so this
/// file stays free of Flutter and of the player model.
class MediaProgress {
  /// `profileId` + `mediaId` — the key a progress row belongs to.
  final String key;

  /// Seconds watched from the start of the media.
  final int positionSeconds;

  /// Full length in seconds. `0` when unknown.
  final int totalDurationSeconds;

  /// When this device last touched the media.
  final DateTime lastWatchedAt;

  /// Everything else we want to keep (title, poster, episode numbers…).
  final Map<String, dynamic> meta;

  const MediaProgress({
    required this.key,
    required this.positionSeconds,
    required this.totalDurationSeconds,
    required this.lastWatchedAt,
    this.meta = const {},
  });

  /// Composite key for [forProfile].
  static String forProfile(String profileId, String mediaId) =>
      '$profileId::$mediaId';

  /// Split a composite key back into `(profileId, mediaId)`.
  ///
  /// Returns `null` for a key that was never built by [forProfile] — a
  /// corrupt row is dropped by the caller instead of poisoning a profile.
  static (String, String)? splitKey(String key) {
    final at = key.indexOf('::');
    if (at <= 0) return null;
    final profileId = key.substring(0, at);
    final mediaId = key.substring(at + 2);
    if (profileId.isEmpty || mediaId.isEmpty) return null;
    return (profileId, mediaId);
  }

  /// Watched fraction, clamped to `0.0..1.0`. `0.0` when the length is
  /// unknown, so an unknown-length item is never shown as finished.
  double get fraction {
    if (totalDurationSeconds <= 0) return 0.0;
    final f = positionSeconds / totalDurationSeconds;
    return f.clamp(0.0, 1.0);
  }

  /// The whole content is done (90% or more).
  bool get isFinished => fraction >= 0.9;

  MediaProgress copyWith({
    int? positionSeconds,
    int? totalDurationSeconds,
    DateTime? lastWatchedAt,
    Map<String, dynamic>? meta,
  }) =>
      MediaProgress(
        key: key,
        positionSeconds: positionSeconds ?? this.positionSeconds,
        totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
        lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
        meta: meta ?? this.meta,
      );
}

/// What a merge did, so the UI can say something true and the tests can
/// assert on behaviour instead of on a diff.
class ProgressMergeReport {
  /// Rows that only one side had — these are the rows a device gained.
  final int added;

  /// Rows both sides had, but the winning position came from the other
  /// side (this device was behind).
  final int advanced;

  /// Rows both sides had and this device was already at or ahead of.
  final int kept;

  const ProgressMergeReport({
    this.added = 0,
    this.advanced = 0,
    this.kept = 0,
  });

  /// Rows the incoming side spoke about: added + advanced + kept.
  ///
  /// A row that lived only on this device is NOT counted — nothing
  /// happened to it, so it must not inflate the "came back with you"
  /// number a person reads.
  int get total => added + advanced + kept;

  ProgressMergeReport operator +(ProgressMergeReport other) =>
      ProgressMergeReport(
        added: added + other.added,
        advanced: advanced + other.advanced,
        kept: kept + other.kept,
      );

  @override
  String toString() =>
      'ProgressMergeReport(added: $added, advanced: $advanced, kept: $kept)';
}

/// Merges two progress maps. The winner of every row is decided here.
abstract final class ProgressMerge {
  /// Fraction at (or above) which a title counts as finished and stops
  /// competing: a finished row is never replaced by a shorter one.
  static const double finishedThreshold = 0.9;

  /// Max rows kept per merge, so a runaway device cannot grow storage
  /// without bound. Oldest-untouched rows fall off first.
  static const int maxRows = 500;

  /// One row, two devices. Returns the row that must survive.
  ///
  /// Order of the arguments does not matter — the rule is symmetric.
  static MediaProgress resolve(MediaProgress a, MediaProgress b) {
    // An unreadable key is never a winner; the store drops it upstream.
    if (MediaProgress.splitKey(a.key) == null) return b;
    if (MediaProgress.splitKey(b.key) == null) return a;

    final posA = a.positionSeconds < 0 ? 0 : a.positionSeconds;
    final posB = b.positionSeconds < 0 ? 0 : b.positionSeconds;

    // Max progress wins — the heart of the rule.
    final winner = posA >= posB ? a : b;
    final loser = posA >= posB ? b : a;

    final pos = posA >= posB ? posA : posB;
    // Keep the better length: a known duration beats an unknown one, and
    // otherwise the longer runtime is the safer denominator.
    final total = _betterDuration(winner, loser);
    // Newer metadata wins, progress does not.
    final metaSource = a.lastWatchedAt.isAfter(b.lastWatchedAt) ? a : b;
    final seenAt =
        a.lastWatchedAt.isAfter(b.lastWatchedAt) ? a.lastWatchedAt : b.lastWatchedAt;

    return MediaProgress(
      key: winner.key,
      positionSeconds: pos,
      totalDurationSeconds: total,
      lastWatchedAt: seenAt,
      meta: metaSource.meta.isEmpty ? winner.meta : metaSource.meta,
    );
  }

  static int _betterDuration(MediaProgress a, MediaProgress b) {
    if (a.totalDurationSeconds > 0 && b.totalDurationSeconds > 0) {
      return a.totalDurationSeconds > b.totalDurationSeconds
          ? a.totalDurationSeconds
          : b.totalDurationSeconds;
    }
    return a.totalDurationSeconds > 0 ? a.totalDurationSeconds : b.totalDurationSeconds;
  }

  /// Merge [incoming] (usually the cloud / the other device) into [local].
  ///
  /// Never overwrites: a key present on both sides becomes the resolved
  /// row, and a key present on one side is kept as-is. Returns the new
  /// map plus a [ProgressMergeReport] for the "we brought X back" line.
  static (Map<String, MediaProgress>, ProgressMergeReport) merge(
    Map<String, MediaProgress> local,
    Map<String, MediaProgress> incoming,
  ) {
    var added = 0;
    var advanced = 0;
    var kept = 0;

    final out = <String, MediaProgress>{};
    out.addAll(local);

    for (final entry in incoming.entries) {
      final key = entry.key;
      final remote = entry.value;
      final mine = local[key];

      // A row that disagrees with its own key is corrupt on one of the two
      // sides. Keep whichever side is readable and say nothing changed.
      if (remote.key != key) {
        if (mine != null && mine.key == key) kept++;
        continue;
      }
      if (mine == null) {
        out[key] = remote;
        added++;
        continue;
      }
      if (mine.key != key) continue;
      final winner = resolve(mine, remote);
      if (winner.positionSeconds > mine.positionSeconds) {
        advanced++;
      } else {
        kept++;
      }
      out[key] = winner;
    }

    return (_cap(out), ProgressMergeReport(added: added, advanced: advanced, kept: kept));
  }

  /// Union of two maps, same max rule, no report (for "add everything"
  /// paths that only need the result).
  static Map<String, MediaProgress> union(
    Map<String, MediaProgress> a,
    Map<String, MediaProgress> b,
  ) =>
      merge(a, b).$1;

  /// Keep the most recently touched [maxRows]. Ties fall back to the key so
  /// the cut is stable across devices.
  static Map<String, MediaProgress> _cap(Map<String, MediaProgress> rows) {
    if (rows.length <= maxRows) return rows;
    final sorted = rows.values.toList()
      ..sort((x, y) {
        final byTime = y.lastWatchedAt.compareTo(x.lastWatchedAt);
        return byTime != 0 ? byTime : x.key.compareTo(y.key);
      });
    return {for (final r in sorted.take(maxRows)) r.key: r};
  }

  /// Rows for one profile, freshest first. A corrupt row is skipped, not
  /// thrown on — one bad row must never hide a whole profile.
  static List<MediaProgress> forProfile(
    Map<String, MediaProgress> rows,
    String profileId,
  ) {
    final out = <MediaProgress>[];
    for (final row in rows.values) {
      final split = MediaProgress.splitKey(row.key);
      if (split == null) continue;
      if (split.$1 != profileId) continue;
      out.add(row);
    }
    out.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return out;
  }
}
