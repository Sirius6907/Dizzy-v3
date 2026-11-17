import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../../utils/torrent/parse_torrent_title.dart';
import '../../../utils/torrent/title_core_match.dart';
import '../../errors/app_log.dart';

class KnabenScraper extends StreamScraper {
  @override
  String get name => 'knaben';

  @override
  bool get isTorrentScraper => true;

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    final sources = <StreamSource>[];

    // Search the CORE name ("Dahaan"), not the full catalogue name
    // ("Dahaan: The Evil Within"). The full string matches nothing in the
    // index, so every subtitled title used to come back with ZERO
    // torrents - a measured "sources kam" cause for regional titles.
    final coreTitle = TitleCoreMatch.core(title);
    String query = coreTitle.isEmpty ? title.trim() : coreTitle;
    if (type == 'movie' && year != null) {
      query += ' $year';
    } else if (type == 'series' && season != null) {
      final s = season.toString().padLeft(2, '0');
      query += ' s$s';
    }

    final encodedQuery = Uri.encodeComponent(query);
    final url = 'https://knaben.org/search/$encodedQuery/0/1/seeders';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return sources;

      final document = parser.parse(response.body);
      final rows = document.querySelectorAll('table tbody tr');

      final titleParser = ParseTorrentTitle();

      for (final row in rows) {
        final tdList = row.querySelectorAll('td');
        if (tdList.length < 6) continue;

        // Extract title (live structure 2026-10-10: full name in BOTH the
        // anchor text and its title attr; fall back to the attr so a
        // layout tweak never blanks the filter input).
        final titleNode = row.querySelector('.text-wrap.w-100 > a');
        var torrentName = titleNode?.text.trim() ?? '';
        torrentName = torrentName.isNotEmpty
            ? torrentName
            : (titleNode?.attributes['title']?.trim() ?? '');

        // Extract magnet
        final magnetNode = row.querySelector('a[href^="magnet:"]');
        final magnetUrl = magnetNode?.attributes['href'] ?? '';

        if (torrentName.isEmpty || magnetUrl.isEmpty) continue;

        // Extract size
        final sizeNode = tdList[2];
        final size = sizeNode.text.trim();

        // Extract seeders
        final seedersNode = tdList[4];
        final seedersText = seedersNode.text.trim().replaceAll(',', '');
        final seeders = int.tryParse(seedersText) ?? 0;

        // Filter out bad matches using ParseTorrentTitle
        final parsed = titleParser.parse(torrentName);
        final parsedTitle = (parsed['title'] ?? '').toString();

        // 1. Exact show/movie match filter
        // The release is indexed under its CORE name, and the catalogue
        // title may carry a subtitle ("Dahaan: The Evil Within" vs
        // "Dahaan (2026)"), so the two are compared on their cores. The
        // year (when the release states one) has to agree too - that is
        // what keeps a same-named older film out.
        final releaseYear = parsed['year'];
        final candidateYear = releaseYear is int ? releaseYear : null;
        if (!TitleCoreMatch.matches(
          requested: title,
          candidate: parsedTitle,
          year: year,
          candidateYear: candidateYear,
        )) {
          continue;
        }

        // 2. Series specific filtering
        if (type == 'series') {
          final parsedSeason = parsed['season'];
          final parsedEpisode = parsed['episode'];

          if (season != null &&
              parsedSeason != null &&
              parsedSeason != season) {
            continue;
          }
          // Only include if it's the specific episode OR a season pack (no episode specified)
          if (episode != null &&
              parsedEpisode != null &&
              parsedEpisode != episode) {
            continue;
          }
        }

        // Extract infoHash from magnet
        final match = RegExp(r'urn:btih:([a-zA-Z0-9]+)').firstMatch(magnetUrl);
        final infoHash = match?.group(1);

        if (infoHash == null) continue;

        // Extract trackers
        final trMatches = RegExp(r'&tr=([^&]+)').allMatches(magnetUrl);
        final trackers = trMatches
            .map((m) => 'tracker:${Uri.decodeComponent(m.group(1)!)}')
            .toList();

        sources.add(
          StreamSource(
            name: 'Knaben',
            addonName: 'knaben',
            title: '$torrentName\n$size 👥 $seeders',
            infoHash: infoHash,
            sources: trackers.isNotEmpty ? trackers : null,
          ),
        );
      }
    } catch (e) {
      AppLog.d('Knaben scrape error: $e');
    }

    return sources;
  }
}
