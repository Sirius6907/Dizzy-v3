import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_inbox.dart';
import 'notification_prefs.dart';
import 'notification_sync.dart';

/// Phase J1/J2 — local notification renderer.
///
/// Contract:
///  * every event lands in [NotificationInbox] (the Center is the source of
///    truth and never loses history, even during quiet hours);
///  * the OS banner shows only when the per-type preference and the
///    quiet-hours window both allow it AND Android has granted
///    POST_NOTIFICATIONS;
///  * nothing here ever throws — a notification failure must never break
///    the feature that triggered it.
class NotificationService {
  NotificationService._();

  static const String kGateKey = 'notification_gate_v1';
  static const String kPermAskedKey = 'notification_permission_asked_v1';

  static const Map<String, String> _channelNames = {
    'updates': 'App updates',
    'releases': 'New releases',
    'downloads': 'Downloads',
    'social': 'Friends & messages',
    'announcements': 'News from Dizzy',
  };

  static const Map<String, String> _channelDesc = {
    'updates': 'A new Dizzy version is ready to install.',
    'releases': 'New movies and shows picked for you.',
    'downloads': 'Your download finished, or stopped early.',
    'social': 'Friend requests, messages and room invites.',
    'announcements': 'News and maintenance notes from the Dizzy team.',
  };

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Tap hook for local banner taps. PushService installs it during init
  /// so this renderer stays free of a push-service import (avoids a cycle):
  /// [onTapData] receives the decoded data blob that rode in the banner.
  static void Function(Map<String, dynamic> data)? onTapData;

  /// Test seam for the image-card leg: replaces the poster download and the
  /// documents directory so `bigPictureStyleForTest` stays unit-testable.
  @visibleForTesting
  static Future<Uint8List?> Function(String url)? imageFetchForTest;
  @visibleForTesting
  static Future<Directory> Function()? directoryForTest;

  static NotificationGate _gate = const NotificationGate();
  static bool _init = false;
  static bool _permGranted = false;
  static bool _permAsked = false;
  static int _nextId = 1000;

  static NotificationGate get gate => _gate;
  static bool get permissionAsked => _permAsked;
  static bool get permissionGranted => _permGranted;

  static void _note(String message) => debugPrint('[Notify] $message');

  /// Fail-soft: a platform failure degrades to "inbox only", never a crash.
  static Future<void> initialize() async {
    if (_init) return;
    _init = true;
    await _loadGate();
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: _onTapForeground,
      );
      await _createChannels();
      _permGranted = await Permission.notification.isGranted;
    } catch (e) {
      _note('init degraded (inbox only): $e');
    }
  }

  /// Foreground local-banner tap: decode the data blob that rode in the
  /// banner payload and hand it to the installed [onTapData] hook (PushService
  /// rebuilds the payload and opens title details). Fail-soft by design.
  static Future<void> _onTapForeground(NotificationResponse response) async {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final hook = onTapData;
        if (hook != null) {
          hook(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (e) {
      _note('tap decode failed (soft): $e');
    }
  }

  static Future<void> _createChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final kind in NotificationKind.values) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          kind.key,
          _channelNames[kind.key] ?? 'Dizzy',
          description: _channelDesc[kind.key],
          importance: Importance.high,
        ),
      );
    }
  }

  static Future<void> _loadGate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _permAsked = prefs.getBool(kPermAskedKey) ?? false;
      final raw = prefs.getString(kGateKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _gate = NotificationGate.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      _note('gate load failed, using defaults: $e');
    }
  }

  static Future<void> _persistGate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kGateKey, jsonEncode(_gate.toJson()));
    } catch (e) {
      _note('gate persist failed (soft): $e');
    }
    unawaited(NotificationSync.push(gate: _gate));
  }

  // ── preferences ──────────────────────────────────────────────────────────

  static Future<void> setKindEnabled(NotificationKind kind, bool on) async {
    final off = Set<String>.from(_gate.off);
    if (on) {
      off.remove(kind.key);
    } else {
      off.add(kind.key);
    }
    _gate = _gate.copyWith(off: off);
    await _persistGate();
  }

  static Future<void> setQuietEnabled(bool on) async {
    _gate = _gate.copyWith(quietEnabled: on);
    await _persistGate();
  }

  static Future<void> setQuietWindow(int startMinute, int endMinute) async {
    _gate = _gate.copyWith(
      quietStartMinute: startMinute,
      quietEndMinute: endMinute,
    );
    await _persistGate();
  }

  static Future<void> setTone(NotificationTone tone) async {
    if (_gate.tone == tone) return;
    _gate = _gate.copyWith(tone: tone);
    await _persistGate();
    unawaited(NotificationSync.pushTone(tone));
  }

  // ── permission (Android 13+) ─────────────────────────────────────────────

  /// Callers show the Easy English rationale first, then await this.
  static Future<bool> requestPermission() async {
    try {
      final status = await Permission.notification.request();
      _permGranted = status.isGranted;
      await markPermissionAsked();
    } catch (e) {
      _note('permission request failed: $e');
    }
    return _permGranted;
  }

  static Future<void> markPermissionAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPermAskedKey, true);
      _permAsked = true;
    } catch (_) {}
  }

  // ── the single entry point triggers call ─────────────────────────────────

  /// Downloads [poster] to a stable local file so the banner can render an
  /// image card. Anything failing (no url, no network, no storage) degrades
  /// to `null` and the banner shows plain text — never a crash.
  static Future<String?> _posterFilePath(String poster) async {
    if (poster.isEmpty) return null;
    try {
      Uint8List? bytes;
      final override = imageFetchForTest;
      if (override != null) {
        bytes = await override(poster);
      } else {
        final res = await http
            .get(Uri.parse(poster))
            .timeout(const Duration(seconds: 5));
        bytes = res.statusCode == 200 ? res.bodyBytes : null;
      }
      if (bytes == null || bytes.isEmpty) return null;
      final overrideDir = directoryForTest;
      final String dirPath;
      if (overrideDir != null) {
        dirPath = (await overrideDir()).path;
      } else {
        dirPath = (await getApplicationDocumentsDirectory()).path;
      }
      final sep = Platform.pathSeparator;
      final name =
          'poster_${sha1.convert(utf8.encode(poster)).toString().substring(0, 12)}.jpg';
      final file = File(
        dirPath.endsWith(sep) ? '$dirPath$name' : '$dirPath$sep$name',
      );
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      _note('poster image skipped (soft): $e');
      return null;
    }
  }

  /// Big-picture ("image card") style for a release push with a poster URL.
  /// Visible-through-test: [bigPictureStyleForTest] exposes it for unit
  /// tests without a platform channel.
  static Future<StyleInformation?> _bigPictureStyle(String? poster) async {
    final path = await _posterFilePath(poster ?? '');
    if (path == null || path.isEmpty) return null;
    return BigPictureStyleInformation(
      FilePathAndroidBitmap(path),
      largeIcon: FilePathAndroidBitmap(path),
      contentTitle: null,
      summaryText: null,
    );
  }

  @visibleForTesting
  static Future<StyleInformation?> bigPictureStyleForTest(
    String? poster,
  ) => _bigPictureStyle(poster);

  /// Records the event in the Center and, when policy allows, shows the
  /// system banner. When the data payload carries a poster URL the banner
  /// renders as an FCM big-picture style image card (failed downloads
  /// degrade to text).
  static Future<void> push(
    NotificationKind kind,
    String title,
    String body, {
    String? id,
    Map<String, String>? dataPayload,
  }) async {
    await initialize();
    await NotificationInbox.add(title: title, body: body, kind: kind, id: id);
    if (!_gate.allows(kind, DateTime.now())) return;
    if (!_permGranted) return;
    final data = dataPayload;
    final dataJson =
        (data == null || data.isEmpty) ? null : jsonEncode(data);
    StyleInformation? style;
    if (data != null) {
      try {
        style = await _bigPictureStyle(data['poster']);
      } catch (e) {
        _note('style for poster failed (soft): $e');
      }
    }
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kind.key,
            _channelNames[kind.key] ?? 'Dizzy',
            channelDescription: _channelDesc[kind.key],
            importance: Importance.high,
            priority: Priority.defaultPriority,
            styleInformation: style,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: dataJson,
      );
    } catch (e) {
      _note('show failed (soft): $e');
    }
  }

  @visibleForTesting
  static void resetForTest({NotificationGate? gate}) {
    _init = false;
    _gate = gate ?? const NotificationGate();
    _permGranted = false;
    _permAsked = false;
    onTapData = null;
    imageFetchForTest = null;
    directoryForTest = null;
  }

  @visibleForTesting
  static void setPermissionForTest(bool granted) => _permGranted = granted;
}
