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

  /// Unified co-experience state shared by Watch, Listen, and Read Together.
  /// mediaKind: 'video' | 'audio' | 'book'.
  String _mediaKind = 'video';
  int _chapterIndex = 0;
  int _pageIndex = 0;
  String? _trackId;

  WatchPartyRoom? get room => _room;
  bool get isHost => _isHost;
  String? get mediaRef => _mediaRef;
  String? get mediaTitle => _mediaTitle;
  int? get season => _season;
  int? get episode => _episode;

  String get mediaKind => _mediaKind;
  int get chapterIndex => _chapterIndex;
  int get pageIndex => _pageIndex;
  String? get trackId => _trackId;

  bool get inParty => _room != null;

  /// Host creates/owns the room. Media is optional (P1: rooms outlive titles).
  void startAsHost({
    required WatchPartyRoom room,
    String? mediaRef,
    String? mediaTitle,
    int? season,
    int? episode,
    String mediaKind = 'video',
    int chapterIndex = 0,
    int pageIndex = 0,
    String? trackId,
  }) {
    _room = room;
    _isHost = true;
    _mediaRef = mediaRef;
    _mediaTitle = mediaTitle;
    _season = season;
    _episode = episode;
    _mediaKind = mediaKind;
    _chapterIndex = chapterIndex;
    _pageIndex = pageIndex;
    _trackId = trackId;
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
    String? mediaKind,
    int? chapterIndex,
    int? pageIndex,
    String? trackId,
  }) {
    _mediaRef = mediaRef;
    _mediaTitle = mediaTitle;
    _season = season;
    _episode = episode;
    if (mediaKind != null) _mediaKind = mediaKind;
    if (chapterIndex != null) _chapterIndex = chapterIndex;
    if (pageIndex != null) _pageIndex = pageIndex;
    if (trackId != null) _trackId = trackId;
    notifyListeners();
  }

  /// Host switches media mid-party.
  void switchMedia({
    required String mediaRef,
    String? mediaTitle,
    int? season,
    int? episode,
    String? mediaKind,
    int? chapterIndex,
    int? pageIndex,
    String? trackId,
  }) {
    if (!inParty || !_isHost) return;
    _mediaRef = mediaRef;
    _mediaTitle = mediaTitle;
    _season = season;
    _episode = episode;
    if (mediaKind != null) _mediaKind = mediaKind;
    if (chapterIndex != null) _chapterIndex = chapterIndex;
    if (pageIndex != null) _pageIndex = pageIndex;
    if (trackId != null) _trackId = trackId;
    notifyListeners();
  }

  /// Shared co-experience updates (host or guest follow).
  void setMediaKind(String kind) {
    assert(kind == 'video' || kind == 'audio' || kind == 'book');
    if (_mediaKind == kind) return;
    _mediaKind = kind;
    notifyListeners();
  }

  void updateMediaKind(String kind) => setMediaKind(kind);

  void setChapterIndex(int index) {
    if (_chapterIndex == index) return;
    _chapterIndex = index;
    notifyListeners();
  }

  void updateChapterIndex(int index) => setChapterIndex(index);

  void setPageIndex(int index) {
    if (_pageIndex == index) return;
    _pageIndex = index;
    notifyListeners();
  }

  void updatePageIndex(int index) => setPageIndex(index);

  void setTrackId(String? id) {
    if (_trackId == id) return;
    _trackId = id;
    notifyListeners();
  }

  void updateTrackId(String? id) => setTrackId(id);

  /// Bulk sync for Watch/Listen/Read Together.
  void updateCoExperience({
    String? mediaKind,
    int? chapterIndex,
    int? pageIndex,
    String? trackId,
    bool clearTrack = false,
  }) {
    if (mediaKind != null) {
      assert(mediaKind == 'video' || mediaKind == 'audio' || mediaKind == 'book');
      _mediaKind = mediaKind;
    }
    if (chapterIndex != null) _chapterIndex = chapterIndex;
    if (pageIndex != null) _pageIndex = pageIndex;
    if (clearTrack) {
      _trackId = null;
    } else if (trackId != null) {
      _trackId = trackId;
    }
    notifyListeners();
  }

  void end() {
    _room = null;
    _isHost = false;
    _mediaRef = null;
    _mediaTitle = null;
    _season = null;
    _episode = null;
    _mediaKind = 'video';
    _chapterIndex = 0;
    _pageIndex = 0;
    _trackId = null;
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
