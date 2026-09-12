import 'package:flutter/foundation.dart';

import '../cloud/watch_party_service.dart';

/// v1.2.0-T2.8: active party session state (player ↔ room glue).
/// Player reads this; lobby writes this. Single source of truth for
/// "am I in a party, host or guest, watching what".
class PartySession extends ChangeNotifier {
  static final PartySession instance = PartySession._();
  PartySession._();

  /// v1.2.0-P3: lifecycle hooks wired in main() (arm/disarm guest follow).
  /// Plain function fields = no import cycles.
  static void Function()? onGuestStart;
  static void Function()? onSessionEnd;

  WatchPartyRoom? _room;
  bool _isHost = false;
  String? _mediaRef;
  String? _mediaTitle;
  int? _season;
  int? _episode;

  WatchPartyRoom? get room => _room;
  bool get isHost => _isHost;
  String? get mediaRef => _mediaRef;
  String? get mediaTitle => _mediaTitle;
  int? get season => _season;
  int? get episode => _episode;

  bool get inParty => _room != null;

  /// Host creates/owns the room. Media is optional (P1: rooms outlive titles).
  void startAsHost({
    required WatchPartyRoom room,
    String? mediaRef,
    String? mediaTitle,
    int? season,
    int? episode,
  }) {
    _room = room;
    _isHost = true;
    _mediaRef = mediaRef;
    _mediaTitle = mediaTitle;
    _season = season;
    _episode = episode;
    notifyListeners();
  }

  /// Guest joins; media ref arrives from host events.
  void startAsGuest({required WatchPartyRoom room}) {
    _room = room;
    _isHost = false;
    notifyListeners();
    onGuestStart?.call();
  }

  /// Guest learns/changes media from host broadcast.
  void setGuestMedia({
    required String mediaRef,
    String? mediaTitle,
    int? season,
    int? episode,
  }) {
    _mediaRef = mediaRef;
    _mediaTitle = mediaTitle;
    _season = season;
    _episode = episode;
    notifyListeners();
  }

  /// Host switches media mid-party.
  void switchMedia({
    required String mediaRef,
    String? mediaTitle,
    int? season,
    int? episode,
  }) {
    if (!inParty || !_isHost) return;
    _mediaRef = mediaRef;
    _mediaTitle = mediaTitle;
    _season = season;
    _episode = episode;
    notifyListeners();
  }

  void end() {
    _room = null;
    _isHost = false;
    _mediaRef = null;
    _mediaTitle = null;
    _season = null;
    _episode = null;
    notifyListeners();
    onSessionEnd?.call();
  }

  /// Canonical media ref builders (must match plan format).
  static String movieRef(String id) => 'tmdb:movie:$id';
  static String tvRef(String id, int season, int episode) =>
      'tmdb:tv:$id:S$season:E$episode';
  static String imdbRef(String imdbId) => 'imdb:$imdbId';

  /// Normalize a pasted/typed room code: trim + uppercase.
  static String normalizeCode(String raw) =>
      raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}
