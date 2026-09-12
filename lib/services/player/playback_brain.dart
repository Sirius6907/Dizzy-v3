/// P6 — DIZZY Player brain (smart layer over mpv).
///
/// mpv stays the decoder (it already beats VLC on compat). This brain owns:
///  - the playback state machine: idle → resolving → buffering → playing → error
///  - format fallback order: direct → HLS master → lower rendition → next source
///  - switch policy: how many auto-switches before handing choice to the user
///  - Easy-English error messages (never tech words in the UI).
///
/// Pure Dart — no Flutter import — so it unit-tests in milliseconds.
/// The UI (player_screen) keeps owning mpv; it only asks the brain
/// "what do I try next?" and "what do I tell the user?".
library;

/// Where playback currently stands. Allowed moves:
/// idle → resolving → buffering → playing ⇄ buffering (re-buffer)
/// any → error → resolving (retry) or error → idle (give up / reset).
enum PlaybackState { idle, resolving, buffering, playing, error }

/// What kind of playable a URL is, so the brain can order attempts.
enum SourceKind {
  /// Plain http(s) file (.mp4/.mkv/.webm …) — try first, cheapest to open.
  direct,

  /// HLS master playlist (.m3u8) — try second, adapts itself.
  hlsMaster,

  /// Torrent / magnet — needs peers, slow to start.
  torrent,

  /// Debrid-cached link — fast, treat like direct.
  debrid,

  /// Anything else / empty — last resort.
  unknown,
}

/// One quality level of a source. P9 fills these from HLS masters and
/// multi-file providers; P6 already understands them so P9 is pure wiring.
class BrainRendition {
  /// Display label, e.g. '1080p'. Never shown raw — UI maps it.
  final String label;

  /// Direct URL of this rendition.
  final String url;

  /// Bits per second when known, else 0 (sorts last among known ones).
  final int bitrate;

  const BrainRendition({
    required this.label,
    required this.url,
    this.bitrate = 0,
  });
}

/// One candidate video location the brain can attempt, in P9 mapped from
/// StreamSource (StreamSource.renditions lands here).
class BrainSource {
  /// Main playable URL (or magnet link).
  final String url;

  /// Override for tests / pre-classified links. Null = auto-detect.
  final SourceKind? kindOverride;

  /// Known renditions, best-first preferred. Empty = single-shot source.
  final List<BrainRendition> renditions;

  /// Friendly name for toasts, e.g. addon name. Never a URL.
  final String label;

  const BrainSource({
    required this.url,
    required this.label,
    this.kindOverride,
    this.renditions = const [],
  });

  /// Kind of the main URL (override wins, else sniffed from the URL).
  SourceKind get kind => kindOverride ?? PlaybackBrain.classifyUrl(url);
}

/// One concrete open attempt: a URL plus why the brain picked it.
class BrainAttempt {
  /// Index into the original source list (for failure tracking).
  final int sourceIndex;

  /// Exact URL to hand to mpv.
  final String url;

  /// Short reason for logs only, e.g. 'direct', 'hls-master', 'rendition-720p'.
  final String reason;

  const BrainAttempt({
    required this.sourceIndex,
    required this.url,
    required this.reason,
  });
}

/// The brain. One instance per playback session; call [reset] for a new video.
class PlaybackBrain {
  /// After this many auto-switches the brain stops and lets the user pick.
  /// (player_screen mirrors this with its own cap — keep them in sync.)
  static const int defaultMaxSwitches = 4;

  PlaybackState _state = PlaybackState.idle;
  PlaybackState get state => _state;

  /// URLs already proven dead this session (no retry — never loop forever).
  final Set<String> _failedUrls = {};

  /// How many auto-switches happened this session.
  int switches = 0;

  /// Last easy message produced (handy for tests / debugging).
  String lastEasyMessage = '';

  // ── State machine ────────────────────────────────────────────────

  static const _allowed = <PlaybackState, Set<PlaybackState>>{
    PlaybackState.idle: {PlaybackState.resolving},
    PlaybackState.resolving: {
      PlaybackState.buffering,
      PlaybackState.error,
      PlaybackState.idle,
    },
    PlaybackState.buffering: {
      PlaybackState.playing,
      PlaybackState.error,
      PlaybackState.resolving,
      PlaybackState.idle,
    },
    PlaybackState.playing: {
      PlaybackState.buffering,
      PlaybackState.error,
      PlaybackState.idle,
    },
    PlaybackState.error: {PlaybackState.resolving, PlaybackState.idle},
  };

  /// Move to [next] when the transition is legal; illegal moves are ignored
  /// (a stray late event must never corrupt state). Returns true if moved.
  bool move(PlaybackState next) {
    if (_allowed[_state]!.contains(next)) {
      _state = next;
      return true;
    }
    return false;
  }

  void startResolve() => move(PlaybackState.resolving);
  void onBuffering() => move(PlaybackState.buffering);
  void onPlaying() => move(PlaybackState.playing);

  /// Record a failure: enter [PlaybackState.error], remember the dead URL,
  /// and produce the Easy-English message for it.
  String onError(String rawError, {String? deadUrl}) {
    move(PlaybackState.error);
    if (deadUrl != null && deadUrl.isNotEmpty) _failedUrls.add(deadUrl);
    lastEasyMessage = easyErrorMessage(rawError);
    return lastEasyMessage;
  }

  /// Fresh video: forget failures and switches, back to idle.
  void reset() {
    _state = PlaybackState.idle;
    _failedUrls.clear();
    switches = 0;
    lastEasyMessage = '';
  }

  bool isUrlFailed(String url) => _failedUrls.contains(url);

  /// True while the brain may still auto-switch (cap not hit).
  bool canAutoSwitch({int maxSwitches = defaultMaxSwitches}) =>
      switches < maxSwitches;

  // ── Attempt planning: direct → HLS → lower rendition → next source ──

  /// Build the full ordered attempt list for [sources] (already ranked —
  /// the brain never re-ranks, it only orders formats inside each source).
  /// Dead URLs from this session are skipped.
  List<BrainAttempt> buildPlan(List<BrainSource> sources) {
    final plan = <BrainAttempt>[];
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      if (s.url.isEmpty || _failedUrls.contains(s.url)) continue;
      switch (s.kind) {
        case SourceKind.direct:
        case SourceKind.debrid:
        case SourceKind.unknown:
          plan.add(BrainAttempt(
              sourceIndex: i, url: s.url, reason: 'direct'));
          plan.addAll(_renditionAttempts(i, s));
          break;
        case SourceKind.hlsMaster:
          plan.add(BrainAttempt(
              sourceIndex: i, url: s.url, reason: 'hls-master'));
          plan.addAll(_renditionAttempts(i, s));
          break;
        case SourceKind.torrent:
          // Torrents start slow — main link first, renditions rarely
          // exist, but honour them when they do.
          plan.add(BrainAttempt(
              sourceIndex: i, url: s.url, reason: 'torrent'));
          plan.addAll(_renditionAttempts(i, s));
          break;
      }
    }
    // De-prioritise torrents behind http sources (instant feel first),
    // keeping original relative order inside each group (stable sort).
    plan.sort((a, b) {
      final aT = sources[a.sourceIndex].kind == SourceKind.torrent ? 1 : 0;
      final bT = sources[b.sourceIndex].kind == SourceKind.torrent ? 1 : 0;
      return aT.compareTo(bT);
    });
    return plan;
  }

  /// Renditions high → low (step DOWN through qualities on failure).
  /// Unknown-bitrate ones keep their given order at the end.
  List<BrainAttempt> _renditionAttempts(int index, BrainSource s) {
    if (s.renditions.isEmpty) return const [];
    final sorted = List<BrainRendition>.of(s.renditions);
    sorted.sort((a, b) {
      if (a.bitrate <= 0 && b.bitrate <= 0) return 0;
      if (a.bitrate <= 0) return 1;
      if (b.bitrate <= 0) return -1;
      return b.bitrate.compareTo(a.bitrate);
    });
    return [
      for (final r in sorted)
        if (r.url.isNotEmpty && !_failedUrls.contains(r.url))
          BrainAttempt(
              sourceIndex: index, url: r.url, reason: 'rendition-${r.label}'),
    ];
  }

  /// Next attempt after [failedUrl] died, or null when the plan is
  /// exhausted / the switch cap is hit (caller shows the source picker).
  /// Counts the switch so the cap is honoured.
  BrainAttempt? nextAfterFailure(
    List<BrainSource> sources,
    String failedUrl, {
    int maxSwitches = defaultMaxSwitches,
  }) {
    _failedUrls.add(failedUrl);
    if (!canAutoSwitch(maxSwitches: maxSwitches)) return null;
    final plan = buildPlan(sources);
    if (plan.isEmpty) return null;
    switches++;
    return plan.first;
  }

  // ── URL classification ───────────────────────────────────────────

  /// Sniff what kind of playable [url] is. Case-insensitive.
  static SourceKind classifyUrl(String url) {
    final u = url.trim().toLowerCase();
    if (u.isEmpty) return SourceKind.unknown;
    if (u.startsWith('magnet:') || u.contains('btih:')) {
      return SourceKind.torrent;
    }
    // Debrid-cache links behave like fast direct files.
    if (u.contains('real-debrid') ||
        u.contains('torbox') ||
        u.contains('alldebrid') ||
        u.contains('premiumize') ||
        u.contains('/debrid/')) {
      return SourceKind.debrid;
    }
    // Strip query/fragment before checking the extension.
    final path = u.split('?').first.split('#').first;
    if (path.endsWith('.m3u8')) return SourceKind.hlsMaster;
    if (path.endsWith('.mp4') ||
        path.endsWith('.mkv') ||
        path.endsWith('.webm') ||
        path.endsWith('.avi') ||
        path.endsWith('.mov') ||
        path.endsWith('.mpd')) {
      return SourceKind.direct;
    }
    if (u.startsWith('http')) return SourceKind.direct;
    return SourceKind.unknown;
  }

  // ── Easy-English errors (no tech words, ever) ────────────────────

  /// Map any raw player/ffmpeg/mpv error to one short friendly line.
  /// Every line promises the next step (try next / pick below) —
  /// the screen is never dead with nowhere to go.
  static String easyErrorMessage(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('subtitle') ||
        l.contains('.srt') ||
        l.contains('.vtt') ||
        l.contains('.ass')) {
      return 'Subtitles did not load, but the video will still play.';
    }
    if (l.contains('no such host') ||
        l.contains('failed to resolve') ||
        l.contains('network is unreachable') ||
        l.contains('no internet') ||
        l.contains('dns')) {
      return 'No internet right now. Check your connection, then try again.';
    }
    if (l.contains('timed out') ||
        l.contains('timeout') ||
        l.contains('connection reset') ||
        l.contains('connection closed') ||
        l.contains('eof') ||
        l.contains('end of file') ||
        l.contains('network')) {
      return 'Slow connection. Trying the next video…';
    }
    if (l.contains('403') || l.contains('forbidden') || l.contains('denied')) {
      return 'This video said no. Trying the next one…';
    }
    if (l.contains('404') || l.contains('not found') || l.contains('gone')) {
      return 'This video is gone. Trying the next one…';
    }
    if (l.contains('500') ||
        l.contains('502') ||
        l.contains('503') ||
        l.contains('server returned 5') ||
        l.contains('server error')) {
      return 'This video is having trouble. Trying the next one…';
    }
    if (l.contains('401') ||
        l.contains('unauthorized') ||
        l.contains('server returned 4')) {
      return 'This video needs a login we do not have. Trying the next one…';
    }
    if (l.contains('torrent') ||
        l.contains('magnet') ||
        l.contains('no seed') ||
        l.contains('peers')) {
      return 'Nobody is sharing this one right now. Trying the next one…';
    }
    if (l.contains('unsupported') ||
        l.contains('recognize file format') ||
        l.contains('could not open') ||
        l.contains('cannot open') ||
        l.contains('failed to open') ||
        l.contains('codec') ||
        l.contains('format')) {
      return 'This video type will not play here. Trying the next one…';
    }
    return 'This video will not play. Trying the next one…';
  }

  /// Shown when every source failed and auto-switching stops —
  /// always paired with the source picker, never a dead end.
  static String get allFailedMessage =>
      'Nothing played from the list. Pick another video below.';
}
