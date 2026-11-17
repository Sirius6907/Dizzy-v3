/// Public tracker list used to seed every magnet the app hands to the
/// local torrent engine.
///
/// Why this exists: a magnet without `tr=` parameters is DHT-only. On a
/// cold swarm the engine has to find the first peer through the DHT
/// bootstrap nodes, which routinely takes 20-40 s (and often finds
/// nobody for niche/regional releases). That is exactly the state the
/// player used to sit in forever with "Gathering metadata & peers…".
///
/// The index sites (Knaben, TorrentGalaxy) put their own trackers in the
/// magnet link, but those are frequently stale, throttled or already
/// dead. Merging a small set of well-known public trackers guarantees
/// the engine has several announce endpoints to try, while the index
/// trackers are kept (they are the ones with the best seeders).
library;

/// Public trackers, best-known first. UDP trackers are the cheapest to
/// contact and do not need a TLS handshake.
const List<String> publicTrackers = <String>[
  'udp://tracker.opentrackr.org:1337/announce',
  'udp://tracker.openbittorrent.com:6969/announce',
  'udp://tracker.openbittorrent.com:80/announce',
  'udp://tracker.torrent.eu.org:451/announce',
  'udp://exodus.desync.com:6969/announce',
  'udp://tracker.empire-js.us:1337/announce',
  'udp://tracker.dler.org:6969/announce',
  'udp://open.stealth.si:80/announce',
  'udp://tracker.dtdub.com:1337/announce',
  'udp://tracker.internetwarriors.net:1337/announce',
  'udp://tracker.ip4fly.net:1337/announce',
  'udp://open.demonii.com:1337/announce',
  'http://tracker.opentrackr.org:1337/announce',
];

/// Normalised announce URL (scheme + host + path) used for dedup.
String _trackerKey(String tracker) {
  final t = tracker.trim().toLowerCase();
  final uri = Uri.tryParse(t);
  if (uri == null || uri.host.isEmpty) return t;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.isEmpty ? '/announce' : uri.path;
  return '${uri.scheme}://${uri.host}$port$path';
}

/// All `tr=` values already present in [magnet], in order.
List<String> magnetTrackers(String magnet) {
  final out = <String>[];
  for (final part in magnet.split('&')) {
    if (!part.startsWith('tr=')) continue;
    final value = Uri.decodeComponent(part.substring(3));
    if (value.isNotEmpty) out.add(value);
  }
  return out;
}

/// Returns [magnet] with the public trackers merged in.
///
/// Existing trackers are never removed and never reordered — the index
/// trackers usually know the release best. Missing public trackers are
/// appended. When the magnet already carries the same announce host on a
/// different scheme (udp vs http), that counts as present so the list
/// stays short.
///
/// A magnet that is not a magnet URI (a bare info hash) is returned
/// unchanged.
String magnetWithTrackers(String magnet) {
  if (!magnet.startsWith('magnet:')) return magnet;
  if (!magnet.contains('xt=urn:btih:')) return magnet;

  final existing = magnetTrackers(magnet);
  if (existing.isEmpty) {
    // No trackers at all: the DHT-only case this whole list exists for.
    final encoded = publicTrackers.map(Uri.encodeComponent).join('&tr=');
    return '$magnet&tr=$encoded';
  }

  // Compare on host, so udp://tracker.x:1337/announce and
  // http://tracker.x:1337/announce are treated as the same tracker.
  final existingHosts = existing
      .map((t) => _trackerKey(t).replaceFirst(RegExp(r'^\w+://'), ''))
      .toSet();

  final missing = publicTrackers.where((t) {
    final host = _trackerKey(t).replaceFirst(RegExp(r'^\w+://'), '');
    return !existingHosts.contains(host);
  }).toList();

  if (missing.isEmpty) return magnet;
  final encoded = missing.map(Uri.encodeComponent).join('&tr=');
  return '$magnet&tr=$encoded';
}
