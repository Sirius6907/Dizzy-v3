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
///
/// Debugging a ranking decision: call [explain] — it returns every additive
/// component of [score] by name, so "why did this source win" is answerable
/// without re-deriving the arithmetic.
class SourceRanker {
  /// The providers the owner verified live against the real upstream
  /// (2026-11-16 probe): RiveStream and FlaxMovies both answer with
  /// playable HLS. They lead every list and every failover chain.
  static const Set<String> promotedProviders = {'rivestream', 'flaxmovies'};

  /// True when this source comes from a promoted provider.
  static bool isPromoted(StreamSource s) =>
      promotedProviders.contains(s.addonName.trim().toLowerCase());

  /// A torrent source in the app's sense: it carries an infoHash and no
  /// direct URL, so playback must go through TorrServer.
  ///
  /// This predicate is the single definition — [tierOf], [score] and
  /// [buildFailoverChain] all branch on it, so a torrent is classified the
  /// same way everywhere. (Earlier this exact condition was duplicated three
  /// times; one copy drifting would have silently mis-tiered a source.)
  static bool isTorrent(StreamSource s) =>
      s.infoHash != null &&
      s.infoHash!.isNotEmpty &&
      (s.url ?? '').isEmpty;

  /// Ordering tier, lowest first:
  /// promoted HTTP → other HTTP → embed → torrent.
  ///
  /// A torrent is last because it needs metadata + peers before the first
  /// byte; an embed is behind a direct link because it costs a page load.
  static int tierOf(StreamSource s) {
    if (isPromoted(s)) return 0;
    if (s.isEmbedSource) return 2;
    if (isTorrent(s)) return 3;
    return 1;
  }

  static const int _wAddonHistory = 40;
  static const int _wDebrid = 25;
  static const int _wHttpDirect = 20;
  static const int _wSeeders = 15;
  static const int _wResolution = 10;
  static const int _wPreferredLang = 5;

  /// Hindi-mode language boost (v1.1.9): beats addon history (+40) so Hindi
  /// mode actually plays Hindi. English mode keeps the small baseline boost.
  static const int _wPreferredLangHindi = 45;
  static const int _penaltyRecentFailure = 30;

  /// A torrent is a fallback tier: it has to gather metadata and peers
  /// before the first byte, a direct HTTP stream does not.
  static const int _penaltyTorrentTier = 12;

  /// P9: rendition-bearing sources decode to something playable far more
  /// often (ladder to step down) — prefer them at rank time.
  static const int _wRenditions = 15;

  /// HEVC/AV1 in a 1080p+ file is heavy to decode in software (stutter on
  /// phones and the emulator) and huge to fetch from a cold swarm.
  static const int _penaltyHeavyCodec = 12;
  static const int _penaltyLargeFile = 10;
  static const int _bonusSmallFile = 8;

  /// File-size landmarks for instant-play scoring — a whole file the device
  /// must fetch/decode, not an adaptive ladder. 2 GB+ = minutes before the
  /// first byte on a weak swarm; under ~700 MB starts fast.
  static const int _sizeTwoGb = 2 * 1024 * 1024 * 1024;
  static const int _sizeOneGb = 1 * 1024 * 1024 * 1024;
  static const int _sizeSevenHundredMb = 700 * 1024 * 1024;

  /// Precompiled once — [score] runs per source per scrape, and the app
  /// re-scores on every failover step.
  static final RegExp _reHeavyCodec = RegExp(r'\b(hevc|h\.?265|x265)\b');
  static final RegExp _reAv1 = RegExp(r'\bav1\b');
  static final RegExp _reAdaptiveLabel = RegExp(r'\b(hls|dash)\b');
  static final RegExp _reSeeders = RegExp(
    r'(\d[\d,]*)\s*seeders?',
    caseSensitive: false,
  );

  /// Stable identity for a source across retries/scrapes.
  /// addon + url/infoHash is enough to recognize "the same stream" — plus the
  /// file index for torrents, because one torrent offers several files and
  /// they are NOT interchangeable (a 480p file and a 1080p file of the same
  /// infohash are different streams).
  static String fingerprint(StreamSource s) {
    final id = s.url ?? s.infoHash ?? s.externalUrl ?? s.title ?? '';
    final file = s.fileIdx != null ? '#${s.fileIdx}' : '';
    return '${s.addonName}::$id$file';
  }

  /// The additive parts of [score], by component name. `score` is exactly
  /// the sum of these values — one source of truth, no drift.
  static Map<String, int> explain(StreamSource s, RankerContext ctx) {
    final breakdown = <String, int>{};

    // 1. Addon that worked before for this title's history.
    breakdown['addonHistory'] = ctx.lastGoodByAddon.containsKey(s.addonName)
        ? _wAddonHistory
        : 0;

    // 2. Debrid direct streams (Torbox etc.) — fastest + most reliable.
    final url = (s.url ?? '').toLowerCase();
    final name = (s.name ?? s.title ?? '').toLowerCase();
    final isDebrid =
        url.contains('torbox') ||
        url.contains('debrid') ||
        url.contains('real-debrid') ||
        url.contains('premiumize') ||
        name.contains('debrid') ||
        name.contains('torbox');
    breakdown['debrid'] = isDebrid ? _wDebrid : 0;

    // 3. Plain HTTP direct stream beats torrents.
    breakdown['httpDirect'] =
        (s.url != null && s.url!.isNotEmpty && s.infoHash == null)
        ? _wHttpDirect
        : 0;

    // 3b. A torrent needs a swarm, a direct HTTP stream does not. Without
    // this, a cold torrent with many seeders outranked a source that was
    // probed alive and could start playing immediately.
    breakdown['torrentTier'] = isTorrent(s) ? -_penaltyTorrentTier : 0;

    // 4. Seeder count, log-scaled 0.._wSeeders (1000+ = full weight).
    final seeders = _parseSeeders(s);
    breakdown['seeders'] = seeders == null
        ? 0
        : (_wSeeders * (_log2(seeders + 1) / _log2(1001)))
              .clamp(0, _wSeeders)
              .round();

    // 5. Resolution hint in name/description.
    breakdown['resolution'] = _resolutionScore(s);

    // 6. Audio language match (mode-aware: hindi boost beats history).
    final langMatch =
        ctx.preferredLang != null && _langMatches(s, ctx.preferredLang!);
    breakdown['preferredLang'] = !langMatch
        ? 0
        : (ctx.preferredLang!.toLowerCase() == 'hindi'
              ? _wPreferredLangHindi
              : _wPreferredLang);

    // 7. Failed this session — sink hard.
    breakdown['recentFailure'] = ctx.failedThisSession.contains(fingerprint(s))
        ? -_penaltyRecentFailure
        : 0;

    // 8. P9: renditions known → always something playable.
    breakdown['renditions'] = s.renditions.isNotEmpty ? _wRenditions : 0;

    // 9. Instant-play friendliness: a file the device can decode without
    //    stutter, and that a weak swarm can deliver fast, beats a heavier
    //    file that starts minutes later — or never.
    breakdown['instantPlay'] = _instantPlayScore(s);

    return breakdown;
  }

  /// Total rank score for [s] — the sum of [explain]'s components.
  static int score(StreamSource s, RankerContext ctx) {
    var total = 0;
    for (final value in explain(s, ctx).values) {
      total += value;
    }
    return total;
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

  /// The failover chain: ranked best-first, without the sources the liveness
  /// probe already proved dead. Switching to a known-dead source is what
  /// produced a black screen instead of the next working source.
  ///
  /// Direct HTTP links come before torrents: a torrent has to gather
  /// metadata and peers (tens of seconds), a direct link can start right
  /// away.
  static List<StreamSource> buildFailoverChain(
    Iterable<StreamSource> sources,
    RankerContext ctx,
  ) {
    final alive = <StreamSource>[];
    final embeds = <StreamSource>[];
    final torrents = <StreamSource>[];
    for (final source in sources) {
      if (source.probeDead) continue;
      // v1.3.5 tiers: verified direct HTTP → embed webview → torrents. An
      // embed costs a page load before any video appears, so it must never
      // beat a direct link; a torrent costs metadata + peers, so it stays
      // behind both.
      if (source.isEmbedSource) {
        embeds.add(source);
        continue;
      }
      if (isTorrent(source)) {
        torrents.add(source);
      } else {
        alive.add(source);
      }
    }
    // The promoted pair leads every tier: they are the only providers the
    // owner verified live, and they answer with playable HLS.
    final promoted = alive.where(isPromoted).toList();
    final rest = alive.where((s) => !isPromoted(s)).toList();
    return [
      ...order(promoted, ctx),
      ...order(rest, ctx),
      ...order(embeds, ctx),
      ...order(torrents, ctx),
    ];
  }

  // ── helpers ────────────────────────────────────────────────────────

  /// All the free text a source offers, lower-cased — one canonical string
  /// for pattern matching (codec, resolution, seeders, language). Every
  /// scoring component reads from this so a hint expressed in any field
  /// counts the same way everywhere.
  static String _searchableText(StreamSource s) =>
      '${s.name ?? ''} ${s.description ?? ''} ${s.title ?? ''}'.toLowerCase();

  static double _log2(num x) {
    if (x <= 1) return 0;
    return math.log(x.toDouble()) / math.ln2;
  }

  static int? _parseSeeders(StreamSource s) {
    // Common patterns: " Tracker: 1,234 seeders", "S: 123"
    final m = _reSeeders.firstMatch(_searchableText(s));
    if (m == null) return null;
    return int.tryParse(m.group(1)!.replaceAll(',', ''));
  }

  static int _resolutionScore(StreamSource s) {
    final text = _searchableText(s);
    if (text.contains('2160') || text.contains('4k')) return _wResolution;
    if (text.contains('1080')) return 8;
    if (text.contains('720')) return 5;
    return 0;
  }

  static bool _langMatches(StreamSource s, String lang) =>
      _searchableText(s).contains(lang.toLowerCase());

  static int _instantPlayScore(StreamSource s) {
    final text = _searchableText(s);
    var score = 0;
    if (_reHeavyCodec.hasMatch(text)) score -= _penaltyHeavyCodec;
    if (_reAv1.hasMatch(text)) score -= _penaltyHeavyCodec;
    // HLS/DASH sources: their size text is an aggregate ladder estimate, not
    // one file the device must fetch whole — an adaptive stream starts
    // playing instantly no matter how big it is. Size penalties/bonuses were
    // designed for torrent/file downloads, so they only apply there.
    final urlLower = (s.url ?? '').toLowerCase();
    final isAdaptiveStream =
        urlLower.contains('.m3u8') ||
        urlLower.contains('.mpd') ||
        _reAdaptiveLabel.hasMatch(text);
    final bytes = s.sizeBytes;
    if (bytes != null && !isAdaptiveStream) {
      if (bytes > _sizeTwoGb) {
        score -= _penaltyLargeFile;
      } else if (bytes > _sizeOneGb) {
        score -= _penaltyLargeFile ~/ 2;
      } else if (bytes < _sizeSevenHundredMb) {
        score += _bonusSmallFile;
      }
    }
    return score;
  }
}
