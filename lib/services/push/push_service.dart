import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/nav_key.dart';
import '../../models/movie/movie.dart';
import '../../pages/details/details_page.dart';
import '../cloud/cloud_client.dart';
import '../errors/app_log.dart';
import '../notification/notification_inbox.dart';
import '../notification/notification_prefs.dart';
import '../notification/notification_service.dart';
import '../notification/notification_sync.dart';
import '../taste/taste_event_service.dart';

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
    );
  }

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

  /// Foreground delivery: inbox + banner under the user's gate.
  static Future<void> dispatch(PushPayload payload) async {
    if (!payload.hasContent) return;
    try {
      await NotificationService.push(
        payload.kind,
        payload.title,
        payload.body,
        id: payload.id,
      );
    } catch (e) {
      AppLog.d('[Push] dispatch failed (soft): $e');
    }
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

  /// A tap is taste signal even when the payload cannot open a title.
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
    final movie = payload.toMovie();
    if (movie == null) return;
    final nav = navigatorKey.currentState;
    if (nav == null) {
      _pendingTap = payload;
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => DetailsPage(movie: movie)));
  }

  /// Called after the first frame — flushes a tap that arrived before the
  /// navigator existed.
  static void openPendingTap() {
    final payload = _pendingTap;
    if (payload == null) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final movie = payload.toMovie();
    if (movie == null) return;
    _pendingTap = null;
    nav.push(MaterialPageRoute(builder: (_) => DetailsPage(movie: movie)));
  }

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
  }
}
