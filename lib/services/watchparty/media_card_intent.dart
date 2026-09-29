/// F4 — "Tap the card, land in the same room."
///
/// A friend sends you a title in a DM as a media card. One tap on that
/// card should put you both in the same room, watching (or listening to,
/// or reading) the same thing at the same spot.
///
/// The three ways to hang out map onto the three things Dizzy plays:
///
///   Watch   → 'video'  → movies and series
///   Listen  → 'audio'  → music and audiobooks
///   Read    → 'book'   → books and comics
///
/// Pure: the DM page only builds the intent and opens the modal. The
/// existing `kind: 'media_card'` bubble is not rebuilt — this is an
/// additive hook, not a rewrite.
library;

/// The three ways to watch something with someone.
///
/// Flutter-free on purpose (no `IconData` here) so this file can be unit
/// tested; the modal widget maps a mode to its own icon.
enum SyncMode {
  watch('video', 'Watch Together'),
  listen('audio', 'Listen Together'),
  read('book', 'Read Together');

  /// Wire value shared with `PartySession.mediaKind`.
  final String kind;

  /// Easy English label for the button.
  final String label;

  const SyncMode(this.kind, this.label);

  /// The mode a media type belongs to. Unknown types fall back to
  /// [SyncMode.watch], because a title is far more often watched than it
  /// is read and a wrong guess should still land the friend in a room.
  static SyncMode forMediaType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'music':
      case 'song':
      case 'album':
      case 'playlist':
      case 'audiobook':
      case 'audio':
      case 'podcast':
        return SyncMode.listen;
      case 'book':
      case 'comic':
      case 'manga':
      case 'novel':
        return SyncMode.read;
      default:
        return SyncMode.watch;
    }
  }
}

/// A card in a DM, reduced to what a room needs.
class MediaCardRef {
  final String mediaId;
  final String title;
  final String mediaType;
  final int? season;
  final int? episode;
  final String? posterUrl;

  const MediaCardRef({
    required this.mediaId,
    required this.title,
    required this.mediaType,
    this.season,
    this.episode,
    this.posterUrl,
  });

  /// The mode this card should open by default.
  SyncMode get mode => SyncMode.forMediaType(mediaType);

  /// The canonical room media ref, built by the same helpers the party
  /// engine already uses so a card and a room always agree on identity.
  String toMediaRef() {
    if (mediaId.startsWith('tt')) return 'imdb:$mediaId';
    final kind = mode == SyncMode.read ? 'book' : 'movie';
    if (season != null && episode != null) {
      return 'tmdb:tv:$mediaId:S$season:E$episode';
    }
    return 'tmdb:$kind:$mediaId';
  }

  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        'title': title,
        'mediaType': mediaType,
        'season': season,
        'episode': episode,
        'posterUrl': posterUrl,
      };

  /// A card we cannot read is dropped, not rendered as a blank bubble.
  static MediaCardRef? fromJson(Map<String, dynamic> json) {
    final id = json['mediaId']?.toString() ?? '';
    if (id.isEmpty) return null;
    final season = json['season'];
    final episode = json['episode'];
    return MediaCardRef(
      mediaId: id,
      title: json['title']?.toString() ?? '',
      mediaType: json['mediaType']?.toString() ?? 'movie',
      season: season is int ? season : int.tryParse(season?.toString() ?? ''),
      episode: episode is int ? episode : int.tryParse(episode?.toString() ?? ''),
      posterUrl: json['posterUrl']?.toString(),
    );
  }
}

/// Everything the room needs to open in sync, built once and handed to
/// the lobby. Deliberately a value type: it can be logged, diffed, and
/// unit tested without touching a socket.
class MediaCardIntent {
  final MediaCardRef card;
  final SyncMode mode;

  const MediaCardIntent({required this.card, required this.mode});

  factory MediaCardIntent.of(MediaCardRef card) =>
      MediaCardIntent(card: card, mode: card.mode);

  /// The line on the "join your friend" button for [m].
  String actionLineFor(SyncMode m) => switch (m) {
        SyncMode.watch => 'Watch with them',
        SyncMode.listen => 'Listen with them',
        SyncMode.read => 'Read with them',
      };

  /// The header of the modal. Never empty, even for a card with no title,
  /// because a blank modal looks broken.
  String get modalTitle {
    final t = card.title.trim();
    return t.isEmpty ? 'Join your friend' : 'Watch "$t" together';
  }

  Map<String, dynamic> toJson() => {
        'card': card.toJson(),
        'kind': mode.kind,
        'mediaRef': card.toMediaRef(),
      };
}
