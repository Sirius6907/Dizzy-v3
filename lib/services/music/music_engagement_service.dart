import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/music/music_track.dart';
import 'music_mood_filter.dart';
import 'music_onboarding_service.dart';
import 'music_player_controller.dart';
import 'music_service.dart';
import 'music_stats_service.dart';

/// Engagement engine (Round 2 content logic).
///
/// Everything a human would call "learning" lives here: taste ranking,
/// daily mixes, trend rotation and queue auto-extension. The pure core
/// ([MusicEngagementCore]) is deterministic and unit-testable without
/// network, players or singletons; the stateful half is a thin singleton
/// that observes [MusicPlayerController] and records skip / like /
/// replay signals, then uses the same core to build the up-next list
/// and keep the queue alive near its end.
///
/// No fixed fallback song lists anywhere: candidates always come from
/// the seed's own metadata through the provider search surface.
enum MusicTimeBucket { morning, afternoon, evening, lateNight }

/// Normalized taste profile for ranking (artist names, lowercased).
class MusicTasteProfile {
  final Set<String> artistNames;
  const MusicTasteProfile({this.artistNames = const {}});
}

/// The user's derived vibe (Part C, 2026-11-12): onboarding favorite
/// artists + chosen styles + default mood, expressed as `MusicMoodFilter`
/// mood weights. Pure value object — build one with
/// [MusicVibeProfile.fromOnboarding] (or [MusicEngagementCore.vibeProfile]
/// for explicit inputs) and pass it into the mix / rail / radio math.
class MusicVibeProfile {
  /// Favorite artist names, lowercased + trimmed, insertion order kept.
  final Set<String> favoriteArtists;

  /// Human vibe titles for the chosen styles, in pick order
  /// ("Lo-fi Evenings", "Romantic Golden Hour") — never artist names.
  final List<String> styleTitles;

  /// Live search phrases for the chosen styles (India-first queries).
  final List<String> styleQueries;

  final MusicMood defaultMood;

  /// Mood → weight: each chosen style contributes 1.0 to its mapped
  /// mood, the default mood contributes 1.5. `any` never enters here.
  final Map<MusicMood, double> moodWeights;

  /// Stable cache key derived from every preference: any favorites /
  /// styles / mood change produces a different key, so day-cached pools
  /// built on it refresh automatically.
  final String profKey;

  const MusicVibeProfile({
    this.favoriteArtists = const {},
    this.styleTitles = const [],
    this.styleQueries = const [],
    this.defaultMood = MusicMood.any,
    this.moodWeights = const {},
    this.profKey = '',
  });

  /// True when any onboarding signal exists. Users who skipped the
  /// wizard with zero picks have no vibe — every engine then keeps its
  /// pre-vibe behavior exactly.
  bool get hasSignal =>
      favoriteArtists.isNotEmpty ||
      styleTitles.isNotEmpty ||
      defaultMood != MusicMood.any;

  /// Builds the profile from whatever the user currently has picked in
  /// the onboarding service (live notifier values, no IO).
  static MusicVibeProfile fromOnboarding() => MusicEngagementCore.vibeProfile(
    favoriteArtists: MusicOnboardingService.favoriteArtists.value,
    styles: MusicOnboardingService.selectedStyles.value,
    defaultMood: MusicOnboardingService.defaultMood.value,
  );
}

/// One generated daily mix. Titles are human vibe/theme labels
/// ("Lo-fi Evenings", "Midday") — never artist concatenation (Part C).
class MusicDailyMix {
  final String id;
  final String title;
  final String description;
  final List<MusicTrack> tracks;
  const MusicDailyMix({
    required this.id,
    required this.title,
    required this.description,
    required this.tracks,
  });
}

/// Pure, deterministic engagement math. All functions are static and
/// side-effect free so unit tests can exercise them directly.
abstract final class MusicEngagementCore {
  /// Stable per-day integer seed: properties hold across the whole day
  /// and flip when the day flips.
  static int daySeed(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  /// Time-of-day bucket used to re-order home rails and mixes.
  /// <6 late-night, 6–11 morning, 12–16 afternoon, 17–21 evening,
  /// 22+ late-night.
  static MusicTimeBucket timeBucket(DateTime now) {
    final h = now.hour;
    if (h >= 6 && h < 12) return MusicTimeBucket.morning;
    if (h >= 12 && h < 17) return MusicTimeBucket.afternoon;
    if (h >= 17 && h < 22) return MusicTimeBucket.evening;
    return MusicTimeBucket.lateNight;
  }

  static String _norm(String raw) => raw.trim().toLowerCase();

  /// Coarse "language bucket" from text. MusicTrack carries no language
  /// field, so unicode script + desi keywords are the one portable
  /// signal shared by both providers.
  static String languageBucket(String text) {
    final t = text.toLowerCase();
    // Devanagari, Bengali, Gurmukhi, Gujarati, Tamil, Telugu, Kannada.
    final re = RegExp(
      '[\u0900-\u097F\u0980-\u09FF\u0A00-\u0A7F\u0A80-\u0AFF'
      '\u0B00-\u0B7F\u0B80-\u0BFF\u0C00-\u0C7F]',
    );
    if (re.hasMatch(text)) return 'desi-script';
    if (t.contains('bollywood') ||
        t.contains('punjabi') ||
        t.contains('desi') ||
        t.contains('bhakti') ||
        t.contains('ghazal')) {
      return 'desi-keyword';
    }
    return 'latin';
  }

  static double sessionPenalty(Map<String, int> skips, String artist) =>
      min(skips[_norm(artist)] ?? 0, 3) * 25.0;

  // --------------------------- vibe engine (Part C) -----------------------

  /// Favorite-artist accent bonus added on top of mood scoring.
  static const double favoriteArtistBonus = 3.0;

  /// Derives a [MusicVibeProfile] from onboarding inputs. Styles map to
  /// mood weights (1.0 each) via their existing `MusicStyle.mood` field,
  /// the default mood adds 1.5 — so a style the user ALSO chose as their
  /// default mood weighs more, and everything else keeps the plain
  /// `MusicMoodFilter` scoring + duration bands underneath.
  static MusicVibeProfile vibeProfile({
    Iterable<String> favoriteArtists = const [],
    Iterable<MusicStyle> styles = const [],
    MusicMood defaultMood = MusicMood.any,
  }) {
    final weights = <MusicMood, double>{};
    void bump(MusicMood mood, double weight) {
      if (mood == MusicMood.any) return; // e.g. devotional: live search only
      weights[mood] = (weights[mood] ?? 0) + weight;
    }

    final titles = <String>[];
    final queries = <String>[];
    for (final style in styles) {
      bump(style.mood, 1.0);
      titles.add(style.vibeTitle);
      queries.add(style.searchQuery);
    }
    bump(defaultMood, 1.5);

    final favs = <String>{};
    for (final raw in favoriteArtists) {
      final a = raw.trim().toLowerCase();
      if (a.isNotEmpty) favs.add(a);
    }

    final key = [
      'a:${favs.join('\u0001').hashCode}',
      's:${titles.join('\u0001').hashCode}',
      'm:${defaultMood.name}',
    ].join('|');

    return MusicVibeProfile(
      favoriteArtists: favs,
      styleTitles: titles,
      styleQueries: queries,
      defaultMood: defaultMood,
      moodWeights: Map.unmodifiable(weights),
      profKey: key,
    );
  }

  /// Weighted vibe affinity for one track: each mood's `MusicMoodFilter`
  /// score times its weight, plus the favorite-artist bonus. 0 means no
  /// signal either way.
  static double vibeScore(MusicTrack track, MusicVibeProfile vibe) {
    var score = 0.0;
    for (final entry in vibe.moodWeights.entries) {
      score += entry.value * MusicMoodFilter.scoreFor(track, entry.key);
    }
    if (vibe.favoriteArtists.contains(_norm(track.artist))) {
      score += favoriteArtistBonus;
    }
    return score;
  }

  /// The heart of "up next": rank [candidates] for a [seed] track.
  ///
  /// Score components — same artist > same album > same language bucket
  /// > title keyword overlap > taste affinity. Session skips hurt
  /// (repeat offenders drop hard), session positives help. Ties break
  /// deterministically via a [seed]-derived hash, so two runs in one
  /// session agree while the day rotates what lands on top.
  static List<MusicTrack> rankUpNext({
    required MusicTrack seed,
    required List<MusicTrack> candidates,
    MusicTasteProfile? taste,
    Map<String, int>? skips,
    Map<String, int>? boosts,
    required int daySeed,
    int limit = 6,
  }) {
    if (candidates.isEmpty || limit <= 0) return const [];
    final seedLang = languageBucket(
      '${seed.artist} ${seed.title} ${seed.album}',
    );
    final keywordSeed = _keywords(seed.title);
    final ranked =
        candidates.where((t) => t.id != seed.id).map((t) {
          var score = 0.0;
          if (_norm(t.artist).isNotEmpty &&
              _norm(t.artist) == _norm(seed.artist)) {
            score += 30;
          }
          if (t.albumId.isNotEmpty && t.albumId == seed.albumId) {
            score += 15;
          } else if (_norm(seed.album).isNotEmpty &&
              _norm(t.album) == _norm(seed.album)) {
            score += 10;
          }
          if (languageBucket('${t.artist} ${t.title}') == seedLang) {
            score += 8;
          }
          score += _keywordOverlap(keywords: keywordSeed, title: t.title) * 5.0;
          final tasteNames = taste?.artistNames ?? const {};
          if (_norm(t.artist).isNotEmpty &&
              tasteNames.contains(_norm(t.artist))) {
            score += 12;
          }
          score -= sessionPenalty(skips ?? const {}, t.artist);
          score += min(boosts?[_norm(t.artist)] ?? 0, 2) * 6.0;
          score += _hash('${seed.id}_${t.id}_$daySeed') * 0.01;
          return MapEntry(t, score);
        }).toList()..sort((a, b) {
          final c = b.value.compareTo(a.value);
          if (c != 0) return c;
          return _norm(a.key.id).compareTo(_norm(b.key.id));
        });
    return ranked.take(limit).map((e) => e.key).toList();
  }

  static List<String> _keywords(String text) => text
      .toLowerCase()
      .split(RegExp(r'[\s\-\(\)\[\],\.]'))
      .where((w) => w.length >= 3)
      .toList();

  static int _keywordOverlap({
    required List<String> keywords,
    required String title,
  }) {
    final t = title.toLowerCase();
    var n = 0;
    for (final k in keywords) {
      if (t.contains(k)) n++;
    }
    return n;
  }

  /// Small deterministic hash in [0,1000).
  static int _hash(String input) {
    var h = input.hashCode;
    if (h.isNegative) h = -h;
    return h % 1000;
  }

  /// Rotates a list window by day seed — the same source list reads
  /// differently today than tomorrow without any new network call.
  static List<T> rotateRail<T>(
    List<T> items, {
    required int daySeed,
    int take = 10,
  }) {
    if (items.length <= take) return items;
    final start = _hash('$daySeed') % items.length;
    final window = items.sublist(start, min(start + take, items.length));
    if (window.length < take) {
      window.addAll(items.take(take - window.length));
    }
    return window;
  }

  /// Queue auto-extension policy: refill when fewer than 3 tracks are
  /// queued ahead. Cheap, predictable, testable.
  static bool shouldExtendQueue(int upcomingCount) => upcomingCount < 3;

  // -------------------------------------------------------------------------
  // India-first rail helpers (2026-11-12)
  // -------------------------------------------------------------------------

  /// Groups live trending tracks into album cards. Deezer's editorial
  /// rails follow the proxy's exit IP (French rap on an India-first app),
  /// so the albums row is now derived from JioSaavn trending instead —
  /// same trick the artists row already uses. Order = first seen, same
  /// album name folds into the card it opened.
  static List<MusicAlbum> albumCardsFromTracks(
    List<MusicTrack> tracks, {
    int cap = 14,
  }) {
    final out = <MusicAlbum>[];
    final byAlbum = <String, List<MusicTrack>>{};
    final order = <String>[];
    for (final t in tracks) {
      final name = t.album.trim();
      if (name.isEmpty) continue;
      final bucket = byAlbum.putIfAbsent(name, () {
        order.add(name);
        return <MusicTrack>[];
      });
      bucket.add(t);
    }
    for (final name in order) {
      if (out.length >= cap) break;
      final group = byAlbum[name]!;
      final first = group.first;
      out.add(
        MusicAlbum(
          id: 'saavn_album_$name',
          title: name,
          artistName: first.artist,
          coverUrl: first.coverUrl,
          trackCount: group.length,
          tracks: group,
        ),
      );
    }
    return out;
  }

  /// One vibe-station playlist card from a live search result. Null when
  /// the search came back thin or coverless — the caller then shows one
  /// fewer station instead of a broken card.
  static MusicPlaylist? stationPlaylist({
    required String id,
    required String title,
    required List<MusicTrack> tracks,
    int minTracks = 6,
  }) {
    final clean = tracks
        .where((t) => t.id.isNotEmpty && t.title.isNotEmpty)
        .toList();
    if (clean.length < minTracks) return null;
    final cover = clean
        .map((t) => t.coverUrl)
        .firstWhere((c) => c.isNotEmpty, orElse: () => '');
    if (cover.isEmpty) return null;
    return MusicPlaylist(
      id: id,
      title: title,
      description: '${clean.length} tracks · refreshed daily',
      coverUrl: cover,
      trackCount: clean.length,
      creatorName: 'Dizzy',
      tracks: clean,
    );
  }

  // -------------------------------------------------------------------------
  // Daily mixes
  // -------------------------------------------------------------------------

  /// Builds 4–6 daily mixes from [pool], date-seeded so the composition
  /// reshuffles across days, sized so a fresh install sees 30+ tracks
  /// in total and scales past 100 with a big pool.
  ///
  /// Titles derive from the dominant artists of each mix; when the pool
  /// is too small nothing is fabricated — the result is an empty list
  /// (caller surfaces simply hide the rail).
  static List<MusicDailyMix> generateDailyMixes({
    required List<MusicTrack> pool,
    required DateTime date,
    MusicTimeBucket timeBucket = MusicTimeBucket.afternoon,
    MusicVibeProfile? vibe,
    List<MusicTrack> favoriteTracks = const [],
  }) {
    final seen = <String, MusicTrack>{};
    for (final t in pool) {
      seen.putIfAbsent(t.id, () => t);
    }
    final unique = seen.values.toList();
    if (unique.length < 8) return const [];

    // Part C: vibe-seeded ordering. With a signal, the pool leans toward
    // the user's vibe (favorite artists + weighted mood scores, index-
    // stable so it stays deterministic). No signal → legacy order.
    final vibeLive = (vibe != null && vibe.hasSignal) ? vibe : null;
    if (vibeLive != null) {
      final ranked = List.generate(
        unique.length,
        (i) => (i, vibeScore(unique[i], vibeLive)),
      );
      ranked.sort((a, b) {
        final byScore = b.$2.compareTo(a.$2);
        return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
      });
      unique.setAll(0, [for (final r in ranked) unique[r.$1]]);
    }

    final seed = daySeed(date) + unique.length;
    final mixCount = unique.length >= 120 ? 6 : 4;
    final perMixTarget = (unique.length ~/ mixCount).clamp(8, 25).toInt();

    // Rotate the pool by a day-seeded offset so mix composition changes
    // day to day even when the chart cache is warm.
    final offset = seed % unique.length;
    final rotated = [...unique.sublist(offset), ...unique.take(offset)];

    // Favorite accents (~1 in 4): favorites that are actually inside the
    // pool claim every 4th slot of each mix, in a day-rotated order —
    // the user's own artists visibly lead without inventing tracks.
    final favSource = <MusicTrack>[];
    final favSeen = <String>{};
    for (final t in favoriteTracks) {
      if (favSeen.add(t.id) && seen.containsKey(t.id)) favSource.add(t);
    }
    var favIdx = 0;
    final favRotated = favSource.isEmpty
        ? favSource
        : [
            ...favSource.sublist(seed % favSource.length),
            ...favSource.take(seed % favSource.length),
          ];

    // Time-of-day theme — generic labels, not content titles; the title
    // itself gets the mix's own artists in front.
    final themes = switch (timeBucket) {
      MusicTimeBucket.morning => [
        'Sunrise',
        'Focus',
        'Fresh',
        'Feel-Good',
        'Brain',
        'Wake',
      ],
      MusicTimeBucket.afternoon => [
        'Midday',
        'Workday',
        'Easy',
        'Pump',
        'Deep',
        'Radar',
      ],
      MusicTimeBucket.evening => [
        'Golden Hour',
        'Party',
        'Drive',
        'Wind Down',
        'Heat',
        'Bloom',
      ],
      MusicTimeBucket.lateNight => [
        'Night',
        'Slow',
        'Midnight',
        'Silent',
        'Low-Light',
        'Dream',
      ],
    };

    // Part C: human titles, theme-only — NEVER artist concatenation.
    // Vibe users get their own style titles, day-rotated; everyone else
    // keeps the time-of-day themes.
    final List<String> titleThemes;
    if (vibeLive != null && vibeLive.styleTitles.isNotEmpty) {
      final st = vibeLive.styleTitles;
      final tStart = seed % st.length;
      titleThemes = [...st.sublist(tStart), ...st.take(tStart)];
    } else {
      titleThemes = themes;
    }
    final titleCounts = <String, int>{};
    String titleFor(String theme) {
      final n = titleCounts[theme] ?? 0;
      titleCounts[theme] = n + 1;
      return n == 0 ? theme : '$theme Vol. ${n + 1}';
    }

    final mixes = <MusicDailyMix>[];
    final used = <String>{};
    for (var i = 0; i < mixCount; i++) {
      final slice = <MusicTrack>[];
      // Staggered walk with per-mix start offsets keeps slices distinct
      // without any hardcoded indices. Every 4th slot prefers an unused
      // favorite when one exists (accent, ~1-in-4 density).
      var start = i * perMixTarget ~/ 2;
      while (slice.length < perMixTarget &&
          start < rotated.length + rotated.length) {
        MusicTrack? pick;
        if (slice.length % 4 == 3 && favIdx < favRotated.length) {
          while (favIdx < favRotated.length) {
            final f = favRotated[favIdx++];
            if (!used.contains(f.id)) {
              pick = f;
              break;
            }
          }
        }
        if (pick == null) {
          pick = rotated[start % rotated.length];
          start++;
        }
        if (used.contains(pick.id)) continue;
        slice.add(pick);
        used.add(pick.id);
      }
      if (slice.isEmpty) continue;

      final artists = <String>[];
      for (final t in slice) {
        final a = t.artist.trim();
        if (a.isNotEmpty && !artists.contains(a)) artists.add(a);
      }
      final vibeTitled = vibeLive != null && vibeLive.styleTitles.isNotEmpty;
      mixes.add(
        MusicDailyMix(
          id: 'daily_mix_d${daySeed(date)}_$i',
          title: titleFor(titleThemes[i % titleThemes.length]),
          description: vibeTitled
              ? (artists.length > 1
                    ? '${artists.length} artists · your vibe, refreshed daily'
                    : 'Your vibe, refreshed daily')
              : (artists.length > 1
                    ? '${artists.length} artists · refreshed daily'
                    : 'A blend refreshed daily'),
          tracks: slice,
        ),
      );
    }
    return mixes;
  }

  /// Home-rail ordering per time bucket: late-night puts mellow first,
  /// evening puts energy first. Pure so a test can assert the order.
  static List<MusicMood> moodOrder(MusicTimeBucket bucket) => switch (bucket) {
    MusicTimeBucket.morning => [
      MusicMood.focus,
      MusicMood.happy,
      MusicMood.energetic,
      MusicMood.chill,
      MusicMood.romance,
      MusicMood.night,
    ],
    MusicTimeBucket.afternoon => [
      MusicMood.happy,
      MusicMood.energetic,
      MusicMood.focus,
      MusicMood.chill,
      MusicMood.romance,
      MusicMood.night,
    ],
    MusicTimeBucket.evening => [
      MusicMood.energetic,
      MusicMood.happy,
      MusicMood.romance,
      MusicMood.chill,
      MusicMood.focus,
      MusicMood.night,
    ],
    MusicTimeBucket.lateNight => [
      MusicMood.chill,
      MusicMood.night,
      MusicMood.focus,
      MusicMood.romance,
      MusicMood.happy,
      MusicMood.energetic,
    ],
  };
}

/// Stateful half: records session signals and drives auto-extension.
class MusicEngagementService extends ChangeNotifier {
  MusicEngagementService._();
  static final MusicEngagementService instance = MusicEngagementService._();

  final Map<String, int> _skipsByArtist = {};
  final Map<String, int> _boostsByArtist = {};
  final Map<String, DateTime> _lastExtensionAt = {};
  String? _lastTrackId;
  DateTime? _lastNotifyAt;
  bool _extensionInFlight = false;
  bool _started = false;
  Timer? _debounce;
  int _lastPositionSeconds = 0;

  static String _norm(String raw) => raw.trim().toLowerCase();

  // ------------------------- session signals ------------------------------

  void recordSkip(MusicTrack track) {
    final key = _norm(track.artist);
    if (key.isEmpty) return;
    _skipsByArtist[key] = min((_skipsByArtist[key] ?? 0) + 1, 5);
    _boostsByArtist.remove(key);
  }

  void recordPositive(MusicTrack track) {
    final key = _norm(track.artist);
    if (key.isEmpty) return;
    _boostsByArtist[key] = min((_boostsByArtist[key] ?? 0) + 1, 5);
    _skipsByArtist.remove(key);
  }

  void cancelAffinity(MusicTrack track) {
    final key = _norm(track.artist);
    _skipsByArtist.remove(key);
    _boostsByArtist.remove(key);
  }

  // ------------------------------ up-next ---------------------------------

  /// Test seam: replaces the provider search for candidate sourcing so
  /// next-up steering can be tested offline. Null in production —
  /// candidates always come from [seed]'s own metadata via search.
  @visibleForTesting
  Future<List<MusicTrack>> Function(String query)? candidateSeam;

  /// Candidates always come from [seed]'s own metadata (artist + title
  /// keywords) through the provider search surface — zero fixed
  /// fallback lists. Empty network → empty rail (the surface hides it).
  Future<List<MusicTrack>> nextUpForPlaying({
    required MusicTrack seed,
    required List<MusicTrack> exclude,
    required DateTime now,
    int limit = 6,
  }) async {
    final excludeIds = exclude.map((t) => t.id).toSet();
    final candidates = <MusicTrack>[];
    final seen = <String>{};

    void addAll(List<MusicTrack> list) {
      for (final t in list) {
        if (t.id.isNotEmpty &&
            t.id != seed.id &&
            !excludeIds.contains(t.id) &&
            seen.add(t.id)) {
          candidates.add(t);
        }
      }
    }

    try {
      final artist = seed.artist.trim();
      if (artist.isNotEmpty) {
        try {
          addAll(
            candidateSeam != null
                ? await candidateSeam!(artist)
                : await MusicService.instance.searchTracks(artist),
          );
        } catch (_) {}
      }
      final titleKey = seed.title.split(RegExp(r'[\(\[\-–]')).first.trim();
      if (titleKey.isNotEmpty && titleKey != seed.title) {
        try {
          addAll(
            candidateSeam != null
                ? await candidateSeam!(titleKey)
                : await MusicService.instance.searchTracks(titleKey),
          );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[MusicEngagement] candidate fetch failed: $e');
    }

    final taste = MusicTasteProfile(
      artistNames: MusicStatsService.instance.topArtists
          .take(10)
          .map((e) => _norm(e.key))
          .toSet(),
    );

    return MusicEngagementCore.rankUpNext(
      seed: seed,
      candidates: candidates,
      taste: taste,
      skips: Map.of(_skipsByArtist),
      boosts: Map.of(_boostsByArtist),
      daySeed: MusicEngagementCore.daySeed(now),
      limit: limit,
    );
  }

  // ----------------------- queue auto-extension ---------------------------

  /// Call once from the music page initState. Attaches the listener
  /// that detects track transitions (skip vs full play) and refills
  /// the queue toward its end without touching the player contract.
  void ensureStarted() {
    if (_started) return;
    _started = true;
    _lastTrackId = MusicPlayerController.instance.currentTrack?.id;
    MusicPlayerController.instance.addListener(_onPlayerChanged);
  }

  void _onPlayerChanged() {
    final now = DateTime.now();
    _lastPositionSeconds = MusicPlayerController.instance.position.inSeconds;

    // The controller notifies during load churn; debounce the engine.
    _debounce?.cancel();
    final last = _lastNotifyAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 200)) {
      _debounce = Timer(const Duration(milliseconds: 250), () {
        _lastNotifyAt = DateTime.now();
        _tick();
        return;
      });
      return;
    }
    _lastNotifyAt = now;
    _tick();
  }

  void _tick() {
    final controller = MusicPlayerController.instance;
    final current = controller.currentTrack;

    // Skip / full-play detection on transition: the just-ended track is
    // the newest history entry; where it ended decides the signal.
    if (_lastTrackId != null && current != null && current.id != _lastTrackId) {
      final history = controller.historyTracks;
      if (history.isNotEmpty) {
        final prev = history.last;
        if (prev.id == _lastTrackId) {
          final dur = prev.durationSeconds;
          if (dur > 0) {
            if (_lastPositionSeconds < dur * 0.25) {
              recordSkip(prev);
            } else {
              recordPositive(prev);
            }
          }
        }
      }
    }
    _lastTrackId = current?.id;

    unawaited(_maybeAutoExtend(DateTime.now()));
    notifyListeners();
  }

  Future<void> _maybeAutoExtend(DateTime now) async {
    if (_extensionInFlight) return;
    final controller = MusicPlayerController.instance;
    final current = controller.currentTrack;
    if (current == null) return;
    if (!MusicEngagementCore.shouldExtendQueue(
      controller.upcomingTracks.length,
    )) {
      return;
    }
    final lastForSeed = _lastExtensionAt[_norm(current.id)];
    if (lastForSeed != null &&
        now.difference(lastForSeed) < const Duration(seconds: 20)) {
      return;
    }
    _extensionInFlight = true;
    _lastExtensionAt[_norm(current.id)] = now;
    try {
      final exclude = [
        current,
        ...controller.upcomingTracks,
        ...controller.historyTracks,
      ];
      final picks = await nextUpForPlaying(
        seed: current,
        exclude: exclude,
        now: now,
        limit: 5,
      );
      for (final t in picks) {
        // Stop once the queue is healthy again.
        if (MusicPlayerController.instance.upcomingTracks.length >= 6) break;
        MusicPlayerController.instance.addTrackToQueue(t);
      }
    } catch (e) {
      debugPrint('[MusicEngagement] auto-extend failed: $e');
    } finally {
      _extensionInFlight = false;
      notifyListeners();
    }
  }

  // ------------------------------ tests -----------------------------------

  /// Test seam: zero out every session signal. Call from engagement
  /// test setUp.
  void resetSessionForTest() {
    _skipsByArtist.clear();
    _boostsByArtist.clear();
    _lastExtensionAt.clear();
    _lastTrackId = null;
    _lastNotifyAt = null;
    _extensionInFlight = false;
  }
}
