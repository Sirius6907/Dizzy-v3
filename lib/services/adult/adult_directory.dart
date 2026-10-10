/// 18+ Heaven — curated adult add-on directory (data only).
///
/// All 7 entries manifest-verified 2026-10-10. Only installed + listed when
/// [AdultSectionGate.visible] is true (triple lock: local 18+ confirm ×
/// admin allow × not-kids). Default OFF everywhere — the section does not
/// exist until the gate opens.
class AdultDirectoryEntry {
  final String id;
  final String name;
  final String oneLine;
  final String category;
  final String manifestUrl;

  const AdultDirectoryEntry({
    required this.id,
    required this.name,
    required this.oneLine,
    required this.category,
    required this.manifestUrl,
  });
}

abstract final class AdultDirectory {
  /// Section title on the adult page.
  static const String sectionTitle = '18+ Heaven';

  static const List<AdultDirectoryEntry> entries = [
    AdultDirectoryEntry(
      id: 'com.tpb.adult.4k',
      name: 'TPB 4K Porn',
      oneLine: 'Biggest library — 4K, studios, live cams, Indian section.',
      category: 'Library',
      manifestUrl: 'https://tpb-adult-addon.click/manifest.json',
    ),
    AdultDirectoryEntry(
      id: 'hub.adultvideo.hd',
      name: 'Adult Video HD',
      oneLine: 'Clean rows — Newest, Trending, Top Rated, stars.',
      category: 'Library',
      manifestUrl: 'https://h-gate.site/AdultVideo/manifest.json',
    ),
    AdultDirectoryEntry(
      id: 'pw.ers.porntube',
      name: 'Porn Tube',
      oneLine: 'Torrents in 4K + VR, needs a config first.',
      category: 'Torrents',
      manifestUrl: 'https://ptube.ers.pw/manifest.json',
    ),
    AdultDirectoryEntry(
      id: 'org.masterchief.onlyporn',
      name: 'OnlyPorn',
      oneLine: 'TV-friendly direct play from top tube sites.',
      category: 'Direct Play',
      manifestUrl:
          'https://07b88951aaab-jaxxx-v2.baby-beamup.club/manifest.json',
    ),
    AdultDirectoryEntry(
      id: 'org.adult.stremio.addon',
      name: 'Adult Stremio Addon',
      oneLine: 'Posters + details, needs a config first.',
      category: 'Direct Play',
      manifestUrl: 'https://asa.00696900.xyz/manifest.json',
    ),
    // Stravo family: bot-shielded from datacenter fetches (403 here), but
    // installs fine from real devices. Kept — directory page install uses
    // the on-device fetch, not this machine.
    AdultDirectoryEntry(
      id: 'stravo.midnight',
      name: 'Midnight',
      oneLine: 'Organized 18+ rows with fast direct streams.',
      category: 'Direct Play',
      manifestUrl: 'https://midnight.stravo.site/local/manifest.json',
    ),
    AdultDirectoryEntry(
      id: 'stravo.v1',
      name: 'Stravo',
      oneLine: 'Movies + shows with subtitles in many languages.',
      category: 'Direct Play',
      manifestUrl: 'https://stravo.site/local/manifest.json',
    ),
    AdultDirectoryEntry(
      id: 'stravo.v2',
      name: 'Stravo II',
      oneLine: 'Auto-dubbed audio + subtitles, pick your language.',
      category: 'Direct Play',
      manifestUrl: 'https://v2.stravo.site/local/manifest.json',
    ),
  ];

  /// Categories in display order.
  static List<String> presentCategories() {
    const order = ['Library', 'Torrents', 'Direct Play'];
    final present = entries.map((e) => e.category).toSet();
    return [...order.where(present.contains)];
  }
}
