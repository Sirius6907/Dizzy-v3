import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/nav_key.dart';
import '../../design/dizzy_tactile.dart';
import '../../models/movie/movie_detail.dart';
import '../../models/movie/video.dart';
import '../../pages/player/watch_screen.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/tactile/dizzy_7segment.dart';
import '../cloud/watch_party_service.dart';
import '../errors/app_error_log.dart';
import '../metadata/metadata_service.dart';
import '../scraper/sites/tmdb_helper.dart';
import 'party_playback_session.dart';
import 'party_session.dart';
import 'watch_sync_engine.dart';

/// v1.2.0-P3: guest auto-open — host plays X → guest's phone resolves X
/// (TMDB → Cinemeta → WatchScreen autoplay) and opens it. Unlimited titles.
///
/// Single owner: [GuestFollowService] (global event listener, armed on join).
/// The player's own onGuestMediaSwitch stays a toast-only fallback.
/// Dedup via [_handlingRef]: double events / join+event races open once.
class GuestAutoOpen {
  static String? _handlingRef;
  static const _resolveTimeout = Duration(seconds: 20);

  /// P10: pre-resolved metadata cache (ref → detail). A `ready:true` hint
  /// warms it; the real switch then opens in ~1s (no resolve wait).
  /// Bounded (forget oldest past 8) — lobby-sitting guests included.
  static final Map<String, MovieDetail> _detailCache = {};

  /// Test/maintenance hook: read the warmed entry (null when cold).
  static MovieDetail? cachedDetail(String ref) => _detailCache[ref];

  /// Test hook: seed the cache without network.
  static void cacheDetail(String ref, MovieDetail detail) {
    _detailCache[ref] = detail;
    while (_detailCache.length > 8) {
      _detailCache.remove(_detailCache.keys.first);
    }
  }

  static void clearCache() => _detailCache.clear();

  static bool get busy => _handlingRef != null;

  /// Parsed host ref → what to fetch. Pure (unit-tested).
  static RefTarget? parseRef(String ref,
      {String? title, int? season, int? episode}) {
    final r = ref.trim();
    var m = RegExp(r'^tmdb:movie:(\d+)$').firstMatch(r);
    if (m != null) {
      return RefTarget(
          kind: RefKind.movie, tmdbId: int.parse(m.group(1)!), title: title);
    }
    m = RegExp(r'^tmdb:tv:(\d+)(?::S(\d+):E(\d+))?$').firstMatch(r);
    if (m != null) {
      return RefTarget(
        kind: RefKind.tv,
        tmdbId: int.parse(m.group(1)!),
        title: title,
        season: season ?? int.tryParse(m.group(2) ?? '') ?? 1,
        episode: episode ?? int.tryParse(m.group(3) ?? '') ?? 1,
      );
    }
    m = RegExp(r'^imdb:(tt\d+)$').firstMatch(r);
    if (m != null) {
      return RefTarget(kind: RefKind.movie, imdbId: m.group(1), title: title);
    }
    return null;
  }

  /// Entry point: guest should now watch [msg]. No-op for hosts,
  /// same-title repeats, and while another open is in flight.
  static Future<void> handle(WatchSyncMessage msg) async {
    final s = PartySession.instance;
    if (!s.inParty || s.isHost || !msg.isUsable) return;
    if (msg.mediaRef == s.mediaRef && _handlingRef == null) {
      // Already on this title (sync math continues in player session).
      return;
    }
    if (_handlingRef == msg.mediaRef) return; // race: already opening
    _handlingRef = msg.mediaRef;
    try {
      await _open(msg).timeout(_resolveTimeout);
    } on TimeoutException {
      _handlingRef = null; // release immediately so retry can re-acquire
      unawaited(
          AppErrorLog.log(code: 'guest_open', screen: 'party', detail: 'timeout_20s'));
      await _showTimeoutRetry(msg, context: navigatorKey.currentContext);
    } catch (_) {
      _toast("Couldn't open this one — check net, you'll rejoin on next play.");
      unawaited(AppErrorLog.log(code: 'guest_open', screen: 'party'));
    } finally {
      _handlingRef = null;
    }
  }

  /// Guest open position: host snapshot + in-flight elapsed (clamped ≥ 0).
  /// Pure (unit-tested) — guest host ke paas khulta hai, 0:00 se nahi.
  static Duration initialPositionFor(WatchSyncMessage msg, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final target = WatchSyncEngine.targetPosition(
      hostPositionMs: msg.positionMs,
      hostSentAtMs: msg.hostSentAtMs,
      nowMs: now,
      clockOffsetMs: 0,
    );
    return Duration(milliseconds: target < 0 ? 0 : target);
  }

  static Future<void> _open(WatchSyncMessage msg) async {
    final target = parseRef(msg.mediaRef,
        title: msg.mediaTitle, season: msg.season, episode: msg.episode);
    if (target == null) {
      _toast('Host is playing something unknown — stay, next title follows.');
      return;
    }
    // P10: warmed by the ready-hint? Skip the resolve wait (~1s feel).
    final detail = cachedDetail(msg.mediaRef) ?? await _resolveDetail(target);
    if (detail == null) {
      _toast("Couldn't find this one — host, pick a popular title.");
      return;
    }
    final nav = navigatorKey.currentState;
    final ctx = navigatorKey.currentContext;
    if (nav == null || ctx == null) return; // app backgrounded: skip silently
    final type = target.kind == RefKind.tv ? 'series' : 'movie';
    Video? ep;
    if (target.kind == RefKind.tv) {
      final vids = detail.videos;
      for (final v in vids) {
        if ((v.season ?? 1) == target.season && (v.episode ?? 1) == target.episode) {
          ep = v;
          break;
        }
      }
      ep ??= vids.isNotEmpty ? vids.first : null;
    }
    final route = CinematicSlideRoute(
      page: WatchScreen(
        detail: detail,
        type: type,
        selectedEpisode: ep,
        // Cinema-hall parity: guest host ke paas khulta hai (0:00 nahi).
        initialPosition: initialPositionFor(msg),
      ),
    );
    if (PartyPlaybackSession.activeCount > 0) {
      // Guest already in player → replace (no stacked players / double audio).
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
    // Local state follows only AFTER successful open.
    PartySession.instance.setGuestMedia(
      mediaRef: msg.mediaRef,
      mediaTitle: msg.mediaTitle ?? detail.name,
      season: target.season,
      episode: target.episode,
    );
  }

  /// P10: `ready:true` hint → pre-RESOLVE metadata only (NO player open,
  /// NO video preload — bandwidth stays untouched). Warms [_detailCache]
  /// so the real switch opens in ~1s. Silent on failure (real switch
  /// resolves normally).
  static Future<void> prewarm(WatchSyncMessage msg) async {
    if (!msg.isUsable || cachedDetail(msg.mediaRef) != null) return;
    try {
      final target = parseRef(msg.mediaRef,
          title: msg.mediaTitle, season: msg.season, episode: msg.episode);
      if (target == null) return;
      final detail = await _resolveDetail(target).timeout(_resolveTimeout);
      if (detail != null) cacheDetail(msg.mediaRef, detail);
    } catch (_) {
      // P15: silent-but-logged — the real switch resolves normally.
      unawaited(
          AppErrorLog.log(code: 'guest_prewarm', screen: 'party'));
    }
  }

  /// tmdb/imdb ref → full MovieDetail via Cinemeta (keyless).
  static Future<MovieDetail?> _resolveDetail(RefTarget t) async {
    String? imdb = t.imdbId;
    final String endpoint = t.kind == RefKind.tv ? 'tv' : 'movie';
    if (imdb == null && t.tmdbId != null) {
      imdb = await TmdbHelper.fetchImdbId(endpoint: endpoint, tmdbId: t.tmdbId!);
    }
    if (imdb == null) {
      // Last resort: title search → Movie → meta (needs msg title).
      if ((t.title ?? '').trim().isEmpty) return null;
      final movie = await MetadataService.findMovieByTitle(
        title: t.title!.trim(),
        type: t.kind == RefKind.tv ? 'series' : 'movie',
      );
      if (movie == null) return null;
      return MetadataService.fetchMeta(
        baseUrl: movie.addonBaseUrl,
        type: movie.type,
        imdbId: movie.id,
      );
    }
    final type = endpoint == 'tv' ? 'series' : 'movie';
    var detail = await MetadataService.fetchMeta(
      baseUrl: '',
      type: type,
      imdbId: imdb,
    );
    // imdb: refs are type-ambiguous — retry as the other type once.
    if (detail == null && t.imdbId != null) {
      detail = await MetadataService.fetchMeta(
        baseUrl: '',
        type: type == 'movie' ? 'series' : 'movie',
        imdbId: imdb,
      );
    }
    return detail;
  }

  static void _toast(String msg) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  /// v1.2.0-W4: graceful resolve-timeout UI — 7-segment countdown and
  /// explicit retry action. Runs as a bottom-sheet overlay.
  /// Guarded: no sheet when the app is backgrounded, never an unawaited
  /// fire-and-forget (the countdown owns the only retry), and Cancel
  /// truly cancels (no auto-retry after user dismisses).
  static Future<void> _showTimeoutRetry(WatchSyncMessage msg, {BuildContext? context}) async {
    final ctx = context ?? navigatorKey.currentContext;
    if (ctx == null) return;
    // Dead context guard: pushing a sheet on a defunct route tree throws.
    Element? element;
    try {
      element = ctx as Element?;
    } catch (_) {
      return;
    }
    if (element == null || !element.mounted) return;
    // Double-guard: no attached overlay (app backgrounded) → skip silently.
    try {
      final overlay = Navigator.of(ctx, rootNavigator: true).overlay;
      if (overlay == null || !overlay.mounted) return;
    } catch (_) {
      return;
    }
    final countdown = ValueNotifier<int>(3);
    Timer? timer;
    var retryCount = 0;
    var settled = false; // exactly one outcome: auto-retry XOR button XOR cancel

    void settle({required bool retry}) {
      if (settled) return;
      settled = true;
      timer?.cancel();
      // Sheet may already be gone (back button / route pop) — never throw.
      try {
        final nav = Navigator.of(ctx, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      } catch (_) {}
      if (retry) {
        retryCount++;
        unawaited(_retryOpen(msg, attempts: retryCount));
      }
    }

    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (countdown.value <= 1) {
        settle(retry: true);
      } else {
        countdown.value--;
      }
    });

    try {
      await showModalBottomSheet(
        context: ctx,
        useRootNavigator: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: const Color(0xFF0D1017),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetCtx) {
          return PopScope(
            canPop: false, // back button can't strand the timer
            child: ValueListenableBuilder<int>(
              valueListenable: countdown,
              builder: (context, remaining, _) {
                final locked = settled;
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        const Text(
                          'Having trouble opening this',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Dizzy7Segment(
                          value: remaining.toString().padLeft(2, '0'),
                          activeColor: DizzyGlow.volt,
                          digitWidth: 26.0,
                          digitHeight: 44.0,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Trying again in a moment…',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            FilledButton.tonal(
                              onPressed: locked
                                  ? null
                                  : () => settle(retry: true),
                              child: const Text('Retry Now'),
                            ),
                            FilledButton(
                              onPressed: locked
                                  ? null
                                  : () => settle(retry: false),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    } catch (_) {
      // Sheet never showed (route race) — fall back to one silent retry.
      settle(retry: true);
    } finally {
      timer.cancel();
      countdown.dispose();
    }
  }

  static Future<void> _retryOpen(WatchSyncMessage msg, {int attempts = 0}) async {
    if (attempts >= 3) return; // max 3 retries
    final d = Duration(seconds: 15 - attempts * 3); // 15, 12, 9 seconds
    try {
      _handlingRef = msg.mediaRef;
      await _open(msg).timeout(d);
    } catch (_) {
      if (navigatorKey.currentContext != null) {
        _toast('Still loading — will try again.');
      }
    } finally {
      _handlingRef = null;
    }
  }
}

enum RefKind { movie, tv }

class RefTarget {
  final RefKind kind;
  final int? tmdbId;
  final String? imdbId;
  final String? title;
  final int season;
  final int episode;

  const RefTarget({
    required this.kind,
    this.tmdbId,
    this.imdbId,
    this.title,
    this.season = 1,
    this.episode = 1,
  });
}

/// v1.2.0-P3: global guest-follow listener. Armed on join, disarmed on leave.
/// Owns auto-open everywhere (lobby-sitting guests too); the player session
/// keeps doing sync math only.
class GuestFollowService {
  static StreamSubscription<WatchPartyEvent>? _sub;
  static bool get armed => _sub != null;

  static void arm() {
    if (_sub != null) return;
    _sub = WatchPartyService.events.listen((event) async {
      final s = PartySession.instance;
      if (!s.inParty || s.isHost) return;
      if (event.text == null) return;
      if (event.type != 'media_switch' && event.type != 'host_state') return;
      try {
        final decoded = jsonDecode(event.text!);
        if (decoded is! Map) return;
        final msg = WatchSyncMessage.fromJson(
            Map<String, dynamic>.from(decoded));
        // P10: prefetch-verified hint → warm metadata only (no open).
        if (msg.isUsable && msg.prefetchReady && msg.mediaRef != s.mediaRef) {
          await GuestAutoOpen.prewarm(msg);
          return;
        }
        if (msg.isUsable && msg.mediaRef != s.mediaRef) {
          await GuestAutoOpen.handle(msg);
        }
      } catch (_) {}
    });
  }

  static Future<void> disarm() async {
    await _sub?.cancel();
    _sub = null;
    GuestAutoOpen.clearCache(); // P10: warmed entries die with the party
  }
}
