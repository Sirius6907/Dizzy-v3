/// The probe's only screen: one TMDB target, one scraper, one player.
///
/// Reading order for anyone debugging a "video does not play" report:
///   1. the results list — what the scraper returned (shape + quality + URL),
///   2. the player — whether that URL opens inside the watchdog window,
///   3. the log — the exact open plan (URL and headers) that was handed to mpv.
///
/// Torrent sources are labelled but not opened (they need TorrServer, which
/// only the app runs). Embed sources play through the app's own ad-blocked
/// webview ([EmbedWebviewPlayer]): the page loads with the Rust engine
/// blocking ads, and the moment its media URL passes through, that URL is
/// handed to mpv with the same headers the shipped player would use.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mk;

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/pages/player/embed_webview_player.dart';
import 'package:dizzy/services/player/player_settings.dart';
import 'package:dizzy/services/scraper/stream_scraper.dart';
import 'package:dizzy/services/stream/stream_service.dart';

import 'probe_engine.dart';

/// Lifecycle of one target, from typed TMDB id to a first visible frame.
enum _Phase {
  idle('IDLE'),
  resolving('RESOLVING'),
  scraping('SCRAPING'),
  ready('READY'),
  opening('OPENING'),
  playing('PLAYING'),
  failed('FAILED');

  const _Phase(this.label);

  final String label;
}

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key});

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  /// A source that has not produced a frame by now is reported as failed:
  /// longer than this and the tester starts doubting the scraper, not mpv.
  static const Duration _openWatchdog = Duration(seconds: 25);

  static const Color _faint = Color(0xFF8B8B99);
  static const Color _panelColor = Color(0xFF16161C);
  static const Color _fieldColor = Color(0xFF1A1A22);
  static const Color _accent = Color(0xFF7C5CFF);
  static const Color _green = Color(0xFF3ECF8E);
  static const Color _amber = Color(0xFFE0B341);
  static const Color _red = Color(0xFFFF6B6B);
  static const Color _blue = Color(0xFF4FA3FF);

  final _tmdbIdCtrl = TextEditingController();
  final _seasonCtrl = TextEditingController(text: '1');
  final _episodeCtrl = TextEditingController(text: '1');
  final _filterCtrl = TextEditingController();
  final _logCtrl = ScrollController();

  final List<StreamScraper> _scrapers = StreamService.builtInHttpScrapers();
  late String _scraperName = _defaultScraperName();

  final _player = Player(
    configuration: PlayerSettings.getMediaKitPlayerConfiguration(),
  );
  late final mk.VideoController _videoController = mk.VideoController(
    _player,
    configuration: PlayerSettings.getVideoControllerConfiguration(),
  );

  StreamSubscription<String>? _errorSub;
  Timer? _ticker;

  ProbeKind _kind = ProbeKind.movie;
  ProbeMetadata? _meta;
  ProbeRun? _run;
  int? _openedIndex;
  String? _openedUrl;
  DateTime? _openedAt;
  bool _embedActive = false;
  _Phase _phase = _Phase.idle;
  String _detail = 'Pick a scraper, enter a TMDB id, then Resolve + Scrape.';

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _buffering = false;
  int? _videoWidth;
  int? _videoHeight;

  final List<String> _lines = [];

  bool get _isBusy =>
      _phase == _Phase.resolving ||
      _phase == _Phase.scraping ||
      _phase == _Phase.opening;

  @override
  void initState() {
    super.initState();
    _errorSub = _player.stream.error.listen(_onPlayerError);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => _onTick(),
    );
    _log(
      'Probe ready · ${_scrapers.length} HTTP scrapers · target watchdog '
      '${_openWatchdog.inSeconds}s',
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _errorSub?.cancel();
    _logCtrl.dispose();
    _tmdbIdCtrl.dispose();
    _seasonCtrl.dispose();
    _episodeCtrl.dispose();
    _filterCtrl.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  // ── player state ──────────────────────────────────────────────────────────

  void _onTick() {
    if (!mounted) return;
    final state = _player.state;
    final wasOpening = _phase == _Phase.opening;
    final openedAt = _openedAt;

    var phase = _phase;
    String? detail;
    var settled = false;

    if (wasOpening && openedAt != null) {
      final elapsed = DateTime.now().difference(openedAt);
      final hasVideo = state.width != null && state.height != null;
      if (state.playing && !state.buffering && (state.position > Duration.zero || hasVideo)) {
        phase = _Phase.playing;
        detail = '${state.width}x${state.height} · first frame in '
            '${elapsed.inMilliseconds}ms';
        settled = true;
        _persist('OPEN OK | $detail | ${_openedUrl ?? ''}');
      } else if (elapsed > _openWatchdog) {
        phase = _Phase.failed;
        detail = 'No video after ${_openWatchdog.inSeconds}s '
            '(buffering=${state.buffering}, '
            'pos=${state.position.inMilliseconds}ms, '
            'video=${state.width}x${state.height})';
        settled = true;
        unawaited(_player.stop());
        _persist('OPEN FAILED | $detail | ${_openedUrl ?? ''}');
        _log('FAILED · $detail');
      }
    }

    if (settled) _openedAt = null;

    setState(() {
      _phase = phase;
      if (detail != null) _detail = detail;
      _position = state.position;
      _duration = state.duration;
      _buffering = state.buffering;
      _videoWidth = state.width;
      _videoHeight = state.height;
    });

    if (settled && phase == _Phase.playing) {
      _log('PLAYING · $_detail');
    }
  }

  void _onPlayerError(String raw) {
    final message = raw.trim();
    if (message.isEmpty || !mounted) return;
    _log('MPV · $message');
    if (_phase != _Phase.opening) return;
    _openedAt = null;
    setState(() {
      _phase = _Phase.failed;
      _detail = 'mpv error: $message';
    });
    unawaited(_player.stop());
    _persist('OPEN FAILED | mpv: $message | ${_openedUrl ?? ''}');
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    if (!mounted) return;
    _openedAt = null;
    setState(() {
      _embedActive = false;
      _phase = _run == null ? _Phase.idle : _Phase.ready;
      _detail = 'Stopped';
      _position = Duration.zero;
      _duration = Duration.zero;
      _videoWidth = null;
      _videoHeight = null;
      _buffering = false;
    });
  }

  // ── scrape ────────────────────────────────────────────────────────────────

  Future<void> _resolveAndScrape() async {
    if (_isBusy) return;
    final tmdbId = int.tryParse(_tmdbIdCtrl.text.trim());
    if (tmdbId == null) {
      _snack('Enter a numeric TMDB id (movie 550, series 1399, …)');
      return;
    }
    final season = int.tryParse(_seasonCtrl.text.trim());
    final episode = int.tryParse(_episodeCtrl.text.trim());
    if (_kind.isSeries &&
        (season == null || episode == null || season < 1 || episode < 1)) {
      _snack('Series needs a season and an episode (1 or higher)');
      return;
    }
    final scraper = _scraperByName(_scraperName);
    if (scraper == null) {
      _snack('Pick a scraper first');
      return;
    }

    await _player.stop();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.resolving;
      _detail = 'TMDB ${_kind.label} $tmdbId';
      _meta = null;
      _run = null;
      _openedIndex = null;
      _openedUrl = null;
      _openedAt = null;
      _embedActive = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _videoWidth = null;
      _videoHeight = null;
    });
    _log('');
    _log('RESOLVE · ${_kind.label} $tmdbId');

    ProbeMetadata? meta;
    try {
      meta = await const ProbeMetadataResolver().resolve(
        tmdbId: tmdbId,
        kind: _kind,
      );
    } catch (e) {
      _log('RESOLVE FAILED · $e');
    }
    if (!mounted) return;
    if (meta == null) {
      setState(() {
        _phase = _Phase.failed;
        _detail = 'TMDB resolve failed for $tmdbId — wrong id or no network';
      });
      _persist('RESOLVE FAILED | ${_kind.label} $tmdbId');
      return;
    }

    setState(() {
      _meta = meta;
      _phase = _Phase.scraping;
      _detail = '${scraper.name} · ${meta!.title}';
    });
    _log('TITLE   · $meta');
    _log('SCRAPE  · ${scraper.name}');

    final run = await const SourceProbe().run(
      scraper: scraper,
      meta: meta,
      season: _kind.isSeries ? season : null,
      episode: _kind.isSeries ? episode : null,
    );
    if (!mounted) return;

    final hasSources = run.sources.isNotEmpty;
    setState(() {
      _run = run;
      _phase = hasSources
          ? _Phase.ready
          : (run.error != null ? _Phase.failed : _Phase.ready);
      _detail = run.error != null ? '$run.error' : run.summary;
    });
    _log(run.summary);
    for (var i = 0; i < run.sources.length; i++) {
      final source = run.sources[i];
      _log(
        '  #$i ${describeSource(source)} · '
        '${source.url ?? source.externalUrl ?? '(no url)'}',
      );
    }
    _persist(_scrapeLogLine(scraper.name, meta, run));
  }

  String _scrapeLogLine(String scraper, ProbeMetadata meta, ProbeRun run) {
    final season = _kind.isSeries ? _seasonCtrl.text.trim() : '-';
    final episode = _kind.isSeries ? _episodeCtrl.text.trim() : '-';
    final title = '${meta.title}${meta.year != null ? ' (${meta.year})' : ''}';
    return 'SCRAPE | $scraper | ${meta.scrapeType} s$season e$episode | '
        '$title | ${run.summary}';
  }

  // ── play ──────────────────────────────────────────────────────────────────

  Future<void> _play(int index) async {
    final run = _run;
    if (run == null || index < 0 || index >= run.sources.length) return;
    if (_phase == _Phase.opening) return;

    final source = run.sources[index];
    final shape = classifySource(source);

    if (shape == SourceShape.torrent) {
      _log('SKIP · TORRENT · ${describeSource(source)}');
      setState(() {
        _detail = 'TORRENT cannot open here — it needs TorrServer, which only '
            'the app runs. Embeds play ad-blocked in this probe.';
      });
      return;
    }

    if (shape == SourceShape.embed) {
      await _openEmbed(index, source);
      return;
    }

    final plan = buildOpenPlan(source);
    if (plan.url.isEmpty) {
      setState(() => _detail = 'Empty URL · ${describeSource(source)}');
      return;
    }

    await _openMediaUrl(
      index,
      plan.url,
      headers: plan.headers,
      shapeLabel: shape.label,
      isLive: plan.isLive,
    );
  }

  /// Opens an embed page in the app's own ad-blocked webview — the same
  /// [EmbedWebviewPlayer] widget the shipped player shows. When the page's
  /// media URL passes through, [_onEmbedCaptured] hands it to mpv; if the
  /// page never exposes one, the webview itself keeps playing (ad-free), so
  /// the probe still shows real, shipped behaviour.
  Future<void> _openEmbed(int index, StreamSource source) async {
    final embedUrl = ((source.externalUrl ?? source.url) ?? '').trim();
    if (embedUrl.isEmpty) {
      setState(() => _detail = 'EMBED with no URL · ${describeSource(source)}');
      return;
    }
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _openedIndex = index;
      _openedUrl = embedUrl;
      _embedActive = true;
      _phase = _Phase.opening;
      _detail = 'Opening embed (ad-blocked webview)…';
      _position = Duration.zero;
      _duration = Duration.zero;
      _videoWidth = null;
      _videoHeight = null;
      _buffering = false;
    });
    _log('EMBED   · #$index ${describeSource(source)}');
    _log('PAGE    · $embedUrl');
  }

  /// The embed page gave up its media URL: play it in mpv exactly like a
  /// direct source, with the Referer/User-Agent the webview used.
  Future<void> _onEmbedCaptured(CapturedMedia media) async {
    _log('CAPTURED · ${media.url}');
    _persist('EMBED CAPTURED | ${media.url}');
    if (!mounted) return;
    final index = _openedIndex;
    setState(() {
      _embedActive = false;
      _openedUrl = media.url;
    });
    await _openMediaUrl(
      index,
      media.url,
      headers: media.headers,
      shapeLabel: 'EMBED→MPV',
    );
  }

  /// The embed page failed to load in the webview.
  void _onEmbedGiveUp() {
    if (!mounted) return;
    _openedAt = null;
    setState(() {
      _embedActive = false;
      _phase = _Phase.failed;
      _detail = 'Embed page failed to load';
    });
    _persist('EMBED FAILED | ${_openedUrl ?? ''}');
  }

  /// Stops everything and opens [url] in mpv. One core so direct sources,
  /// FILE links and captured embed media all take the identical path — and a
  /// play failure is never a code-path difference between them.
  Future<void> _openMediaUrl(
    int? index,
    String url, {
    Map<String, String>? headers,
    required String shapeLabel,
    bool isLive = false,
  }) async {
    await _player.stop();
    if (!mounted) return;
    _openedAt = DateTime.now();
    setState(() {
      if (index != null) _openedIndex = index;
      _openedUrl = url;
      // Any previous embed webview must come down the moment a direct source
      // takes over — the webview sits on top of the mpv surface.
      _embedActive = false;
      _phase = _Phase.opening;
      _detail = 'Opening $shapeLabel…';
      _position = Duration.zero;
      _duration = Duration.zero;
      _videoWidth = null;
      _videoHeight = null;
      _buffering = false;
    });

    _log('OPEN    · #$index $shapeLabel');
    _log('URL     · $url');
    if (headers != null && headers.isNotEmpty) {
      _log(
        'HEADERS · ${headers.entries.map((e) => '${e.key}: ${e.value}').join(' | ')}',
      );
    }

    try {
      // Identical pre/post sequence to the app's `_initStream`: default audio
      // language, cache sizing and subtitle setup all come from the app.
      await PlayerSettings.applyPreOpenProperties(_player, isLive: isLive);
      await _player.open(
        Media(url, httpHeaders: headers),
        play: true,
      );
      await PlayerSettings.applyPostOpenProperties(_player);
      final volume = PlayerSettings.lastVolume.value;
      if (volume > 0 && volume < 1) {
        unawaited(_player.setVolume(volume * 100));
      }
    } catch (e) {
      if (!mounted) return;
      _openedAt = null;
      setState(() {
        _phase = _Phase.failed;
        _detail = 'open threw: $e';
      });
      _log('FAILED · open threw: $e');
      _persist('OPEN THREW | $e | $url');
    }
  }

  // ── log / persistence ─────────────────────────────────────────────────────

  void _log(String message) {
    if (message.isEmpty) {
      _lines.add('');
    } else {
      _lines.add('${_stamp().substring(11)}  $message');
    }
    if (_lines.length > 500) {
      _lines.removeRange(0, _lines.length - 500);
    }
    debugPrint('[probe] $message');
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logCtrl.hasClients) return;
      _logCtrl.jumpTo(_logCtrl.position.maxScrollExtent);
    });
  }

  void _persist(String line) {
    try {
      _logFile().writeAsStringSync(
        '${_stamp()} | $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // A read-only or missing folder must never break the probe itself.
    }
  }

  /// `probe_results.log` next to the exe, so a run can be replayed later
  /// without screenshots.
  File _logFile() {
    final exe = Platform.resolvedExecutable;
    final cut = exe.lastIndexOf(Platform.pathSeparator);
    final dir = cut > 0 ? exe.substring(0, cut) : Directory.current.path;
    return File('$dir${Platform.pathSeparator}probe_results.log');
  }

  String _stamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  Future<void> _copyReport() async {
    final buffer = StringBuffer()
      ..writeln('DIZZY SOURCE PROBE ${_stamp()}')
      ..writeln(
        'kind=${_kind.label} tmdb=${_tmdbIdCtrl.text.trim()} '
        'season=${_seasonCtrl.text.trim()} episode=${_episodeCtrl.text.trim()}',
      )
      ..writeln('scraper=$_scraperName');
    final meta = _meta;
    if (meta != null) buffer.writeln('meta=$meta');
    final run = _run;
    if (run != null) {
      buffer.writeln(run.summary);
      for (var i = 0; i < run.sources.length; i++) {
        final source = run.sources[i];
        buffer.writeln(
          '  #$i ${describeSource(source)} | '
          '${source.url ?? source.externalUrl ?? '(no url)'}',
        );
      }
    }
    buffer
      ..writeln('status=${_phase.label} | $_detail')
      ..writeln('opened=${_openedUrl ?? '-'}')
      ..writeln('--- log ---')
      ..writeln(_lines.join('\n'));

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    _snack('Report copied — paste it into chat');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  List<StreamScraper> get _visibleScrapers {
    final filter = _filterCtrl.text.trim().toLowerCase();
    if (filter.isEmpty) return _scrapers;
    return _scrapers
        .where(
          (s) =>
              s.name.toLowerCase().contains(filter) || s.name == _scraperName,
        )
        .toList();
  }

  StreamScraper? _scraperByName(String name) {
    for (final scraper in _scrapers) {
      if (scraper.name == name) return scraper;
    }
    return null;
  }

  String _defaultScraperName() {
    // Prefer scrapers with live-proven yield; fall back to registration order.
    for (final preferred in const ['a111477', 'lmscript', 'rivestream', 'vidfast']) {
      for (final scraper in _scrapers) {
        if (scraper.name == preferred) return preferred;
      }
    }
    return _scrapers.isEmpty ? '' : _scrapers.first.name;
  }

  String _scraperLabel(StreamScraper scraper) {
    final retired = StreamService.retiredScrapers.contains(scraper.name);
    return retired ? '${scraper.name}  ·  retired in app' : scraper.name;
  }

  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    if (url.isEmpty) return '(no url)';
    return url.length > 48 ? '${url.substring(0, 48)}…' : url;
  }

  static String _formatDuration(Duration d) {
    if (d == Duration.zero) return '--:--';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Color get _phaseColor => switch (_phase) {
    _Phase.idle => _faint,
    _Phase.resolving || _Phase.scraping || _Phase.opening => _amber,
    _Phase.ready => _blue,
    _Phase.playing => _green,
    _Phase.failed => _red,
  };

  BoxDecoration _panel({Color color = _panelColor, double radius = 14}) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }

  Widget _shapeChip(SourceShape shape) {
    final color = switch (shape) {
      SourceShape.hls => _green,
      SourceShape.dash => const Color(0xFF35C2C2),
      SourceShape.progressive => _blue,
      SourceShape.file => const Color(0xFF4FD1D9),
      SourceShape.local => const Color(0xFF9AA5FF),
      SourceShape.embed => _amber,
      SourceShape.torrent => const Color(0xFFB07CFF),
      SourceShape.unknown => _faint,
    };
    return Container(
      width: 64,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        shape.label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              _buildControls(),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: _buildResults()),
                    const SizedBox(width: 10),
                    Expanded(flex: 6, child: _buildPlayer()),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildLogPane(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: _phaseColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        const Text(
          'Dizzy · Source Probe',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${_scrapers.length} HTTP scrapers · one at a time · embeds play '
            'ad-blocked · torrents labelled only (TorrServer is app-only)',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: _faint),
          ),
        ),
        _pill(_phase.label, _phaseColor),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _copyReport,
          icon: const Icon(Icons.copy_all_rounded, size: 16),
          label: const Text('Copy report'),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      decoration: _panel(),
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 128,
            child: TextField(
              controller: _tmdbIdCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'TMDB id',
                hintText: '550',
              ),
              onSubmitted: (_) => _resolveAndScrape(),
            ),
          ),
          SegmentedButton<ProbeKind>(
            segments: const [
              ButtonSegment(
                value: ProbeKind.movie,
                label: Text('Movie'),
                icon: Icon(Icons.movie_outlined, size: 16),
              ),
              ButtonSegment(
                value: ProbeKind.series,
                label: Text('Series'),
                icon: Icon(Icons.live_tv_rounded, size: 16),
              ),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _kind = selection.first),
          ),
          SizedBox(
            width: 92,
            child: TextField(
              controller: _seasonCtrl,
              enabled: _kind.isSeries,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Season'),
            ),
          ),
          SizedBox(
            width: 92,
            child: TextField(
              controller: _episodeCtrl,
              enabled: _kind.isSeries,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Episode'),
            ),
          ),
          SizedBox(
            width: 150,
            child: TextField(
              controller: _filterCtrl,
              decoration: const InputDecoration(
                labelText: 'Filter scrapers',
                hintText: 'a111477',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: 250, child: _buildScraperDropdown()),
          FilledButton.icon(
            onPressed: _isBusy ? null : _resolveAndScrape,
            icon: _isBusy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore_rounded, size: 18),
            label: Text(_isBusy ? 'Working…' : 'Resolve + Scrape'),
          ),
          OutlinedButton.icon(
            onPressed: _stopPlayback,
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  Widget _buildScraperDropdown() {
    final items = _visibleScrapers;
    final selected = items.any((s) => s.name == _scraperName)
        ? _scraperName
        : null;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          hint: const Text(
            'Pick a scraper',
            style: TextStyle(fontSize: 13, color: _faint),
          ),
          dropdownColor: _fieldColor,
          menuMaxHeight: 420,
          style: const TextStyle(fontSize: 13, color: Colors.white),
          items: [
            for (final scraper in items)
              DropdownMenuItem(
                value: scraper.name,
                child: Text(
                  _scraperLabel(scraper),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _scraperName = value);
          },
        ),
      ),
    );
  }

  Widget _buildResults() {
    final run = _run;
    final summary = run == null
        ? 'No scrape yet'
        : (run.error != null && run.sources.isEmpty
              ? 'Error · ${run.error}'
              : run.summary);

    return Container(
      decoration: _panel(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.dns_outlined, size: 16, color: _faint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.white70,
                  ),
                ),
              ),
              if (run != null && run.sources.isNotEmpty)
                Text(
                  '${run.sources.length}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: _faint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: run == null || run.sources.isEmpty
                ? _buildEmptyResults(run)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 6),
                    itemCount: run.sources.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    itemBuilder: (context, index) =>
                        _buildSourceRow(index, run.sources[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults(ProbeRun? run) {
    final message = switch (run) {
      null => 'Pick a scraper, enter a TMDB id, then press Resolve + Scrape.',
      _ when run.error != null =>
        'Scraper failed before returning a source.\n\n${run.error}',
      _ =>
        'This scraper returned 0 sources for that target. That is a scraper '
            'result, not a player result.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: _faint, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildSourceRow(int index, StreamSource source) {
    final shape = classifySource(source);
    final opened = _openedIndex == index;
    final playing = opened && _phase == _Phase.playing;
    final playable = shape.opensInMpv || shape == SourceShape.embed;
    final title = (source.title ?? source.name ?? '').trim();
    final quality = source.quality;
    final host = _hostOf(source.url ?? source.externalUrl ?? '');

    return InkWell(
      onTap: playable ? () => _play(index) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: opened ? const Color(0xFF20202B) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: opened ? _accent.withValues(alpha: 0.7) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            _shapeChip(shape),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.isEmpty ? host : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (quality != null && quality.isNotEmpty) quality,
                      host,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: _faint),
                  ),
                ],
              ),
            ),
            if (playing)
              _pill('PLAYING', _green)
            else if (opened)
              _pill(_phase.label, _phaseColor),
            const SizedBox(width: 4),
            IconButton(
              tooltip: switch (shape) {
                SourceShape.torrent =>
                  '${shape.label} needs TorrServer — labelled only',
                _ => 'Open in ${shape.opensInMpv ? 'mpv' : 'ad-blocked webview'}',
              },
              onPressed: playable ? () => _play(index) : null,
              icon: Icon(
                playable
                    ? Icons.play_arrow_rounded
                    : Icons.block_rounded,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    final run = _run;
    final source = (run != null &&
            _openedIndex != null &&
            _openedIndex! < run.sources.length)
        ? run.sources[_openedIndex!]
        : null;

    return Container(
      decoration: _panel(color: Colors.black),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          mk.Video(
            controller: _videoController,
            controls: mk.NoVideoControls,
            fit: BoxFit.contain,
          ),
          if (_embedActive && source != null)
            // The app's own widget: ad-blocked (Rust engine) page load, and a
            // media capture that hands the URL back to mpv. Sits on top of
            // the (idle) mpv surface so a capture is seamless.
            Positioned.fill(
              child: EmbedWebviewPlayer(
                source: source,
                onMediaCaptured: (media) => unawaited(_onEmbedCaptured(media)),
                onGiveUp: _onEmbedGiveUp,
              ),
            ),
          if (_openedIndex == null)
            const Center(
              child: Text(
                'No source opened yet',
                style: TextStyle(fontSize: 12.5, color: _faint),
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _phaseColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${_phase.label} · $_detail',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (source != null)
                    Text(
                      describeSource(source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white70,
                      ),
                    ),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                      activeTrackColor: _accent,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      min: 0,
                      max: _duration.inMilliseconds > 0
                          ? _duration.inMilliseconds.toDouble()
                          : 1,
                      value: _duration.inMilliseconds > 0
                          ? _position.inMilliseconds
                                .clamp(0, _duration.inMilliseconds)
                                .toDouble()
                          : 0,
                      onChanged: _duration.inMilliseconds > 0
                          ? (value) => unawaited(
                              _player.seek(
                                Duration(milliseconds: value.round()),
                              ),
                            )
                          : null,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '${_formatDuration(_position)} / '
                        '${_formatDuration(_duration)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_buffering)
                        const Text(
                          'buffering',
                          style: TextStyle(fontSize: 11, color: _amber),
                        ),
                      const Spacer(),
                      Text(
                        [
                          if (_videoWidth != null && _videoHeight != null)
                            '${_videoWidth}x$_videoHeight',
                          if (_phase == _Phase.playing) 'mpv',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11, color: _faint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogPane() {
    return Container(
      height: 150,
      decoration: _panel(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Row(
              children: [
                const Text(
                  'Run log',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'probe_results.log is written next to the exe',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: _faint),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear log',
                  onPressed: () => setState(_lines.clear),
                  icon: const Icon(Icons.delete_outline, size: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: ListView.builder(
                controller: _logCtrl,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: _lines.length,
                itemBuilder: (context, index) => Text(
                  _lines[index],
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11.5,
                    height: 1.5,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
