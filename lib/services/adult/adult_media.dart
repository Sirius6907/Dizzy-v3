/// Pure "is this adult?" predicate used OUTSIDE the browse surfaces.
///
/// The home/search fan-out already excludes adult addons via
/// `AddonManager.isAdultAddon`, but a title that is playing, being saved to
/// Continue Watching, or teaching the taste engine never goes through that
/// fan-out again — it carries only an addon NAME (from the stream), a media
/// id and a type. This class answers the same question from those signals so
/// 18+ titles cannot leak into recents, genre taste, cloud sessions or
/// scrobbles.
///
/// Deliberately no fuzzy title matching: a title containing "jav" or
/// "adult" is not proof of anything ("Javelin", "Adulting"). Only addon
/// identity, id prefixes, content types and unambiguous hosts count.
///
/// No imports on purpose — this sits under services/adult and must not pull
/// in `AddonManager` (that would cycle through continue-watching).
abstract final class AdultMedia {
  /// Addon names / ids that are adult by themselves. Mirrors the marker set
  /// in `AddonManager.isAdultAddon` so both layers agree on identity.
  static const List<String> _nameMarkers = [
    'adult',
    'porn',
    'porntube',
    'onlyporn',
    'xxx',
    'jav',
    'hentai',
    'midnight',
    'stravo',
  ];

  /// Id prefixes issued by the 18+ catalog addons.
  static const List<String> _idPrefixes = ['asa:', 'tpb:'];

  /// Stremio content types that only exist in the adult addons.
  static const Set<String> _adultTypes = {
    'porn',
    'adultvideo',
    'xxx',
    'adult',
  };

  /// Manifest hosts of the curated 18+ directory.
  static const List<String> _adultHosts = [
    'tpb-adult-addon.click',
    'h-gate.site',
    'ptube.ers.pw',
    'asa.00696900.xyz',
    'midnight.stravo.site',
    'stravo.site',
    'v2.stravo.site',
  ];

  /// `baby-beamup.club` hosts MANY addons — only this path is adult, so the
  /// host alone must never be a match.
  static const String _sharedHost = 'baby-beamup.club';
  static const String _sharedAdultMarker = 'jaxxx';

  /// True when [name] (an addon manifest name, or a stream's `addonName`)
  /// carries an adult marker.
  static bool isAdultAddonName(String? name) {
    final n = (name ?? '').trim().toLowerCase();
    if (n.isEmpty) return false;
    return _nameMarkers.any(n.contains);
  }

  /// True when [id] was issued by an 18+ addon (`asa:…`, `tpb:…`).
  static bool isAdultMediaId(String? id) {
    final i = (id ?? '').trim().toLowerCase();
    if (i.isEmpty) return false;
    return _idPrefixes.any(i.startsWith);
  }

  /// True when [type] is an adult-only Stremio content type.
  static bool isAdultType(String? type) =>
      _adultTypes.contains((type ?? '').trim().toLowerCase());

  /// True when [url] points at a curated 18+ addon host.
  ///
  /// Sub-domains of a curated root (e.g. `cdn.stravo.site`) count; the
  /// shared `baby-beamup.club` host counts only with the jaxxx path.
  static bool isAdultUrl(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    final host = (uri?.host ?? '').toLowerCase();
    if (host.isEmpty) return false;

    if (host == _sharedHost || host.endsWith('.$_sharedHost')) {
      return host.contains(_sharedAdultMarker) ||
          (uri?.path.toLowerCase().contains(_sharedAdultMarker) ?? false);
    }

    for (final h in _adultHosts) {
      if (host == h || host.endsWith('.$h')) return true;
    }
    return false;
  }

  /// Combined verdict for playback/bookkeeping call sites.
  ///
  /// Any single adult signal is enough — this is fail-closed by design: a
  /// false positive only means one item is not remembered, a false negative
  /// would put 18+ content in the normal recents list.
  static bool isAdult({
    String? addonName,
    String? mediaId,
    String? type,
    Iterable<String?> urls = const [],
  }) {
    if (isAdultAddonName(addonName)) return true;
    if (isAdultMediaId(mediaId)) return true;
    if (isAdultType(type)) return true;
    for (final u in urls) {
      if (isAdultUrl(u)) return true;
    }
    return false;
  }
}
