import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_inbox.dart';
import 'notification_prefs.dart';

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
    'download': 'Downloads',
    'social': 'Friends & messages',
    'announcement': 'News from Dizzy',
  };

  static const Map<String, String> _channelDesc = {
    'updates': 'A new Dizzy version is ready to install.',
    'download': 'Your download finished, or stopped early.',
    'social': 'Friend requests, messages and room invites.',
    'announcement': 'News and maintenance notes from the Dizzy team.',
  };

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

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
      );
      await _createChannels();
      _permGranted = await Permission.notification.isGranted;
    } catch (e) {
      _note('init degraded (inbox only): $e');
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

  /// Records the event in the Center and, when policy allows, shows the
  /// system banner.
  static Future<void> push(
    NotificationKind kind,
    String title,
    String body, {
    String? id,
  }) async {
    await initialize();
    await NotificationInbox.add(title: title, body: body, kind: kind, id: id);
    if (!_gate.allows(kind, DateTime.now())) return;
    if (!_permGranted) return;
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
          ),
          iOS: const DarwinNotificationDetails(),
        ),
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
  }

  @visibleForTesting
  static void setPermissionForTest(bool granted) => _permGranted = granted;
}
