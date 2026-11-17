import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/nav_key.dart';
import '../../models/movie/movie.dart';
import '../../pages/details/details_page.dart';
import '../../pages/settings/watch_party_page.dart';
import '../../pages/social/direct_message_page.dart';
import '../../pages/social/group_chat_page.dart';
import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';
import '../metadata/metadata_service.dart';
import '../notification/notification_inbox.dart';
import '../notification/notification_prefs.dart';
import '../notification/notification_service.dart';
import '../notification/notification_sync.dart';
import '../notification/push_route.dart';
import '../scraper/sites/tmdb_helper.dart';
import '../taste/taste_event_service.dart';
import 'active_thread.dart';

/// FCM payload after normalisation. Pure value type so the mapping is
/// unit-tested without a platform channel.
class PushPayload {
  const PushPayload({
    required this.kind,
    required this.title,
    required this.body,
    this.id,
    this.entityType = '',
    this.entityId = '',
    this.lang = '',
    this.poster = '',
    this.year = '',
    this.rating = '',
    this.senderUid = '',
    this.senderName = '',
    this.avatar = '',
    this.groupId = '',
    this.groupName = '',
    this.roomCode = '',
  });

  static const int maxTitle = 120;
  static const int maxBody = 240;

  final NotificationKind kind;
  final String title;
  final String body;
  final String? id;
  final String entityType;
  final String entityId;
  final String lang;
  final String poster;
  final String year;
  final String rating;

  /// Social routing fields. Empty for release/update pushes, so a single
  /// payload shape serves both — [route] picks the destination.
  final String senderUid;
  final String senderName;
  final String avatar;
  final String groupId;
  final String groupName;
  final String roomCode;

  factory PushPayload.fromData(
    Map<String, dynamic>? data, {
    String? fallbackTitle,
    String? fallbackBody,
  }) {
    final d = data ?? const <String, dynamic>{};
    final rawTitle = clean(d['title'] ?? fallbackTitle, maxTitle);
    final rawBody = clean(d['body'] ?? fallbackBody, maxBody);
    final hasContent = rawTitle.isNotEmpty || rawBody.isNotEmpty;
    final id = clean(d['id'], 80);
    return PushPayload(
      kind:
          NotificationKind.fromKey(clean(d['kind'], 32)) ??
          NotificationKind.release,
      title: rawTitle.isEmpty && hasContent ? 'Dizzy' : rawTitle,
      body: rawBody,
      id: id.isEmpty ? null : id,
      entityType: clean(d['entity_type'], 16),
      entityId: clean(d['entity_id'], 32),
      lang: clean(d['lang'] ?? d['language'], 8),
      poster: clean(d['poster'], 500),
      year: clean(d['year'], 8),
      rating: clean(d['rating'], 8),
      senderUid: clean(d['sender_uid'], 64),
      senderName: clean(d['sender_name'], 80),
      avatar: clean(d['avatar'], 500),
      groupId: clean(d['group_id'], 64),
      groupName: clean(d['group_name'], 80),
      roomCode: clean(d['room_code'], 16),
    );
  }

  /// Where a tap on this payload lands. Chat beats title: someone tapping a
  /// message wants the conversation, not the film it mentions.
  PushRoute get route => PushRoute.resolve(
    senderUid: senderUid,
    senderName: senderName,
    avatar: avatar,
    groupId: groupId,
    groupName: groupName,
    roomCode: roomCode,
    entityId: entityId,
    poster: poster,
  );

  static String clean(Object? raw, int max) {
    if (raw == null) return '';
    final s = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length <= max ? s : s.substring(0, max).trimRight();
  }

  bool get hasContent => title.isNotEmpty || body.isNotEmpty;

  bool get openable => entityId.isNotEmpty;

  Movie? toMovie() {
    if (!openable) return null;
    return Movie(
      id: entityId,
      name: title.isEmpty ? 'Unknown' : title,
      poster: poster.isEmpty ? null : poster,
      year: year.isEmpty ? null : year,
      type: entityType == 'tv' || entityType == 'series' ? 'series' : 'movie',
      addonBaseUrl: '',
      imdbRating: rating.isEmpty ? null : rating,
    );
  }
}

/// What [PushService.openMovieFor] must do about the entity id before opening
/// details. Cinemeta (`MetadataService.fetchMeta`) only understands imdb `tt…`
/// ids, but push-brain sends a numeric TMDB id — so numeric ids need a
/// tmdb→imdb bridge first. `tt…` / other id shapes pass through untouched.
class PushEntityPlan {
  const PushEntityPlan({required this.endpoint, required this.tmdbId});

  /// 'movie' or 'tv' — TMDB's resource path for [tmdbId].
  final String endpoint;
  final int tmdbId;
}

/// House copy that push-brain prefixes to the real title (2026-11-R2
/// templates). Order: longer/more specific first is unnecessary — none is a
/// prefix of another — but keep the list grouped by shape for readability.
@visibleForTesting
const List<String> pushCopyPrefixes = <String>[
  'aaj raat:',
  'aaj ka pick:',
  'one episode?',
  'episode time…',
  'psst…',
  'psst — ',
  'tonight:',
  'new on dizzy:',
];

/// House copy that push-brain appends after the real title. Terminal
/// punctuation (`?`, `…`) is deliberately absent — displayTitleFor's end-trim
/// consumes it before suffix matching runs.
@visibleForTesting
const List<String> pushCopySuffixes = <String>[
  ' — episode mood',
  ' — tum ke liye',
  ' — aaj dekh lein',
  ' ab dizzy par',
  ' just landed',
];

/// Pure: the real title name behind the notification copy, so
/// [MetadataService.findMovieByTitle]'s exact-title gate can match when the
/// tmdb→imdb bridge fails. Strips emoji/symbol runs at both ends, then the
/// known prefixes/suffixes, then trims again ('🌙 Aaj raat: Dune 2 🍿' →
/// 'Dune 2'; 'One episode? Breaking Bad 🎬' → 'Breaking Bad'; a plain title
/// passes through unchanged). Case-insensitive, idempotent, never empty-lossy:
/// if nothing remains (e.g. the 40-char shade clip ate the name) the nearest
/// prior state wins.
@visibleForTesting
String displayTitleFor(String rawTitle) {
  var s = rawTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return s;
  // Emoji, symbols, punctuation and control chars at either end — but keep
  // a leading '(' or trailing ')' so titles starting with parens survive.
  final lead = RegExp(r'^[^\p{L}\p{N}(]+', unicode: true);
  final tail = RegExp(r'[^\p{L}\p{N})]+$', unicode: true);
  for (var round = 0; round < 3; round++) {
    var changed = false;
    final next = s.replaceAll(lead, '').replaceAll(tail, '').trim();
    final lower = next.toLowerCase();
    for (final p in pushCopyPrefixes) {
      if (lower.startsWith(p)) {
        s = next.substring(p.length).trim();
        changed = true;
        break;
      }
    }
    if (!changed) {
      for (final suf in pushCopySuffixes) {
        if (lower.endsWith(suf)) {
          s = next.substring(0, next.length - suf.length).trim();
          changed = true;
          break;
        }
      }
    }
    if (!changed) return next;
    // else loop again: another prefix/suffix/emoji run may remain.
  }
  return s;
}

/// Pure: how the payload's entity id must be resolved before DetailsPage can
/// use it. Returns null when no bridge is needed (`tt…` ids pass straight
/// through, legacy non-numeric shapes keep today's pass-through behavior,
/// unparseable ids cannot be bridged).
@visibleForTesting
PushEntityPlan? resolvePlanForPushEntity(PushPayload payload) {
  final id = payload.entityId.trim();
  if (id.isEmpty) return null;
  if (id.toLowerCase().startsWith('tt')) return null;
  final tmdbId = int.tryParse(id);
  if (tmdbId == null || tmdbId <= 0) return null;
  final type = payload.entityType.trim().toLowerCase();
  return PushEntityPlan(
    endpoint: type == 'tv' || type == 'series' ? 'tv' : 'movie',
    tmdbId: tmdbId,
  );
}

/// Must be a top-level function: FCM spawns a background isolate that calls
/// it by name. No UI and no local-notification plugin — only the inbox is
/// written, because the OS already draws the banner for notification
/// payloads sent while the app is backgrounded.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await PushService.recordToInbox(PushService.payloadFromMessage(message));
  } catch (e) {
    debugPrint('[Push] background handler failed (soft): $e');
  }
}

/// FCM client half (v1.3.3 Phase 3).
///
/// Contract:
///  * phone-only — desktops never touch Firebase;
///  * a token is registered only after the user granted notifications, and
///    re-registered whenever FCM rotates it;
///  * foreground pushes land in the Notification Center through
///    [NotificationService.push] so quiet hours and per-type prefs apply;
///  * taps feed `notif_open` into the taste engine and open details when the
///    payload carries a title id;
///  * every failure is soft — no push problem may break boot or playback.
class PushService {
  PushService._();

  static bool _started = false;
  static bool _granted = false;
  static String? _registeredToken;
  static PushPayload? _pendingTap;

  static bool _testMode = false;
  static Future<String?> Function()? _tokenOverride;
  static Future<String> Function()? _appVersionOverride;
  static Future<bool> Function(Map<String, dynamic>)? _registerOverride;
  static Future<String?> Function({required String endpoint, required int tmdbId})?
      _imdbResolveOverride;
  static Future<Movie?> Function(String title, String type, int? year)?
      _titleSearchOverride;

  /// 'android' | 'ios' | 'desktop' | 'other' — stored on device_tokens.
  static String get platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return 'desktop';
    }
    return 'other';
  }

  static Future<void> initialize() async {
    if (_started) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    _started = true;
    try {
      await Firebase.initializeApp();
      debugPrint('[Push] firebase ready (${Firebase.app().name})');
    } catch (e) {
      AppLog.d('[Push] firebase init failed (soft): $e');
      return;
    }
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        unawaited(handleTap(payloadFromMessage(m)));
      });
      unawaited(_handleInitialMessage(messaging));
      // Foreground banner taps come back through the local-notification
      // plugin; hook them into the same open-details pipeline.
      NotificationService.onTapData = _onLocalTap;
      await _syncAuthorization();
      if (_granted) unawaited(registerToken());
      unawaited(NotificationSync.push(gate: NotificationService.gate));
      messaging.onTokenRefresh.listen((token) {
        if (token.isNotEmpty) unawaited(_register(token));
      });
    } catch (e) {
      AppLog.d('[Push] messaging wiring failed (soft): $e');
    }
  }

  /// Called after the app's own permission dialog returned "Turn on".
  static Future<void> onPermissionGranted() async {
    await _syncAuthorization();
    if (_granted) await registerToken();
    await NotificationSync.push(gate: NotificationService.gate);
  }

  static Future<void> _syncAuthorization() async {
    try {
      await NotificationService.initialize();
      _granted = NotificationService.permissionGranted;
    } catch (_) {
      _granted = false;
    }
  }

  /// Registers this device's FCM token against the signed-in account. The
  /// RPC moves the token if another account used the same handset.
  static Future<bool> registerToken() async {
    try {
      if (!_testMode) {
        if (!_granted) return false;
        if (!CloudClient.isReady) return false;
      }
      final token = await (_tokenOverride ?? _fcmToken)();
      if (token == null || token.isEmpty) return false;
      if (token == _registeredToken) return true;
      return await _register(token);
    } catch (e) {
      AppLog.d('[Push] register failed (soft): $e');
      return false;
    }
  }

  static Future<String?> _fcmToken() => FirebaseMessaging.instance.getToken();

  static Future<bool> _register(String token) async {
    final appVersion = await (_appVersionOverride ?? _appVersion)();
    final params = <String, dynamic>{
      'p_token': token,
      'p_platform': platformName,
      'p_app_version': appVersion,
    };
    final registrar = _registerOverride;
    final ok = registrar != null ? await registrar(params) : await _rpcRegister(params);
    if (!ok) return false;
    _registeredToken = token;
    return true;
  }

  static Future<bool> _rpcRegister(Map<String, dynamic> params) async {
    try {
      final res = await CloudClient.db.rpc(
        'register_device_token',
        params: params,
      );
      return res is Map && res['success'] == true;
    } catch (e) {
      AppLog.d('[Push] rpc register failed (soft): $e');
      return false;
    }
  }

  static Future<String> _appVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '';
    }
  }

  static PushPayload payloadFromMessage(RemoteMessage message) =>
      PushPayload.fromData(
        message.data,
        fallbackTitle: message.notification?.title,
        fallbackBody: message.notification?.body,
      );

  static void _onForeground(RemoteMessage message) {
    unawaited(dispatch(payloadFromMessage(message)));
  }

  /// Local-banner tap (foreground): rebuild the payload from the data blob
  /// carried in the notification and feed the same handleTap path.
  static Future<void> _onLocalTap(Map<String, dynamic> data) =>
      handleTap(PushPayload.fromData(data));

  /// Foreground delivery: inbox + banner under the user's gate.
  static Future<void> dispatch(PushPayload payload) async {
    if (!payload.hasContent) return;
    try {
      await NotificationService.push(
        payload.kind,
        payload.title,
        payload.body,
        id: payload.id,
        dataPayload: tapDataFor(payload),
        banner: !ActiveThread.isOpen(payload.route.threadKey),
      );
    } catch (e) {
      AppLog.d('[Push] dispatch failed (soft): $e');
    }
  }

  /// Data carried in the local banner so a foreground banner tap can rebuild
  /// the payload and open the same screen a system tap would. Everything
  /// round-trips: the rebuilt payload must pass [PushPayload.fromData] with
  /// the same content and the same [PushRoute], otherwise `handleTap` would
  /// bail on `hasContent` and the tap would do nothing. Pure: unit-tested.
  static Map<String, String> tapDataFor(PushPayload payload) {
    final data = <String, String>{
      'kind': payload.kind.key,
      'title': payload.title,
      'body': payload.body,
      'entity_type': payload.entityType,
      'entity_id': payload.entityId,
      'lang': payload.lang,
      'poster': payload.poster,
      'year': payload.year,
      'rating': payload.rating,
    };
    final id = payload.id;
    if (id != null && id.isNotEmpty) data['id'] = id;
    // Social routing fields ride along only when present, so a release push
    // keeps exactly the blob it had before.
    void put(String key, String value) {
      if (value.isNotEmpty) data[key] = value;
    }

    put('sender_uid', payload.senderUid);
    put('sender_name', payload.senderName);
    put('avatar', payload.avatar);
    put('group_id', payload.groupId);
    put('group_name', payload.groupName);
    put('room_code', payload.roomCode);
    return data;
  }

  /// Background isolate: inbox only, history load first so a cold isolate
  /// cannot overwrite the stored list with a single item.
  static Future<void> recordToInbox(PushPayload payload) async {
    if (!payload.hasContent) return;
    await NotificationInbox.load();
    await NotificationInbox.add(
      title: payload.title,
      body: payload.body,
      kind: payload.kind,
      id: payload.id,
      data: tapDataFor(payload),
    );
  }

  static Future<void> _handleInitialMessage(FirebaseMessaging messaging) async {
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) await handleTap(payloadFromMessage(initial));
    } catch (e) {
      AppLog.d('[Push] initial message failed (soft): $e');
    }
  }

  /// A tap is taste signal even when the payload cannot open a screen.
  /// With no navigator yet (cold start) the payload waits for first frame.
  static Future<void> handleTap(PushPayload payload) async {
    if (!payload.hasContent) return;
    try {
      TasteEventService.record(
        TasteEventKind.notifOpen,
        entityType: payload.entityType.isEmpty ? 'movie' : payload.entityType,
        entityId: payload.entityId,
        title: payload.title,
        lang: payload.lang,
        meta: {'source': 'push'},
      );
    } catch (_) {}
    final route = payload.route;
    if (!route.opens) return;
    final nav = navigatorKey.currentState;
    if (nav == null) {
      _pendingTap = payload;
      return;
    }
    await openRoute(route, payload: payload);
  }

  /// Opens the screen [route] points at. Every tap funnels through here — a
  /// system tap, a foreground banner tap and a Notification Center row all
  /// take the same path, so they can never disagree about where a push goes.
  static Future<void> openRoute(PushRoute route, {PushPayload? payload}) async {
    if (!route.opens) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    switch (route.target) {
      case PushTarget.dm:
        nav.push(
          MaterialPageRoute(
            builder: (_) => DirectMessagePage(
              recipientUid: route.threadId,
              recipientUsername: route.label.isEmpty ? 'Friend' : route.label,
              recipientAvatar: route.avatar.isEmpty ? null : route.avatar,
            ),
          ),
        );
        break;
      case PushTarget.group:
        nav.push(
          MaterialPageRoute(
            builder: (_) => GroupChatPage(
              groupId: route.threadId,
              groupName: route.label.isEmpty ? 'Group' : route.label,
            ),
          ),
        );
        break;
      case PushTarget.room:
        nav.push(MaterialPageRoute(builder: (_) => const WatchPartyPage()));
        break;
      case PushTarget.title:
        final source = payload;
        if (source == null) return;
        final resolved = await openMovieFor(source);
        if (resolved == null) return;
        // The navigator may have gone away while resolving (dispose during
        // navigation away) — fall back to pending so nothing is silently lost.
        final nav2 = navigatorKey.currentState;
        if (nav2 == null) {
          _pendingTap = source;
          return;
        }
        nav2.push(
          MaterialPageRoute(builder: (_) => DetailsPage(movie: resolved)),
        );
        break;
      case PushTarget.none:
        return;
    }
  }

  /// Rebuilds a payload from a stored or banner-carried data blob and opens
  /// it. Used by the Notification Center rows, whose tap data outlives the
  /// banner it came from.
  static Future<void> openFromData(Map<String, dynamic>? data) async {
    final payload = PushPayload.fromData(data);
    await openRoute(payload.route, payload: payload);
  }

  /// Called after the first frame — flushes a tap that arrived before the
  /// navigator existed.
  static Future<void> openPendingTap() async {
    final payload = _pendingTap;
    if (payload == null) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _pendingTap = null;
    await openRoute(payload.route, payload: payload);
  }

  /// Resolves the movie to open for a tap: swaps a numeric TMDB entity id for
  /// an imdb id via [TmdbHelper.fetchImdbId] (Cinemeta only speaks `tt…`),
  /// and when that bridge fails falls back to an exact-title search on the
  /// copy-cleaned name (pure [displayTitleFor]). Always returns a movie for an
  /// openable payload — worst case it keeps prior pass-through behavior.
  /// Resolution failures are soft and logged, never thrown.
  static Future<Movie?> openMovieFor(PushPayload payload) async {
    final base = payload.toMovie();
    if (base == null) return null;
    final plan = resolvePlanForPushEntity(payload);
    if (plan == null) return base;
    String id = base.id;
    try {
      String? imdb;
      if (_imdbResolveOverride != null) {
        final resolve = _imdbResolveOverride;
        if (resolve != null) {
          imdb = await resolve(
            endpoint: plan.endpoint,
            tmdbId: plan.tmdbId,
          );
          if (imdb != null && imdb.isNotEmpty) id = imdb;
        }
      } else {
        imdb = await TmdbHelper.fetchImdbId(
          endpoint: plan.endpoint,
          tmdbId: plan.tmdbId,
        );
        if (imdb != null && imdb.startsWith('tt')) id = imdb;
      }
    } catch (e) {
      AppLog.d('[Push] tmdb->imdb bridge failed (soft): $e');
    }
    if (id != base.id) {
      return _withId(base, id);
    }
    // Bridge unavailable/failed → exact-title fallback with copy cleaned.
    final displayTitle = displayTitleFor(payload.title);
    if (displayTitle.isEmpty) return base;
    try {
      Movie? found;
      if (_titleSearchOverride != null) {
        found = await _titleSearchOverride!(
          displayTitle,
          base.type,
          _yearOf(payload),
        );
      } else {
        found = await MetadataService.findMovieByTitle(
          title: displayTitle,
          type: base.type,
          year: _yearOf(payload),
        );
      }
      if (found != null && found.id.isNotEmpty) return found;
    } catch (e) {
      AppLog.d('[Push] title fallback failed (soft): $e');
    }
    return base;
  }

  static int? _yearOf(PushPayload payload) {
    final y = payload.year.replaceAll(RegExp(r'[^0-9]'), '');
    return y.length >= 4 ? int.tryParse(y.substring(0, 4)) : null;
  }

  static Movie _withId(Movie base, String id) => Movie(
        id: id,
        name: base.name,
        poster: base.poster,
        year: base.year,
        type: base.type,
        addonBaseUrl: base.addonBaseUrl,
        imdbRating: base.imdbRating,
      );

  @visibleForTesting
  static PushPayload? get pendingTapForTest => _pendingTap;

  @visibleForTesting
  static void configureForTest({
    required Future<String?> Function() token,
    required Future<String> Function() appVersion,
    required Future<bool> Function(Map<String, dynamic> params) register,
  }) {
    _testMode = true;
    _tokenOverride = token;
    _appVersionOverride = appVersion;
    _registerOverride = register;
  }

  /// Test seams for the open path: [imdbResolve] mirrors
  /// [TmdbHelper.fetchImdbId], [titleSearch] mirrors
  /// [MetadataService.findMovieByTitle]; both let tests assert on the exact
  /// calls without network. Pass null to leave that seam unchanged.
  @visibleForTesting
  static void configureResolverForTest({
    Future<String?> Function({required String endpoint, required int tmdbId})?
        imdbResolve,
    Future<Movie?> Function(String title, String type, int? year)? titleSearch,
  }) {
    if (imdbResolve != null) _imdbResolveOverride = imdbResolve;
    if (titleSearch != null) _titleSearchOverride = titleSearch;
  }

  @visibleForTesting
  static void resetForTest() {
    _testMode = false;
    _started = false;
    _granted = false;
    _registeredToken = null;
    _pendingTap = null;
    _tokenOverride = null;
    _appVersionOverride = null;
    _registerOverride = null;
    _imdbResolveOverride = null;
    _titleSearchOverride = null;
  }
}
