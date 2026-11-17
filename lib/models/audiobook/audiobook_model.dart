import '../../utils/text/html_entities.dart';

class Audiobook {
  final String uuid;
  final String audioBookId;
  final String dynamicSlugId;
  final String title;
  final String? author;
  final String coverImage;
  final String source;
  final String pageUrl;

  Audiobook({
    required this.uuid,
    required this.audioBookId,
    required this.dynamicSlugId,
    required String title,
    String? author,
    required String coverImage,
    required this.source,
    required this.pageUrl,
  })  : // The upstream catalogue ships HTML entities in the titles
        // ("The Baker Who&#8217;s 40% ..."), and they used to reach the
        // UI literally. The music side has decoded them for a long time
        // (lib/utils/text/html_entities.dart); the audiobook side did
        // not. Decoded HERE, in the constructor, so every construction
        // path is covered - the scraper builds these objects directly,
        // not through fromJson.
        title = unescapeHtmlEntities(title),
        author = author == null ? null : unescapeHtmlEntities(author),
        coverImage = coverImage.trim();

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'audioBookId': audioBookId,
    'dynamicSlugId': dynamicSlugId,
    'title': title,
    'author': author,
    'coverImage': coverImage,
    'source': source,
    'pageUrl': pageUrl,
  };

  factory Audiobook.fromJson(Map<String, dynamic> json) => Audiobook(
    uuid: (json['uuid'] ?? '').toString(),
    audioBookId: (json['audioBookId'] ?? '').toString(),
    dynamicSlugId: (json['dynamicSlugId'] ?? '').toString(),
    title: (json['title'] ?? '').toString(),
    author: json['author'] is String ? json['author'] as String : null,
    coverImage: (json['coverImage'] ?? '').toString().trim(),
    source: (json['source'] ?? '').toString(),
    pageUrl: (json['pageUrl'] ?? '').toString(),
  );
}

class AudiobookChapter {
  final String title;
  final String url;
  final Map<String, String>? httpHeaders;
  final bool isTorrent;
  final int? torrentFileIndex;

  AudiobookChapter({
    required this.title,
    required this.url,
    this.httpHeaders,
    this.isTorrent = false,
    this.torrentFileIndex,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'httpHeaders': httpHeaders,
    'isTorrent': isTorrent,
    'torrentFileIndex': torrentFileIndex,
  };

  factory AudiobookChapter.fromJson(Map<String, dynamic> json) =>
      AudiobookChapter(
        title: json['title'] ?? '',
        url: json['url'] ?? '',
        httpHeaders: (json['httpHeaders'] as Map?)?.cast<String, String>(),
        isTorrent: json['isTorrent'] ?? false,
        torrentFileIndex: json['torrentFileIndex'],
      );
}
