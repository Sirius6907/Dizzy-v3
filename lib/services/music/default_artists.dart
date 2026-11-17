import '../../models/music/music_track.dart';

/// Approved default artist row (product override, 2026-11-12).
///
/// Round 2 removed fixed artist seeds so the home row could be purely
/// content-derived. The product owner has since specified an explicit
/// launch row for India, so this file is the ONE place those names may
/// live. Nothing here is content data: every entry is resolved to a real
/// catalog artist at fetch time, so faces, fan counts and spellings come
/// from the live API — never from this list.
///
/// [query] exists only because users type names the catalog spells
/// differently (`Krshna` → `Krsna`, `Honey Singh` → `Yo Yo Honey Singh`).
class DefaultArtist {
  final String displayName;

  /// The catalog search query used to resolve this entry. Defaults to
  /// [displayName] when the user-facing spelling already matches.
  final String query;

  const DefaultArtist(this.displayName, {String? query})
    : query = query ?? displayName;
}

/// The exact list the product owner specified, in the order they gave.
/// Order is meaningful: a cold start shows these in this sequence.
const List<DefaultArtist> kDefaultArtists = <DefaultArtist>[
  DefaultArtist('The Weeknd'),
  DefaultArtist('Arijit Singh'),
  DefaultArtist('Krshna', query: 'Krsna'),
  DefaultArtist('Anuv Jain'),
  DefaultArtist('Aditya Rihari', query: 'Aditya Rikhari'),
  DefaultArtist('Chaar Diwari', query: 'Chaar Diwaari'),
  DefaultArtist('Badshah'),
  DefaultArtist('Honey Singh', query: 'Yo Yo Honey Singh'),
  DefaultArtist('Beauz', query: 'BEAUZ'),
  DefaultArtist('Sanam', query: 'SANAM'),
  DefaultArtist('Akon'),
  DefaultArtist('Lady Gaga'),
  DefaultArtist('Lil Nas X'),
];

String _normArtist(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Picks the best catalog match for one default artist.
///
/// Deezer search ranks by relevance, which is right most of the time but
/// wrong for duplicated names (`Akon` has a 233-fan impostor above the
/// 4.7M-fan real profile; `SANAM` has an Iranian act above the Indian
/// band). The rule: keep only exact name matches when there are any,
/// then take the most-followed one. A name that doesn't exist in the
/// catalog falls back to the relevance-first hit, and an empty result
/// returns null so the caller simply skips the slot.
MusicArtist? pickDefaultArtistMatch(
  List<MusicArtist> candidates,
  String query,
) {
  if (candidates.isEmpty) return null;
  final target = _normArtist(query);
  final exact = candidates.where((a) => _normArtist(a.name) == target).toList();
  final pool = exact.isNotEmpty ? exact : candidates;
  pool.sort((a, b) => b.fanCount.compareTo(a.fanCount));
  return pool.first;
}
