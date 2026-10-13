import 'package:flutter/widgets.dart';

/// v1.3.3-T2.3 — session trail (bounded ring buffer of coarse events).
///
/// Why: the old pipeline stored one enum code per (device, screen, code)
/// triple with no context, so a crash arrived with no idea what the user
/// was doing. This buffer keeps the last N nav/playback/net events and
/// attaches them to the next error report as a short trail.
///
/// PRIVACY CONTRACT (same as [AppErrorLog]): tokens are ENUM ONLY —
/// `nav_home`, `play_start`, `net_timeout`. Never titles, URLs, ids or
/// free text. [record] silently drops anything outside the allowlist, so a
/// careless call site degrades to "no breadcrumb", never to a leak.
///
/// Sampling: every event is kept in-memory (cheap, ≤50 strings); the trail
/// is only ever TRANSMITTED when an error report goes out.
class SessionTrail {
  const SessionTrail._();

  /// Ring capacity. 20 tokens ≈ enough to see the path into a crash
  /// without turning a report into a novel.
  static const int capacity = 20;

  /// Whole trail must fit the server-side column budget.
  static const int maxWireLength = 240;

  /// `nav_home`, `play_start`, `net_504`, … — lowercase enums only.
  static final RegExp _tokenPattern = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

  static final List<String> _events = <String>[];

  /// Record one coarse event. Returns true when it was accepted.
  static bool record(String token) {
    final t = token.trim().toLowerCase();
    if (sanitizeToken(t).isEmpty) return false;
    _events.add(t);
    while (_events.length > capacity) {
      _events.removeAt(0);
    }
    return true;
  }

  /// A copy of the current trail, oldest first.
  @visibleForTesting
  static List<String> get events => List<String>.unmodifiable(_events);

  /// Wire string for the error payload: `nav_home>play_start>net_timeout`,
  /// trimmed from the OLDEST side when it exceeds [maxWireLength] so the
  /// events nearest the failure survive.
  static String wire() {
    final parts = List<String>.from(_events);
    var joined = parts.join('>');
    while (joined.length > maxWireLength && parts.length > 1) {
      parts.removeAt(0);
      joined = parts.join('>');
    }
    return joined.length > maxWireLength
        ? joined.substring(joined.length - maxWireLength)
        : joined;
  }

  /// Clear on session end / consent change. The trail must never outlive
  /// the session it describes.
  static void reset() => _events.clear();

  /// Test-only: drop everything.
  @visibleForTesting
  static void resetForTest() => reset();

  /// Returns the token when the WHOLE string is an allowed enum, else ''.
  static String sanitizeToken(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty || !_tokenPattern.hasMatch(v)) return '';
    return v;
  }

  /// Map a route/screen name onto a coarse nav token. Names are app-owned
  /// (`/home`, `/settings`, `PlayerScreen`) — the result is always a fixed
  /// enum, so a dynamic route param can never reach the wire.
  @visibleForTesting
  static String navTokenFor(String? routeName) {
    final n = (routeName ?? '').toLowerCase();
    if (n.isEmpty) return 'nav_unknown';
    for (final key in _navMap.keys) {
      if (n.contains(key)) return _navMap[key]!;
    }
    return 'nav_other';
  }

  /// Known route fragments → coarse tokens. Deliberately small: the trail
  /// needs "where were they", not a full route log.
  static const Map<String, String> _navMap = {
    'home': 'nav_home',
    'search': 'nav_search',
    'settings': 'nav_settings',
    'player': 'nav_player',
    'watch': 'nav_watch',
    'music': 'nav_music',
    'details': 'nav_details',
    'library': 'nav_library',
    'download': 'nav_download',
    'profile': 'nav_profile',
    'social': 'nav_social',
    'manga': 'nav_manga',
    'anime': 'nav_anime',
    'books': 'nav_books',
  };
}

/// v1.3.3-T2.3 — records a coarse `nav_*` breadcrumb per pushed route.
///
/// Only the mapped enum is kept: no route arguments, no query params, no
/// screen names a user typed. `didPush` alone is enough — a trail of
/// "where the user went" is what a crash report needs, and tracking pops
/// would double the volume for no extra signal.
class TrailNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    SessionTrail.record(SessionTrail.navTokenFor(name));
  }
}