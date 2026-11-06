/// Torrent swarms for fake releases ship `.exe` payloads that look like a
/// 1080p episode. The player must never treat those as video.
abstract final class TorrentFileGuard {
  static const Set<String> videoExtensions = {
    'mkv',
    'mp4',
    'm4v',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm',
    'ts',
    'm2ts',
    'mpg',
    'mpeg',
    '3gp',
    'ogv',
  };

  static bool isVideo(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return videoExtensions.contains(path.substring(dot + 1).toLowerCase());
  }
}
