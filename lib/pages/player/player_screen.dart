import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit_video/media_kit_video.dart' as mk;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'package:dizzy/models/movie/video.dart';
import 'package:dizzy/models/movie/movie_detail.dart';
import 'package:dizzy/models/subtitle/subtitle_model.dart';
import 'package:dizzy/services/subtitles/subtitle_service.dart';
import 'package:dizzy/services/subtitles/subtitle_parser.dart';

import '../../models/stream/stream_model.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/stream/torrent_stream_service.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/player/player_settings.dart';
import '../../services/player/playback_brain.dart';
import '../../services/player/quality_service.dart';
import '../../services/player/bandwidth_meter.dart';
import '../../services/player/hls_rendition_parser.dart';
import '../../services/errors/app_error_log.dart';
import '../../services/discord/discord_rpc_service.dart';

import '../../widgets/player/player_glass.dart';
import '../../widgets/player/player_top_bar.dart';
import '../../widgets/player/player_transport.dart';
import '../../widgets/player/player_speed_menu.dart';
import '../../services/window/window_service.dart';
import '../../models/player/skip_segment_model.dart';
import '../../services/player/skip_segments_service.dart';
import '../../services/player/pip_service.dart';
import '../../widgets/player/player_aspect_menu.dart';
import '../../widgets/player/player_audio_menu.dart';
import '../../widgets/player/player_quality_menu.dart';
import '../../widgets/player/player_gesture_layer.dart';
import '../../widgets/player/player_lock_button.dart';
import '../../widgets/player/player_subtitle_menu.dart';
import '../../widgets/player/player_sub_style_modal.dart';
import '../../widgets/player/player_skip_button.dart';
import '../../widgets/player/player_episodes_panel.dart';
import '../../widgets/player/player_sources_panel.dart';
import '../../widgets/player/player_volume_control.dart';
import '../../widgets/player/sub_sync_bar.dart';
import '../../widgets/player/text_sync_overlay.dart';
import '../../models/download/download_task_model.dart';
import '../../services/download/download_service.dart';
import '../../utils/download/download_path_helper.dart';
import '../../services/stream/next_episode_engine.dart';
import '../../services/stream/source_ranker.dart';
import '../../services/stream/last_good_source_store.dart';
import '../../services/watchparty/party_session.dart';
import '../../services/watchparty/party_playback_session.dart';
import '../../services/system/resource_governor.dart';
import '../../widgets/player/next_episode_countdown.dart';
import '../../services/errors/app_log.dart';

class PlayerScreen extends StatefulWidget {
  final StreamSource source;
  final String title;
  final String? backdropUrl;
  final String? logoUrl;
  final MovieDetail? detail;
  final Video? episode;
  final Duration? initialPosition;
  /// Verified backup sources (from the probe race), used for silent
  /// failover when the current source stalls or dies mid-play.
  final List<StreamSource>? failoverSources;

  const PlayerScreen({
    super.key,
    required this.source,
    required this.title,
    this.backdropUrl,
    this.logoUrl,
    this.detail,
    this.episode,
    this.initialPosition,
    this.failoverSources,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late final Player _player = Player(configuration: PlayerSettings.getMediaKitPlayerConfiguration());
  late final mk.VideoController _videoController = mk.VideoController(
    _player,
    configuration: PlayerSettings.getVideoControllerConfiguration(),
  );
  final List<StreamSubscription> _subscriptions = [];

  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration?> _bufferNotifier = ValueNotifier<Duration?>(null);

  bool _isLoading = true;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _buffered;
  bool _isBuffering = false;
  bool _wasBuffering = false;
  DateTime _lastSeekAt = DateTime.now();

  void _onUserSeek(Duration target) {
    _lastSeekAt = DateTime.now();
    _lastProgressPosition = target;
    _lastProgressAt = DateTime.now();
  }
  String _statusMessage = 'Initializing...';
  bool _showControls = true;
  bool _isHoveringUI = false;
  Timer? _hideTimer;
  Timer? _progressSaveTimer;
  DateTime? _lastPointerTimerReset;
  late AnimationController _logoAnimController;

  // Active Menu / Popover
  String? _activeMenu; // 'subtitle' | 'audio' | 'quality' | 'speed' | 'aspect' | 'style' | null
  bool _showSubSyncBar = false;
  bool _showTextSyncOverlay = false;

  // P7 — manual quality (Auto default, per-device persisted).
  final QualityService _qualityService = QualityService();
  QualityChoice _qualityChoice = QualityChoice.auto;

  // P8 — auto quality by real speed (Auto mode only; manual wins).
  final BandwidthMeter _bandwidthMeter = BandwidthMeter();
  Timer? _autoQualityTimer;
  QualityChoice? _autoEffective;

  // P9 — rendition ladder fetch state (one flight per source).
  bool _renditionsFetching = false;

  // Playback & Audio State
  double _volume = 1.0;
  double _lastVolumeBeforeMute = 1.0;
  bool _isMuted = false;
  bool _showVolumeHud = false;
  Timer? _volumeHudTimer;
  double _playbackRate = 1.0;
  BoxFit _videoFit = BoxFit.contain;
  List<PlayerAudioTrack> _audioTracks = [];

  // Party sync (v1.2.0-T2.8) — null when not in a Watch Together room.
  PartyPlaybackSession? _partySession;

  // Lock mode (v1.1.8) — swallows all player-area input when locked.
  bool _isLocked = false;
  int _selectedAudioTrackIndex = 0;
  double _audioDelaySec = 0.0;
  bool _showAudioHud = false;
  String _audioHudText = '';
  Timer? _audioHudTimer;

  // Subtitle State
  List<SubtitleLanguageGroup> _subtitleGroups = [];
  List<PlayerEmbeddedSubtitle> _embeddedSubtitles = [];
  int? _selectedEmbeddedSubtitleIndex;
  SubtitleVariant? _currentSubtitleVariant;
  bool _isSubtitleEnabled = false;
  String? _currentSubtitlePath;
  List<SubCue> _currentCues = [];
  SubFormat _currentSubFormat = SubFormat.srt;
  double _subtitleDelayMs = 0;
  double _subtitleScale = 1.0;

  // Skip Segments State (IntroDB)
  List<MediaSkipSegment> _skipSegments = [];
  MediaSkipSegment? _activeSkipSegment;
  bool _showSkipButton = false;
  final Set<String> _dismissedSegmentKeys = {};

  // Episodes & Sources Side Panels State
  late StreamSource _currentSource;
  Video? _currentEpisode;
  late String _currentTitle;
  bool _showEpisodesPanel = false;
  bool _showSourcesPanel = false;
  Video? _sourcesEpisode;
  String? _sourcesErrorMessage;
  final Map<String, List<StreamSource>> _cachedSourcesByEpisode = {};

  // Next-episode autoplay (Phase 2)
  final NextEpisodeEngine _nextEpisodeEngine = NextEpisodeEngine();
  bool _showNextEpisodeCountdown = false;

  // Resource governor: live RAM/VRAM/CPU budget enforcement (max 3GB/2.5GB/20%)
  ResourceLevel _resourceLevel = ResourceLevel.normal;

  // ── Silent Failover (Phase 3.2) ────────────────────────────────────────
  /// Sources verified by the probe race that opened this player, ranked
  /// best→worst. Used to silently switch when the current source stalls.
  List<StreamSource> _failoverChain = [];
  /// Completes when the ranked chain is ready (v1.1.9: stall watchdog waits
  /// for this so an early stall never fires with zero backups).
  Future<void>? _failoverReady;
  final Set<String> _failedFingerprints = {}; // this-session only
  int _failoverSwitches = 0;
  static const int _maxFailoverSwitches = 3;
  bool _failoverInProgress = false;
  Timer? _stallWatchdog;
  Duration _lastProgressPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  /// Failover resume override — passed straight into Media(start:) so the
  /// backup source opens AT the saved position (no seek-after-open race on
  /// slow networks where mpv would drop the seek fired before media load).
  Duration? _resumeAtOverride;
  /// 30s of stable playback on current source → record last-good + start prefetch
  Timer? _lastGoodTimer;
  bool _lastGoodRecorded = false;
  /// Phase 5 gate: prefetch starts only after 25%/3min threshold.
  bool _prefetchStarted = false;

  @override
  void initState() {
    super.initState();
    _currentSource = widget.source;
    _currentEpisode = widget.episode;
    _currentTitle = widget.title;
    // v1.1.9: restore last-used volume (persisted via PlayerSettings).
    _volume = PlayerSettings.lastVolume.value.clamp(
        0.0, PlayerVolumeControl.maxVolume);
    if (_volume == 0) _volume = 1.0;

    // P7: restore saved quality choice (per-device, Auto default).
    unawaited(_qualityService.load().then((c) {
      if (mounted) setState(() => _qualityChoice = c);
    }));

    // P8: 2s speed probe — fires only on a stable 10s window, Auto mode only.
    _autoQualityTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _autoQualityTick());

    // Build the ranked failover chain (Phase 3.2): backups exclude the
    // primary source, ordered by SourceRanker with persisted history.
    if (widget.failoverSources != null && widget.failoverSources!.isNotEmpty) {
      _failoverReady = () async {
        final detail = widget.detail;
        Map<String, String> history = const {};
        if (detail != null) {
          final titleKey = 'dizzy:${detail.id}';
          final ep = widget.episode;
          history = await LastGoodSourceStore.addonHistoryFor(
            titleKey: titleKey,
            episodeKey: (ep != null)
                ? '$titleKey:S${ep.season}E${ep.episode}'
                : null,
          );
        }
        final primaryFp = SourceRanker.fingerprint(widget.source);
        final candidates = widget.failoverSources!
            .where((s) => SourceRanker.fingerprint(s) != primaryFp)
            .toList();
        _failoverChain = SourceRanker.order(
          candidates,
          RankerContext(
            lastGoodByAddon: history,
            failedThisSession: _failedFingerprints,
          ),
        );
        AppLog.d('[Failover] chain ready: ${_failoverChain.length} backups ranked');
      }();
    }

    WakelockPlus.enable();
    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Resource governor: enforce RAM/VRAM/CPU budgets live during playback.
    ResourceGovernor.instance.playbackActive = true;
    ResourceGovernor.instance.anime4kActive =
        PlayerSettings.anime4kPreset.value != Anime4KPreset.off;
    ResourceGovernor.instance.start();
    ResourceGovernor.instance.level.addListener(_onResourceLevelChanged);
    _resourceLevel = ResourceGovernor.instance.level.value;
    if (_resourceLevel != ResourceLevel.normal) {
      _applyResourceLevel(_resourceLevel); // already under pressure
    }

    PlayerSettings.changeNotifier.addListener(_onPlayerSettingsChanged);

    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _isPlaying = playing);
          _updateDiscordRpc(isPaused: !playing);
          if (!playing) {
            // v1.1.9 (Task 16): pause = flush dirty progress immediately.
            _savePlaybackProgress();
            unawaited(ContinueWatchingService.flushProgress());
          }
        }
      }),
      _player.stream.position.listen((pos) {
        _position = pos;
        _positionNotifier.value = pos;
        _onPlaybackTick(pos);
        // ── Stall watchdog: position changing (forward or backward) = healthy.
        final diff = (pos - _lastProgressPosition).inMilliseconds.abs();
        if (diff >= 200) {
          _lastProgressPosition = pos;
          _lastProgressAt = DateTime.now();
        }
        // ── Prefetch gate (Phase 5) ── start next-episode prefetch only
        // after 25% watched OR 3 min elapsed (quick-bouncers save bandwidth).
        // Data Saver (v1.1.8) disables prefetch entirely — mobile-data
        // users pay only for what they actually watch.
        // v1.1.9 (Task 19): verified correct — comment only, no change.
        if (!_prefetchStarted &&
            PlayerSettings.nextEpisodeAutoPlay.value &&
            !PlayerSettings.dataSaver.value) {
          final dur = _player.state.duration;
          final watched25 = dur.inSeconds >= 4 &&
              pos.inSeconds >= (dur.inSeconds * 0.25).ceil();
          final elapsed3min = pos.inSeconds >= 180;
          if (watched25 || elapsed3min) {
            _prefetchStarted = true;
            _startNextEpisodePrefetch();
          }
        }
      }),
      _player.stream.duration.listen((dur) {
        if (mounted) {
          setState(() => _duration = dur);
          _updateDiscordRpc();
        }
      }),
      _player.stream.buffer.listen((buf) {
        _buffered = buf;
        _bufferNotifier.value = buf;
      }),
      _player.stream.buffering.listen((isBuffering) {
        _isBuffering = isBuffering;
        // Slow-net guard: while mpv is actively buffering (spinner showing),
        // the stall watchdog must NOT fire — the demuxer is still feeding
        // data and a source switch would only lose buffered progress.
        if (isBuffering) {
          _lastProgressAt = DateTime.now();
        }
        if (_wasBuffering && !isBuffering && PlayerSettings.autoResyncOnStall.value) {
          try {
            if (PlayerSettings.hardwareAudioClock.value) {
              final np = _player.platform as dynamic;
              np.setProperty('video-sync', 'audio');
            }
          } catch (_) {}
        }
        _wasBuffering = isBuffering;
      }),
      _player.stream.tracks.listen((tracks) {
        _updateMediaTracks(tracks);
      }),
      _player.stream.track.listen((track) {
        if (!mounted) return;
        final aid = track.audio.id;
        final idx = int.tryParse(aid);
        if (idx != null && _selectedAudioTrackIndex != idx) {
          setState(() => _selectedAudioTrackIndex = idx);
        }
      }),
      _player.stream.error.listen((error) {
        _onControllerError(error);
      }),
      _player.stream.completed.listen((completed) {
        if (completed && mounted) {
          _savePlaybackProgress();
          _onPlaybackCompleted();
        }
      }),
    ]);

    _initStream();
    _startPartySync();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// v1.2.0-T2.8: wire Watch Together sync (no-op when not in a party).
  /// Host broadcasts state; guest silently follows. Player-agnostic session
  /// gets thin callbacks into media_kit — nothing else in init changes.
  void _startPartySync() {
    final s = PartySession.instance;
    if (!s.inParty) return;
    _partySession = PartyPlaybackSession(
      getPositionMs: () => _player.state.position.inMilliseconds,
      isPlaying: () => _player.state.playing,
      getSpeed: () => _playbackRate,
      seekToMs: (ms) async {
        await _player.seek(Duration(milliseconds: ms));
      },
      setPlaying: (play) async {
        if (play) {
          await _player.play();
        } else {
          await _player.pause();
        }
      },
      onToast: _partyToast,
      onGuestMediaSwitch: (msg) async {
        final title = (msg.mediaTitle ?? '').trim();
        _partyToast(title.isEmpty
            ? 'Host switched movie — open it to rejoin sync.'
            : 'Host is playing $title — opening it for you…');
      },
    );
    _partySession!.start();
    // v1.2.0-P2: host announces what just opened (any title, unlimited/room).
    _announceHostMedia();
  }

  /// True when this device follows the host (controls locked, banner shown).
  bool get _partyGuestLocked =>
      PartySession.instance.inParty && !PartySession.instance.isHost;

  /// v1.2.0-P2: canonical ref for what THIS player shows right now
  /// (movie / episode). Null when detail is missing (e.g. deep-link file).
  String? _partyRefForCurrent() {
    final d = widget.detail;
    if (d == null) return null;
    if (d.id.startsWith('tt')) return PartySession.imdbRef(d.id);
    final tmdb = d.tmdbId ?? d.id;
    final ep = _currentEpisode ?? widget.episode;
    if (ep != null) {
      return PartySession.tvRef(tmdb, ep.season ?? 1, ep.episode ?? 1);
    }
    return PartySession.movieRef(tmdb);
  }

  /// v1.2.0-P2: host tells the room "I am playing X now".
  /// Guests get media_switch + DB row; auto-open itself lands in P3.
  void _announceHostMedia({bool prefetchReady = false}) {
    final s = PartySession.instance;
    if (!s.inParty || !s.isHost || _partySession == null) return;
    final ref = _partyRefForCurrent();
    if (ref == null || ref == s.mediaRef) return; // no-op: same title
    final ep = _currentEpisode ?? widget.episode;
    unawaited(_partySession!.announceMedia(
      ref: ref,
      title: _currentTitle,
      season: ep?.season,
      episode: ep?.episode,
      prefetchReady: prefetchReady,
    ));
  }

  /// P10: countdown just appeared → the next episode is ~5s away. Tell
  /// guests EARLY (preview-only, `ready:true`) so they pre-resolve metadata
  /// and the real switch opens in ~1s. Local state/DB untouched.
  void _announcePrefetchHint() {
    final s = PartySession.instance;
    if (!s.inParty || !s.isHost || _partySession == null) return;
    final d = widget.detail;
    final nextEp = _nextEpisodeEngine.prefetchedEpisode;
    if (d == null || nextEp == null) return;
    final String ref;
    if (d.id.startsWith('tt')) {
      ref = PartySession.imdbRef(d.id);
    } else {
      ref = PartySession.tvRef(
          d.tmdbId ?? d.id, nextEp.season ?? 1, nextEp.episode ?? 1);
    }
    if (ref == s.mediaRef) return;
    unawaited(_partySession!.announceMedia(
      ref: ref,
      title: _currentTitle,
      season: nextEp.season,
      episode: nextEp.episode,
      prefetchReady: true,
      previewOnly: true,
    ));
  }

  void _partyToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// v1.2.0-T2.8: party banner pill (Easy English, non-tech).
  /// Host sees LIVE pill; guest sees locked-controls note.
  Widget _buildPartyBanner() {
    final isHost = PartySession.instance.isHost;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 56,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: (isHost
                      ? const Color(0xFFE5484D)
                      : const Color(0xFF7C5CFF))
                  .withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isHost
                  ? '🔴 LIVE • Watch Together'
                  : 'Host controls play. You control sound + chat.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _initStream() async {
    String? streamUrl;

    AppLog.d('[PlayerScreen] Initializing playback:');
    AppLog.d('[PlayerScreen]   Title: $_currentTitle');
    AppLog.d('[PlayerScreen]   Source Name: ${_currentSource.name}');
    AppLog.d('[PlayerScreen]   Addon Name: ${_currentSource.addonName}');
    AppLog.d('[PlayerScreen]   Source Title: ${_currentSource.title}');
    AppLog.d('[PlayerScreen]   Raw URL: ${_currentSource.url}');

    try {
      final rawUrl = _currentSource.url;

      // Handle offline downloaded file playback directly
      if (rawUrl != null && (File(rawUrl).existsSync() || _currentSource.name == 'Downloaded')) {
        AppLog.d('[PlayerScreen] Initializing offline local file playback: $rawUrl');
        await PlayerSettings.applyPreOpenProperties(_player);
        await _player.open(Media(rawUrl), play: true);
        await PlayerSettings.applyPostOpenProperties(_player);
        _setSubtitleScale(_subtitleScale);
        _applyVolume(_isMuted ? 0.0 : _volume, persist: false);
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final infoHash = _currentSource.infoHash;
      final isMagnetUrl = rawUrl != null && rawUrl.startsWith('magnet:');
      final isTorrent = (infoHash != null && infoHash.isNotEmpty) || isMagnetUrl;

      if (isTorrent) {
        String magnet;
        if (isMagnetUrl) {
          magnet = rawUrl;
        } else {
          magnet = 'magnet:?xt=urn:btih:$infoHash';
          if (_currentSource.sources != null) {
            for (final source in _currentSource.sources!) {
              if (source.startsWith('tracker:')) {
                final trackerUrl = source.replaceFirst('tracker:', '');
                magnet += '&tr=${Uri.encodeComponent(trackerUrl)}';
              }
            }
          }
        }

        final useDebrid = await DebridService().isDebridActiveForStreams();
        final seasonNum = _currentEpisode?.season;
        final episodeNum = _currentEpisode?.episode;
        final epTitle = _currentEpisode?.title;

        if (useDebrid) {
          final activeService = await DebridService().getSelectedService();
          if (!mounted) return;
          setState(() => _statusMessage = 'Using $activeService for files...');

          final debridFiles = await DebridService().resolveMagnet(
            magnet: magnet,
            fileIndex: _currentSource.fileIdx,
            filename: _currentTitle,
            season: seasonNum,
            episode: episodeNum,
            episodeTitle: epTitle,
          );

          if (debridFiles.isEmpty || debridFiles.first.downloadUrl.isEmpty) {
            throw Exception('$activeService returned no direct stream links.');
          }

          streamUrl = debridFiles.first.downloadUrl;
          AppLog.d('[PlayerScreen] Debrid resolved stream URL: $streamUrl');
        } else {
          if (!mounted) return;
          setState(() => _statusMessage = 'Gathering metadata & peers...');

          streamUrl = await TorrentStreamService().streamTorrent(
            magnet,
            season: seasonNum,
            episode: episodeNum,
            episodeTitle: epTitle,
            fileIdx: _currentSource.fileIdx,
          );
        }
      } else if (rawUrl != null && rawUrl.isNotEmpty) {
        streamUrl = rawUrl;
      } else {
        throw Exception('No valid stream source found.');
      }

      if (streamUrl == null) throw Exception('Stream URL is null');

      final sanitizedUrlStr = streamUrl.contains('::')
          ? streamUrl.replaceAll('::', '%3A%3A')
          : streamUrl;

      // Automatically resolve complete CDN headers (Referer, Origin, User-Agent)
      final playerHeaders = PlayerSettings.resolveStreamHeaders(
        sanitizedUrlStr,
        _currentSource.headers,
      );

      // Also merge any proxyHeaders from behaviorHints if present
      final proxyReqHeaders = _currentSource.behaviorHints?['proxyHeaders']?['request'];
      if (proxyReqHeaders is Map) {
        playerHeaders.addAll(Map<String, String>.from(proxyReqHeaders));
      }

      final cleanUri = Uri.parse(sanitizedUrlStr);
      AppLog.d('[PlayerScreen] Opening direct network stream URL: $cleanUri (headers: ${playerHeaders.keys})');

      if (!mounted) return;
      final epLabel = _currentEpisode != null
          ? 'S${_currentEpisode!.season ?? 1}:E${_currentEpisode!.episode ?? 1} - ${_currentEpisode!.title.isNotEmpty ? _currentEpisode!.title : "Episode ${_currentEpisode!.episode ?? 1}"}'
          : (widget.detail?.name ?? _currentTitle);
      setState(() => _statusMessage = 'Buffering $epLabel...');

      final lowerClean = sanitizedUrlStr.toLowerCase();
      final bool isLive = _currentSource.behaviorHints?['isLive'] == true ||
          _currentSource.addonName.toLowerCase() == 'iptv' ||
          _currentSource.name?.toLowerCase() == 'iptv' ||
          lowerClean.contains('/live/') ||
          lowerClean.contains('/hls/live');

      final bool isTorrentStream = isTorrent ||
          sanitizedUrlStr.contains(':8090') ||
          sanitizedUrlStr.contains('/stream?link=') ||
          sanitizedUrlStr.contains('/stream?');

      await PlayerSettings.applyPreOpenProperties(_player, isLive: isLive, isTorrent: isTorrentStream);

      // Set native MPV properties for referer and user-agent directly on the player for web streams
      if (!isTorrentStream) {
        try {
          final dynamic platform = _player.platform;
          if (platform != null) {
            final referer = playerHeaders['Referer'] ?? playerHeaders['referer'];
            if (referer != null && referer.isNotEmpty) {
              await platform.setProperty('referrer', referer);
            }
            final ua = playerHeaders['User-Agent'] ?? playerHeaders['user-agent'];
            if (ua != null && ua.isNotEmpty) {
              await platform.setProperty('user-agent', ua);
            }
            final cookie = playerHeaders['Cookie'] ?? playerHeaders['cookie'];
            if (cookie != null && cookie.isNotEmpty) {
              await platform.setProperty('cookies', 'yes');
              await platform.setProperty('http-header-fields', 'Cookie: $cookie');
            }
          }
        } catch (e) {
          AppLog.d('[PlayerScreen] Warning setting native header properties: $e');
        }
      }

      await _player.open(
        Media(
          cleanUri.toString(),
          httpHeaders: isTorrentStream ? null : playerHeaders,
          start: _resumeAtOverride ?? widget.initialPosition,
        ),
        play: true,
      );

      await PlayerSettings.applyPostOpenProperties(_player);

      _setSubtitleScale(_subtitleScale);
      _applyVolume(_isMuted ? 0.0 : _volume, persist: false);

      AppLog.d('[PlayerScreen SUCCESS] Player opened media successfully for $streamUrl');

      _updateMediaTracks(_player.state.tracks);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      _player.play();
      _startHideControlsTimer();

      // Defer background services until after playback starts
      Future.microtask(() {
        if (!mounted) return;
        _armPlaybackGuards();
        _fetchSkipSegments();
        _fetchInitialSubtitles();
        // NOTE: next-episode prefetch is gated (Phase 5) — starts at 25%
        // watched / 3 min from the position listener, not here.

        final detail = widget.detail;
        if (detail != null) {
          final targetId = detail.id.startsWith('tt') ? detail.id : (detail.tmdbId ?? detail.id);
          if (targetId.isNotEmpty) {
            final s = _currentEpisode?.season;
            final e = _currentEpisode?.episode;
            final initPos = widget.initialPosition?.inSeconds ?? 0;
            final dur = _player.state.duration.inSeconds;
            final progress = (dur > 0 ? (initPos / dur) * 100.0 : 0.0).clamp(0.0, 100.0);

            TraktService.instance.isAuthenticated().then((authed) {
              if (authed) {
                TraktService.instance.scrobbleStart(targetId, progress, season: s, episode: e);
              }
            });
            SimklService.instance.isAuthenticated().then((authed) {
              if (authed) {
                SimklService.instance.scrobbleStart(targetId, progress, season: s, episode: e);
              }
            });
          }
        }
      });

      _progressSaveTimer?.cancel();
      _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _savePlaybackProgress();
      });
    } catch (e, stackTrace) {
      AppLog.d('[PlayerScreen ERROR] Failed to initialize stream URL: "$streamUrl"');
      AppLog.d('[PlayerScreen ERROR] Exception: $e');
      AppLog.d('[PlayerScreen ERROR] StackTrace:\n$stackTrace');

      if (!mounted) return;

      // If we have an episode context (TV show), reopen the sources panel with error notice!
      if (_currentEpisode != null && widget.detail?.videos.isNotEmpty == true) {
        setState(() {
          _isLoading = false;
          _showSourcesPanel = true;
          _sourcesEpisode = _currentEpisode;
          _sourcesErrorMessage = 'Source failed to play. Please select another source below.';
        });
        return;
      }

      String displayMessage = 'Error: $e';
      if (e is PlatformException &&
          (e.message?.contains('invalid or unsupported media') ?? false)) {
        displayMessage =
            'Media Open Error: Stream server quota exceeded or invalid media format.\nPlease select another stream.';
      }

      setState(() {
        _statusMessage = displayMessage;
      });
    }
  }

  void _updateMediaTracks(Tracks tracks) {
    if (!mounted) return;
    final audioList = tracks.audio;
    final audioTracks = <PlayerAudioTrack>[];
    for (int i = 0; i < audioList.length; i++) {
      final t = audioList[i];
      if (t.id == 'no' || t.id == 'auto') continue;
      final lang = t.language;
      final title = t.title ?? (lang != null ? lang.toUpperCase() : 'Track ${i + 1}');
      final idx = int.tryParse(t.id) ?? (i + 1);
      audioTracks.add(PlayerAudioTrack(
        index: idx,
        title: title,
        language: lang,
        channels: int.tryParse(t.channels?.toString() ?? ''),
      ));
    }

    final subList = tracks.subtitle;
    final embeddedSubs = <PlayerEmbeddedSubtitle>[];
    for (int i = 0; i < subList.length; i++) {
      final t = subList[i];
      if (t.id == 'no' || t.id == 'auto') continue;
      final lang = t.language;
      final title = t.title ?? (lang != null ? lang.toUpperCase() : 'Track ${i + 1}');
      final idx = int.tryParse(t.id) ?? (i + 1);
      embeddedSubs.add(PlayerEmbeddedSubtitle(
        index: idx,
        title: title,
        language: lang,
      ));
    }

    int activeIdx = _selectedAudioTrackIndex;
    if (activeIdx == 0 && audioTracks.isNotEmpty) {
      final activeAid = _player.state.track.audio.id;
      activeIdx = int.tryParse(activeAid) ?? audioTracks.first.index;
    }

    setState(() {
      _audioTracks = audioTracks;
      _embeddedSubtitles = embeddedSubs;
      if (_selectedAudioTrackIndex == 0 && audioTracks.isNotEmpty) {
        _selectedAudioTrackIndex = activeIdx;
      }
    });
  }

  static String cleanMediaTitle(String raw) {
    var name = raw;
    name = name.replaceAll(RegExp(r'\.(mkv|mp4|avi|webm|ts|mov|m4v|srt|vtt)$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[._]'), ' ');
    name = name.replaceAll(RegExp(r'\b(2160p|1080p|720p|480p|4k|uhd|ds4k|webrip|web-dl|bluray|brrip|h264|x264|h265|x265|hevc|10bit|ddp5\.1|dd5\.1|atmos|aac|ac3|dts|flac|remux|hdr|dv|proper|repack|hdtv)\b', caseSensitive: false), ' ');
    name = name.replaceAll(RegExp(r'-[a-zA-Z0-9]+$'), '');
    return name.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _fetchInitialSubtitles() async {
    try {
      int? searchYear;
      if (widget.detail?.year != null && widget.detail!.year!.isNotEmpty) {
        final yMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(widget.detail!.year!);
        if (yMatch != null) searchYear = int.tryParse(yMatch.group(1)!);
      }
      final rawName = widget.detail?.name ?? widget.title;
      if (searchYear == null) {
        final yMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(rawName);
        if (yMatch != null) searchYear = int.tryParse(yMatch.group(1)!);
      }
      final showName = cleanMediaTitle(rawName);
      AppLog.d('[PlayerScreen] Scraping initial subtitles for "$showName" (year: $searchYear, imdb: ${widget.detail?.id})...');

      final groups = await SubtitleService().fetchAllSubtitles(
        showName,
        imdbId: widget.detail?.id,
        season: _currentEpisode?.season,
        episode: _currentEpisode?.episode,
        year: searchYear,
      );
      AppLog.d('[PlayerScreen] Scraped ${groups.length} subtitle language groups with ${groups.fold(0, (s, g) => s + g.variants.length)} total variants');
      if (mounted && groups.isNotEmpty) {
        setState(() => _subtitleGroups = groups);

        // Auto-load matching language subtitle for the new episode if subtitles were enabled
        if (_isSubtitleEnabled && _currentSubtitleVariant != null) {
          final previousLang = _currentSubtitleVariant!.language.toLowerCase();
          final matchingGroup = groups.firstWhere(
            (g) => g.language.toLowerCase() == previousLang,
            orElse: () => groups.firstWhere(
              (g) => g.language.toLowerCase().contains('english') || g.language.toLowerCase() == 'en',
              orElse: () => groups.first,
            ),
          );
          if (matchingGroup.variants.isNotEmpty) {
            _loadSubtitle(matchingGroup.variants.first);
          }
        }
      }
    } catch (e) {
      AppLog.d('[PlayerScreen] Error loading subtitles: $e');
    }
  }

  void _startHideControlsTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          _isPlaying &&
          !_isHoveringUI &&
          _activeMenu == null &&
          !_showSubSyncBar &&
          !_showTextSyncOverlay) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_showTextSyncOverlay || _activeMenu != null) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _handlePointerActivity() {
    if (_isLoading) return;
    if (!_showControls) setState(() => _showControls = true);

    final now = DateTime.now();
    if (_lastPointerTimerReset == null ||
        now.difference(_lastPointerTimerReset!) >= const Duration(milliseconds: 250)) {
      _lastPointerTimerReset = now;
      _startHideControlsTimer();
    }
  }

  void _toggleMenu(String menuName) {
    setState(() {
      if (_activeMenu == menuName) {
        _activeMenu = null;
        _startHideControlsTimer();
      } else {
        _activeMenu = menuName;
        _showSubSyncBar = false;
        _showTextSyncOverlay = false;
        _hideTimer?.cancel();
      }
    });
  }

  void _selectEmbeddedSubtitle(PlayerEmbeddedSubtitle embedded) {
    setState(() {
      _selectedEmbeddedSubtitleIndex = embedded.index;
      _currentSubtitleVariant = SubtitleVariant(
        providerName: 'Embedded',
        language: embedded.language ?? 'Embedded',
        title: embedded.title,
        downloadUrl: '',
        format: 'ass',
      );
      _isSubtitleEnabled = true;
      _currentSubtitlePath = null;
      _currentCues = [];
    });

    _player.setSubtitleTrack(SubtitleTrack(embedded.index.toString(), embedded.title, embedded.language));
    _setSubtitleScale(_subtitleScale);
    PlayerSettings.applySubtitleStyling(_player);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to embedded subtitle: ${embedded.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _disableSubtitles() {
    setState(() {
      _isSubtitleEnabled = false;
      _currentSubtitleVariant = null;
      _selectedEmbeddedSubtitleIndex = null;
      _currentSubtitlePath = null;
      _currentCues = [];
    });
    _player.setSubtitleTrack(SubtitleTrack.no());
  }

  Future<void> _loadSubtitle(SubtitleVariant variant) async {
    _currentSubtitleVariant = variant;
    _selectedEmbeddedSubtitleIndex = null;
    _isSubtitleEnabled = true;
    _player.setSubtitleTrack(SubtitleTrack.no());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${variant.language} subtitle...'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final path = await SubtitleService().downloadSubtitle(variant);
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download subtitle')),
        );
      }
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final content = SubtitleParser.decodeBytesWithFallback(bytes);
        final parseResult = SubtitleParser.parse(content);
        _currentCues = parseResult.cues;
        _currentSubFormat = parseResult.format;
      }
    } catch (e) {
      AppLog.d('[PlayerScreen] Subtitle cues parse error: $e');
    }

    _currentSubtitlePath = path;
    final resolvedUri = _resolveSubtitleUri(path);
    _player.setSubtitleTrack(SubtitleTrack.uri(resolvedUri, title: variant.language));
    _setSubtitleScale(_subtitleScale);
    PlayerSettings.applySubtitleStyling(_player);

    if (_subtitleDelayMs != 0) {
      await _applyLiveDelay(_subtitleDelayMs / 1000.0);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${variant.language} subtitle loaded (${_currentCues.length} lines)'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _resolveSubtitleUri(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    try {
      final file = File(pathOrUrl);
      if (file.existsSync()) {
        final canonicalPath = file.resolveSymbolicLinksSync();
        return Uri.file(canonicalPath).toString();
      }
    } catch (_) {}

    final uri = Uri.tryParse(pathOrUrl);
    if (uri != null && uri.hasScheme && !(Platform.isWindows && RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(pathOrUrl))) {
      return pathOrUrl;
    }
    return Uri.file(pathOrUrl).toString();
  }

  void _setSubtitleScale(double scale) {
    final clamped = scale.clamp(0.5, 3.0);
    setState(() => _subtitleScale = clamped);
    PlayerSettings.setSubScale(clamped, player: _player);
  }

  Future<void> _applyLiveDelay(double delaySec) async {
    _subtitleDelayMs = delaySec * 1000.0;
    final np = _player.platform as dynamic;
    try {
      np.setProperty('sub-delay', delaySec.toString());
    } catch (e) {
      AppLog.d('[PlayerScreen] applyLiveDelay error: $e');
    }
  }

  Future<void> _saveTextSyncedCues(List<SubCue> syncedCues, double offsetSec) async {
    _currentCues = syncedCues;
    _subtitleDelayMs = 0.0; // Reset live delay since timestamps are now permanently baked into cues
    if (_currentSubtitlePath != null) {
      final content = _currentSubFormat == SubFormat.vtt
          ? SubtitleParser.toVtt(syncedCues)
          : SubtitleParser.toSrt(syncedCues);
      final ext = _currentSubFormat == SubFormat.vtt ? 'vtt' : 'srt';
      final cleanBase = _currentSubtitlePath!.replaceAll(
        RegExp(r'(_delayed.*|_synced.*)?\.(srt|vtt)$', caseSensitive: false),
        '',
      );
      final newPath = '${cleanBase}_synced_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(newPath).writeAsString(content, flush: true);
      _currentSubtitlePath = newPath;
      final resolvedUri = _resolveSubtitleUri(newPath);
      _player.setSubtitleTrack(SubtitleTrack.uri(resolvedUri));
      _setSubtitleScale(_subtitleScale);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subtitle timing synchronized and saved!')),
        );
      }
    }
  }

  void _onControllerError(dynamic err) {
    if (!mounted) return;
    final errorMsg = err.toString();
    final lower = errorMsg.toLowerCase();

    // 1. Subtitle track loading errors - non-fatal, notify user briefly without interrupting playback
    if (lower.contains('can not open external file') ||
        lower.contains('subtitle') ||
        lower.contains('sub-add') ||
        lower.contains('.srt') ||
        lower.contains('.vtt') ||
        lower.contains('.ass')) {
      AppLog.d('[PlayerScreen] Ignored non-fatal subtitle warning: $errorMsg');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(PlaybackBrain.easyErrorMessage(errorMsg)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // 2. Ignore non-fatal MPV/FFmpeg network and demuxer warnings (e.g. "tcp: ffurl_read returned 0xffffff99")
    if (PlayerSettings.isNonFatalError(err)) {
      AppLog.d('[PlayerScreen] Ignored non-fatal player warning: $errorMsg');
      return;
    }

    // 3. Active playback protection:
    // Only routine non-fatal hiccups during ongoing playback (where media has actively loaded and progressed)
    // should be suppressed. Startup errors where media has not loaded must trigger error handling.
    final bool hasActivelyProgressed = _duration > Duration.zero &&
        (_position > Duration.zero || _player.state.position > Duration.zero) &&
        (_isPlaying || _player.state.playing);

    final bool isFatalOpenFailure = lower.contains('failed to open') ||
        lower.contains('cannot open') ||
        lower.contains('could not open') ||
        lower.contains('failed to recognize file format') ||
        lower.contains('unsupported file format') ||
        lower.contains('server returned 4') ||
        lower.contains('server returned 5') ||
        lower.contains('failed to resolve') ||
        lower.contains('no such host');

    // Slow-net guard: transient network blips (timeout / reset / EOF) during
    // ACTIVE playback with buffer headroom must not trigger a source switch —
    // mpv's cache keeps playing while the demuxer retries. Only switch when
    // the blip comes with zero buffer headroom (true death).
    final bool isTransientNetBlip = lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('averror_eof') ||
        lower.contains('end of file');
    final bufferHeadroom = (_buffered?.inMilliseconds ?? 0) -
        _player.state.position.inMilliseconds;

    if (hasActivelyProgressed && (!isFatalOpenFailure ||
        (isTransientNetBlip && bufferHeadroom > 3000))) {
      AppLog.d('[PlayerScreen WARNING] Ignored player warning during active playback: $errorMsg');
      return;
    }

    // 4. Critical error on dead stream — try silent failover FIRST if a
    // ranked backup chain exists; fall back to source picker when exhausted.
    AppLog.d('[PlayerScreen ERROR] Critical player error on dead stream: $errorMsg');

    _failedFingerprints.add(SourceRanker.fingerprint(_currentSource));
    if (_failoverChain.where((s) => !_failedFingerprints.contains(SourceRanker.fingerprint(s))).isNotEmpty &&
        PlayerSettings.autoFailover.value) {
      _attemptSilentFailover(reason: 'error: ${errorMsg.substring(0, errorMsg.length > 60 ? 60 : errorMsg.length)}');
      return;
    }

    if (_currentEpisode != null && widget.detail?.videos.isNotEmpty == true) {
      setState(() {
        _isLoading = false;
        _showSourcesPanel = true;
        _sourcesEpisode = _currentEpisode;
        _sourcesErrorMessage =
            '${PlaybackBrain.easyErrorMessage(errorMsg)} Please pick another video below.';
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _statusMessage = PlaybackBrain.easyErrorMessage(errorMsg);
    });
  }

  void _applyVolume(double vol, {bool showHud = false, bool persist = true}) {
    final clamped = ((vol * 100).round() / 100.0).clamp(0.0, PlayerVolumeControl.maxVolume);
    setState(() {
      _volume = clamped;
      _isMuted = clamped == 0;
      if (showHud) _showVolumeHud = true;
    });

    if (showHud) {
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }

    _player.setVolume(clamped * 100.0);
    // v1.1.9: remember last non-zero volume for next open (fire-and-forget).
    if (persist && clamped > 0) {
      unawaited(PlayerSettings.setLastVolume(clamped));
    }
  }

  void _toggleMute({bool showHud = false}) {
    if (_volume > 0 && !_isMuted) {
      _lastVolumeBeforeMute = _volume;
      setState(() {
        _isMuted = true;
        if (showHud) _showVolumeHud = true;
      });
      _player.setVolume(0.0);
    } else {
      final restore = _lastVolumeBeforeMute > 0 ? _lastVolumeBeforeMute : 1.0;
      setState(() {
        _volume = restore;
        _isMuted = false;
        if (showHud) _showVolumeHud = true;
      });
      _player.setVolume(restore * 100.0);
    }

    if (showHud) {
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }
  }

  void _togglePlayPause() {
    // v1.2.0-T2.8: guest follows host — local toggle locked with easy note.
    if (_partyGuestLocked) {
      _partyToast('Host controls play. You control sound + chat.');
      return;
    }
    _player.playOrPause();
    // v1.2.0-T2.8: host action → immediate broadcast (no 500ms wait).
    if (PartySession.instance.inParty) {
      unawaited(_partySession?.sendAction(
        _player.state.playing ? 'pause' : 'play',
      ));
    }
    _startHideControlsTimer();
  }

  void _seekRelative(Duration offset) {
    // v1.2.0-T2.8: guest seek locked — host seeks, guest auto-follows.
    if (_partyGuestLocked) {
      _partyToast('Host controls play. You control sound + chat.');
      return;
    }
    final cur = _player.state.position;
    final dur = _player.state.duration;
    final target = cur + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (dur > Duration.zero && target > dur ? dur : target);
    _onUserSeek(clamped);
    _player.seek(clamped);
    // v1.2.0-T2.8: host seek → immediate broadcast so guests jump together.
    if (PartySession.instance.inParty) {
      unawaited(_partySession?.sendAction(
        'seek',
        positionMs: clamped.inMilliseconds,
      ));
    }
    _startHideControlsTimer();
  }

  void _toggleEpisodesPanel() {
    setState(() {
      _showEpisodesPanel = !_showEpisodesPanel;
      if (_showEpisodesPanel) {
        _showSourcesPanel = false;
        _activeMenu = null;
        _showSubSyncBar = false;
        _showTextSyncOverlay = false;
        _showControls = true;
      }
    });
  }

  void _onEpisodeChosen(Video episode) {
    setState(() {
      _showEpisodesPanel = false;
      _showSourcesPanel = true;
      _sourcesEpisode = episode;
      _sourcesErrorMessage = null;
      _activeMenu = null;
      _showControls = true;
    });
  }

  void _onBackToEpisodes() {
    setState(() {
      _showSourcesPanel = false;
      _showEpisodesPanel = true;
      _sourcesErrorMessage = null;
    });
  }

  void _playNewSource(StreamSource newSource, Video episode) {
    setState(() {
      _showSourcesPanel = false;
      _showEpisodesPanel = false;
      _sourcesErrorMessage = null;
    });
    _switchStream(newSource, episode);
  }

  void _switchStream(StreamSource newSource, Video newEpisode) async {
    _progressSaveTimer?.cancel();
    _savePlaybackProgress();

    final prevVariant = _currentSubtitleVariant;
    final wasSubEnabled = _isSubtitleEnabled;

    setState(() {
      _currentSource = newSource;
      _currentEpisode = newEpisode;
      final showName = widget.detail?.name ?? widget.title;
      final epNum = newEpisode.episode ?? 1;
      final sNum = newEpisode.season ?? 1;
      _currentTitle = '$showName - S${sNum}E$epNum ${newEpisode.title}';
      _isLoading = true;
      _statusMessage = 'Buffering S$sNum:E$epNum - ${newEpisode.title.isNotEmpty ? newEpisode.title : "Episode $epNum"}...';
      _showEpisodesPanel = false;
      _showSourcesPanel = false;
      _activeMenu = null;
      _showSubSyncBar = false;
      _showTextSyncOverlay = false;
      _showSkipButton = false;
      _activeSkipSegment = null;
      _skipSegments = [];
      _subtitleGroups = [];
      _currentSubtitlePath = null;
      _currentCues = [];
      _currentSubtitleVariant = prevVariant;
      _isSubtitleEnabled = wasSubEnabled;
    });

    // Cleanup previous torrent engine if was P2P
    TorrentStreamService().cleanup();

    _initStream();

    // Episode changed via panel — re-arm the gated prefetch for THIS
    // episode's successor (fires at 25%/3min into the new episode).
    _prefetchStarted = false;
  }

  void _fetchSkipSegments() async {
    try {
      final detail = widget.detail;
      final showName = widget.detail?.name ?? widget.title;
      final skipData = await SkipSegmentsService.instance.fetchSkipSegments(
        tmdbId: detail?.tmdbId,
        imdbId: (detail != null && detail.id.startsWith('tt')) ? detail.id : null,
        title: showName,
        year: int.tryParse(detail?.year ?? ''),
        type: detail?.type ?? (_currentEpisode != null ? 'tv' : 'movie'),
        season: _currentEpisode?.season,
        episode: _currentEpisode?.episode,
        durationMs: _player.state.duration.inMilliseconds,
      );

      if (skipData != null && mounted) {
        setState(() {
          _skipSegments = skipData.segments;
        });
      }
    } catch (e) {
      AppLog.d('[PlayerScreen] Error loading skip segments: $e');
    }
  }

  void _onPlaybackTick(Duration pos) {
    if (_skipSegments.isEmpty) return;

    final dur = _player.state.duration;

    MediaSkipSegment? matched;
    for (final seg in _skipSegments) {
      if (seg.contains(pos, dur)) {
        matched = seg;
        break;
      }
    }

    if (matched != null) {
      if (!_dismissedSegmentKeys.contains(matched.uniqueKey)) {
        // F2 (v1.1.9): auto-skip intro/recap when the user opted in.
        // Credits/preview never auto-skip (credits go to next-ep handoff).
        final t = matched.type.toLowerCase();
        final autoOn = (t == 'intro' && PlayerSettings.autoSkipIntro.value) ||
            (t == 'recap' && PlayerSettings.autoSkipRecap.value);
        if (autoOn) {
          _handleSkipSegment(matched);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Skipped ${t[0].toUpperCase()}${t.substring(1)} ⏭️'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        if (_activeSkipSegment?.uniqueKey != matched.uniqueKey) {
          setState(() {
            _activeSkipSegment = matched;
            _showSkipButton = true;
          });
        }
      }
    } else {
      if (_activeSkipSegment != null) {
        setState(() {
          _activeSkipSegment = null;
          _showSkipButton = false;
        });
      }
    }
  }

  void _handleSkipSegment(MediaSkipSegment seg) {
    _dismissedSegmentKeys.add(seg.uniqueKey);

    // ── Credits/Outro → jump straight to next-episode handoff (Phase 4.1).
    // The countdown overlay (with prefetched source) takes over from here.
    if (seg.type.toLowerCase() == 'credits' &&
        _nextEpisodeEngine.hasNextEpisode) {
      AppLog.d('[SkipSegment] credits skipped → triggering next episode');
      setState(() {
        _showSkipButton = false;
        _activeSkipSegment = null;
      });
      _onPlaybackCompleted();
      return;
    }

    final target = seg.endMs != null
        ? Duration(milliseconds: seg.endMs!)
        : _player.state.duration;

    _onUserSeek(target + const Duration(milliseconds: 300));
    _player.seek(target + const Duration(milliseconds: 300));

    setState(() {
      _showSkipButton = false;
      _activeSkipSegment = null;
    });
  }

  void _handleDismissSkipSegment(MediaSkipSegment seg) {
    _dismissedSegmentKeys.add(seg.uniqueKey);
    setState(() {
      _showSkipButton = false;
      _activeSkipSegment = null;
    });
  }

  // ── Resource Governor integration ─────────────────────────────────────

  /// Governor escalated/de-escalated — retune the player immediately.
  void _onResourceLevelChanged() {
    final lvl = ResourceGovernor.instance.level.value;
    if (lvl == _resourceLevel) return;
    _resourceLevel = lvl;
    _applyResourceLevel(lvl);
  }

  /// Applies mpv knobs for the given resource level (live, no restart).
  Future<void> _applyResourceLevel(ResourceLevel lvl) async {
    try {
      final dynamic platform = _player.platform;
      if (platform == null) return;
      switch (lvl) {
        case ResourceLevel.normal:
          // Full quality: restore standard buffers, allow Anime4K if on.
          await platform.setProperty('demuxer-max-bytes', '157286400'); // 150MB
          await platform.setProperty('demuxer-max-back-bytes', '52428800'); // 50MB
          await platform.setProperty('demuxer-readahead-secs', '15');
          await platform.setProperty('vd-lavc-skiploopfilter', '0');
          await platform.setProperty('vd-lavc-skipidct', '0');
          await platform.setProperty('vd-lavc-skipframe', '0');
          await platform.setProperty('hwdec', 'auto-safe');
        case ResourceLevel.caution:
          // Trim caches & buffers ~50%.
          await platform.setProperty('demuxer-max-bytes', '78643200'); // 75MB
          await platform.setProperty('demuxer-max-back-bytes', '25165824'); // 24MB
          await platform.setProperty('demuxer-readahead-secs', '8');
          await platform.setProperty('vd-lavc-skiploopfilter', 'all');
        case ResourceLevel.critical:
          // Minimum viable playback: tiny buffers, skip all loop filters,
          // software-ish decode budget, no Anime4K shader VRAM.
          await platform.setProperty('demuxer-max-bytes', '31457280'); // 30MB
          await platform.setProperty('demuxer-max-back-bytes', '10485760'); // 10MB
          await platform.setProperty('demuxer-readahead-secs', '4');
          await platform.setProperty('vd-lavc-skiploopfilter', 'all');
          await platform.setProperty('vd-lavc-skipidct', 'all');
          await platform.setProperty('vd-lavc-skipframe', 'nonref');
          await platform.setProperty('glsl-shaders', ''); // kill Anime4K VRAM
          // Also drop image cache pressure immediately.
          PaintingBinding.instance.imageCache.clear();
      }
    } catch (e) {
      AppLog.d('[PlayerScreen] resource level apply warning: $e');
    }
  }

  // ── Silent Failover (Phase 3.2) ────────────────────────────────────────

  /// Arms the stall watchdog + last-good recorder once playback starts.
  /// Called from _initStream success and after every successful source switch.
  void _armPlaybackGuards() {
    _lastProgressPosition = Duration.zero;
    _maybeFetchRenditions(); // P9: HLS master → attach ladder in background
    _lastProgressAt = DateTime.now();

    _stallWatchdog?.cancel();
    _stallWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _failoverInProgress) return;
      // v1.1.9: chain still ranking → wait (max ~3s), don't fire blind.
      if (_failoverReady != null && _failoverChain.isEmpty) {
        unawaited(_failoverReady!.timeout(const Duration(seconds: 3), onTimeout: () {}));
        return;
      }
      final stalled = DateTime.now().difference(_lastProgressAt);
      // Only failover when we believe we SHOULD be playing but position
      // hasn't advanced for 10s+ (not paused, media loaded) AND mpv is not
      // actively buffering. Slow internet just buffers longer — a spinner
      // with data still flowing must never trigger a source switch; only a
      // truly dead stream (no position progress AND no buffering activity)
      // justifies losing the buffered progress to switch sources.
      final shouldPlay = _isPlaying && _duration > Duration.zero;
      final seekGrace = DateTime.now().difference(_lastSeekAt).inSeconds < 8;
      if (shouldPlay && !seekGrace && !_isBuffering && stalled.inSeconds >= 10) {
        AppLog.d('[Failover] stall detected: ${stalled.inSeconds}s no progress, not buffering');
        _attemptSilentFailover(reason: 'stall');
      }
    });

    _lastGoodTimer?.cancel();
    if (!_lastGoodRecorded) {
      _lastGoodTimer = Timer(const Duration(seconds: 30), () {
        if (!mounted) return;
        // 30s of healthy playback on this source → record last-good.
        if (_isPlaying && _player.state.position > const Duration(seconds: 25)) {
          _recordLastGoodSource();
          _lastGoodRecorded = true;
        }
      });
    }
  }

  void _recordLastGoodSource() {
    final detail = widget.detail;
    if (detail == null) return;
    final titleKey = 'dizzy:${detail.id}';
    final ep = _currentEpisode;
    final episodeKey = (ep != null)
        ? '$titleKey:S${ep.season}E${ep.episode}'
        : null;
    unawaited(LastGoodSourceStore.record(
      titleKey: titleKey,
      episodeKey: episodeKey,
      source: _currentSource,
    ));
  }

  /// Silently switches to the next best-ranked backup source.
  /// Saves position first, then reopens at the same position.
  void _attemptSilentFailover({String reason = 'error'}) {
    if (!mounted || _failoverInProgress) return;
    if (_failoverSwitches >= _maxFailoverSwitches) {
      AppLog.d('[Failover] switch cap reached — showing picker');
      _failoverChain = [];
      _showSourcesPanel = true; // let the user decide now
      setState(() {});
      return;
    }

    // Mark current source failed (this session).
    _failedFingerprints.add(SourceRanker.fingerprint(_currentSource));

    // Rank remaining candidates: exclude failed + current.
    final currentFp = SourceRanker.fingerprint(_currentSource);
    final candidates = _failoverChain
        .where((s) => !_failedFingerprints.contains(SourceRanker.fingerprint(s)))
        .where((s) => SourceRanker.fingerprint(s) != currentFp)
        .toList();
    if (candidates.isEmpty) {
      AppLog.d('[Failover] no backup sources — showing picker');
      setState(() => _showSourcesPanel = true);
      return;
    }

    _failoverInProgress = true;
    final savedPos = _player.state.position;
    final next = candidates.first;
    _failoverSwitches++;

    AppLog.d('[Failover] $reason → switching to ${next.name ?? next.addonName} '
        '(switch $_failoverSwitches/$_maxFailoverSwitches)');

    unawaited(() async {
      try {
        await _player.stop();
        setState(() => _isLoading = true);
        _currentSource = next;
        _bandwidthMeter.reset(); // P8: fresh source → fresh speed history
        _autoEffective = null;
        // Reopen via the standard init path, resuming AT the saved position
        // via Media(start:) — atomic open (no seek-after-open race).
        _resumeAtOverride = savedPos > Duration.zero ? savedPos : null;
        await _initStream();
        _resumeAtOverride = null;
        if (savedPos > Duration.zero && _player.state.position < savedPos) {
          // Fallback: only if the open didn't land at the position.
          await _player.seek(savedPos);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Switched to ${next.name ?? next.addonName} (backup)'),
            duration: const Duration(seconds: 2),
          ));
        }
      } catch (e) {
        AppLog.d('[Failover] switch failed: $e');
        if (mounted) setState(() => _showSourcesPanel = true);
      } finally {
        _resumeAtOverride = null;
        _failoverInProgress = false;
        if (mounted) _armPlaybackGuards();
      }
    }());
  }

  // ── P7: Manual quality (+ P8 auto) ─────────────────────────────────
  //
  // HLS → live `hls-bitrate-max` cap (no reopen). Progressive → reopen the
  // ranked file whose badge matches (same resume pattern as failover;
  // mpv lands the resume on a keyframe). Fail-soft everywhere.
  // [auto]=true → toast gains the "(auto)" suffix, choice is NOT persisted
  // (Auto mode stays Auto; only the effective rendition moves).
  void _applyQualityChoice(QualityChoice choice, {bool auto = false}) {
    setState(() {
      if (!auto) _qualityChoice = choice;
      _activeMenu = null;
    });
    final toast = QualityService.toastFor(choice) + (auto ? ' (auto)' : '');
    if (auto) {
      _autoEffective = choice;
    } else {
      unawaited(_qualityService.save(choice));
      _autoEffective = null;
      _bandwidthMeter.reset();
    }

    final url = _currentSource.url ?? '';
    if (QualityService.isHlsUrl(url)) {
      // P9: exact ladder rung known → cap at ITS bitrate (seamless, no reopen).
      final rung = _currentSource.renditions
          .where((r) => QualityChoice.fromBadge(r.label) == choice)
          .firstOrNull;
      final cap = rung != null && rung.bitrate > 0
          ? rung.bitrate.toString()
          : (choice.maxBitrate?.toString() ?? '0');
      try {
        final np = _player.platform as dynamic;
        np.setProperty('hls-bitrate-max', cap);
      } catch (_) {}
      _showAudioHudToast(toast);
      return;
    }
    if (choice == QualityChoice.auto) {
      _showAudioHudToast(toast);
      return;
    }
    // P8: straining device + AV1 file → prefer the H264 twin (same badge).
    final strained =
        ResourceGovernor.instance.level.value != ResourceLevel.normal;
    final ranked = [_currentSource, ..._failoverChain]
        .where((s) =>
            !_failedFingerprints.contains(SourceRanker.fingerprint(s)))
        .toList();
    final match = QualityService.matchProgressive(ranked, choice,
        avoidAv1: strained);
    if (match == null) {
      _showAudioHudToast('That quality is not available for this video.');
      return;
    }
    if (SourceRanker.fingerprint(match) ==
        SourceRanker.fingerprint(_currentSource)) {
      _showAudioHudToast(toast);
      return;
    }
    final savedPos = _player.state.position;
    unawaited(() async {
      try {
        await _player.stop();
        if (!mounted) return;
        setState(() => _isLoading = true);
        _currentSource = match;
        _bandwidthMeter.reset();
        _resumeAtOverride = savedPos > Duration.zero ? savedPos : null;
        await _initStream();
        _resumeAtOverride = null;
        if (mounted) _showAudioHudToast(toast);
      } catch (e) {
        AppLog.d('[Quality] switch failed: $e');
        if (mounted) {
          _showAudioHudToast('Could not switch quality. Keep watching.');
        }
      } finally {
        _resumeAtOverride = null;
        if (mounted) _armPlaybackGuards();
      }
    }());
  }

  // ── P9: rendition ladder lazy-fill ────────────────────────────────
  //
  // Any extractor emitting an HLS master automatically grows renditions:
  // fetch → parse → attach. Fail-soft (timeout/offline/bad playlist =
  // no renditions, playback untouched). One flight per source.
  void _maybeFetchRenditions() {
    final url = _currentSource.url ?? '';
    if (!QualityService.isHlsUrl(url)) return;
    if (_currentSource.renditions.isNotEmpty || _renditionsFetching) return;
    _renditionsFetching = true;
    final fp = SourceRanker.fingerprint(_currentSource);
    unawaited(() async {
      try {
        final res = await http
            .get(Uri.parse(url),
                headers: _currentSource.headers ?? const {})
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200 || !mounted) return;
        final parsed = HlsRenditionParser.parseMaster(res.body, url);
        if (parsed.isEmpty) return;
        if (SourceRanker.fingerprint(_currentSource) != fp) return;
        setState(
            () => _currentSource = _currentSource.copyWith(renditions: parsed));
        AppLog.d(
            '[Renditions] attached ${parsed.length} to ${_currentSource.addonName}');
      } catch (_) {
        // P15: silent-but-logged (background network) — playback untouched.
        unawaited(AppErrorLog.log(
            code: 'renditions_fetch', screen: 'player'));
      } finally {
        _renditionsFetching = false;
      }
    }());
  }

  // ── P8: 2s auto-quality probe ───────────────────────────────────────
  //
  // Feeds the meter from demuxer cache-fill (no pings). Applies the stable
  // target ONLY in Auto mode, steady playback, non-torrent sources.
  // Manual choice always wins — the probe goes quiet.
  void _autoQualityTick() {
    if (!mounted) return;
    if (_qualityChoice != QualityChoice.auto) return;
    if (_isLoading || !_isPlaying) return;
    final url = _currentSource.url ?? '';
    if (url.startsWith('magnet:')) return;
    if ((_currentSource.infoHash ?? '').isNotEmpty) return;
    final buf = _buffered;
    if (buf == null) return;
    final aheadSec =
        (buf.inMilliseconds - _player.state.position.inMilliseconds) / 1000.0;
    if (aheadSec < 0) return;
    final assumed = QualityChoice.fromBadge(_currentSource.quality)
            ?.maxBitrate ??
        BandwidthMeter.fallbackBitrateBps;
    _bandwidthMeter.addSample(
      at: DateTime.now(),
      bufferedAheadSec: aheadSec,
      assumedBitrateBps: assumed,
    );
    final target = _bandwidthMeter.stableTarget(
        dataSaver: PlayerSettings.dataSaver.value);
    if (target == null || target == _autoEffective) return;
    // Already watching at the target rendition → remember, don't toast.
    if (target == QualityChoice.fromBadge(_currentSource.quality) &&
        !QualityService.isHlsUrl(url)) {
      _autoEffective = target;
      return;
    }
    _applyQualityChoice(target, auto: true);
  }

  // ── Next-Episode Autoplay (Phase 2) ────────────────────────────────────

  /// Kicks off a background scrape+probe of the NEXT episode while the
  /// current one plays, so completion can start it in < 1s.
  void _startNextEpisodePrefetch() {
    if (!PlayerSettings.nextEpisodeAutoPlay.value) return;
    final detail = widget.detail;
    if (detail == null || detail.videos.isEmpty) return;
    final s = _currentEpisode?.season;
    final e = _currentEpisode?.episode;
    if (s == null || e == null) return; // movies have no episode context

    _nextEpisodeEngine.startPrefetch(
      type: detail.type,
      id: detail.id,
      title: detail.name,
      allEpisodes: detail.videos,
      currentSeason: s,
      currentEpisode: e,
      year: int.tryParse(detail.year ?? ''),
    );
  }

  /// Playback finished: show the 5s skippable next-episode countdown when
  /// a prefetched source is ready (Netflix-style binge handoff).
  void _onPlaybackCompleted() {
    if (!PlayerSettings.nextEpisodeAutoPlay.value) return;
    if (_nextEpisodeEngine.prefetchedSource == null) return;
    if (_currentEpisode == null) return; // movies don't chain

    // Avoid double-showing if already visible.
    if (_showNextEpisodeCountdown) return;

    setState(() => _showNextEpisodeCountdown = true);
    _announcePrefetchHint(); // P10: guests pre-resolve during the countdown
  }

  /// Starts playing the prefetched next episode (countdown finished or
  /// user tapped "Play now").
  void _playNextEpisode() {
    final src = _nextEpisodeEngine.prefetchedSource;
    final nextEp = _nextEpisodeEngine.prefetchedEpisode;
    if (src == null || nextEp == null) return;

    setState(() => _showNextEpisodeCountdown = false);

    _switchToEpisodeVideo(nextEp, src, prefetched: true);
  }

  /// Cancels the countdown and stays on the (ended) current episode.
  void _cancelNextEpisode() {
    setState(() => _showNextEpisodeCountdown = false);
  }

  /// Switches the player to [nextEp] using verified [source] without
  /// leaving the player route (reuses the in-player episode switch path).
  /// [prefetched]=true (countdown path) → guests get the `ready:true` mark.
  void _switchToEpisodeVideo(Video nextEp, StreamSource source,
      {bool prefetched = false}) {
    if (!mounted) return;

    setState(() {
      _currentSource = source;
      _currentEpisode = nextEp;
      final showName = widget.detail?.name ?? widget.title;
      final epNum = nextEp.episode ?? 1;
      final sNum = nextEp.season ?? 1;
      _currentTitle = '$showName - S$sNum:E$epNum ${nextEp.title}';
      _isLoading = true;
      _statusMessage = 'Buffering S$sNum:E$epNum...';
      _showEpisodesPanel = false;
      _showSourcesPanel = false;
      _activeMenu = null;
    });

    // Cleanup previous torrent engine if was P2P
    TorrentStreamService().cleanup();

    _initStream();

    // v1.2.0-P2: host episode change (incl. auto next-ep) re-announces.
    _announceHostMedia(prefetchReady: prefetched);

    // Binge chain continues: re-arm the gated prefetch for THIS
    // episode's successor (fires at 25%/3min into the new episode).
    _prefetchStarted = false;
  }

  void _savePlaybackProgress() {
    if (widget.detail == null) return;

    final pos = _player.state.position.inSeconds;
    final dur = _player.state.duration.inSeconds;
    if (dur <= 0) return;

    ContinueWatchingService.saveProgress(
      detail: widget.detail!,
      episode: _currentEpisode,
      source: _currentSource,
      positionSeconds: pos,
      totalDurationSeconds: dur,
    );
  }

  void _updateDiscordRpc({bool? isPaused}) {
    final paused = isPaused ?? !_isPlaying;
    final detail = widget.detail;
    final episode = _currentEpisode;
    final title = detail?.name ?? _currentTitle;
    final poster = widget.backdropUrl ?? detail?.poster ?? detail?.background;

    final type = (detail?.type ?? '').toLowerCase();
    final isAnime = type == 'anime' || (detail == null && _currentTitle.toLowerCase().contains('episode') && episode != null);
    final isSeries = type == 'series' || type == 'tv' || (!isAnime && episode != null);

    if (isAnime) {
      DiscordRpcService.instance.setWatchingAnime(
        title: title,
        season: episode?.season,
        episode: episode?.episode,
        episodeTitle: episode?.title,
        posterUrl: poster,
        position: _position,
        duration: _duration,
        isPaused: paused,
      );
    } else if (isSeries) {
      DiscordRpcService.instance.setWatchingSeries(
        title: title,
        season: episode?.season,
        episode: episode?.episode,
        episodeTitle: episode?.title,
        posterUrl: poster,
        position: _position,
        duration: _duration,
        isPaused: paused,
      );
    } else {
      DiscordRpcService.instance.setWatchingMovie(
        title: title,
        year: detail?.year,
        posterUrl: poster,
        position: _position,
        duration: _duration,
        isPaused: paused,
      );
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _progressSaveTimer?.cancel();
    _volumeHudTimer?.cancel();
    _audioHudTimer?.cancel();
    _savePlaybackProgress();
    // v1.1.9 (Task 16): flush dirty progress now — nothing lost on exit.
    unawaited(ContinueWatchingService.flushProgress());
    WakelockPlus.disable();
    _hideTimer?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    PlayerSettings.changeNotifier.removeListener(_onPlayerSettingsChanged);
    _stallWatchdog?.cancel();
    _lastGoodTimer?.cancel();
    _autoQualityTimer?.cancel();
    // v1.2.0-T2.8: stop party heartbeat / guest listener.
    unawaited(_partySession?.stop());
    _partySession = null;
    ResourceGovernor.instance.level.removeListener(_onResourceLevelChanged);
    ResourceGovernor.instance.playbackActive = false;
    _positionNotifier.dispose();
    _bufferNotifier.dispose();
    _nextEpisodeEngine.dispose(); // cancel next-episode prefetch cycle
    _player.dispose();
    _logoAnimController.dispose();
    TorrentStreamService().cleanup();
    WindowService.instance.exitFullscreen();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _onPlayerSettingsChanged() {
    PlayerSettings.applyToPlayer(_player);
  }

  DateTime? _lastScreenTapTime;

  void _handleScreenTap() {
    if (_isLocked) return; // lock mode: single taps ignored
    final now = DateTime.now();
    if (_lastScreenTapTime != null &&
        now.difference(_lastScreenTapTime!) < const Duration(milliseconds: 280)) {
      _lastScreenTapTime = null;
      WindowService.instance.toggleFullscreen();
    } else {
      _lastScreenTapTime = now;
      _toggleControls();
    }
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        // Locking hides controls immediately for clean fullscreen.
        _showControls = false;
        _hideTimer?.cancel();
      } else {
        _startHideControlsTimer();
      }
    });
  }

  /// Sets playback rate and keeps `_playbackRate` in sync (used by the
  /// speed menu, keyboard, and the gesture layer's long-press 2x hold).
  void _setPlaybackRate(double rate) {
    // v1.2.0-T2.8: guest speed locked — host speed wins for everyone.
    if (_partyGuestLocked) {
      _partyToast('Host controls play. You control sound + chat.');
      return;
    }
    setState(() => _playbackRate = rate);
    _player.setRate(rate);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        WindowService.instance.exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // Never intercept key events when typing or searching in text inputs or overlay
            if (_showTextSyncOverlay) {
              return KeyEventResult.ignored;
            }
            final primaryFocus = FocusManager.instance.primaryFocus;
            if (primaryFocus != null && primaryFocus.context != null) {
              final focusedWidget = primaryFocus.context!.widget;
              if (focusedWidget is EditableText) {
                return KeyEventResult.ignored;
              }
            }

            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                  event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
                _applyVolume((_volume + 0.05).clamp(0.0, PlayerVolumeControl.maxVolume), showHud: true);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                  event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
                _applyVolume((_volume - 0.05).clamp(0.0, PlayerVolumeControl.maxVolume), showHud: true);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
                _toggleMute(showHud: true);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.keyK) {
                _togglePlayPause();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.keyJ) {
                _seekRelative(const Duration(seconds: -10));
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                  event.logicalKey == LogicalKeyboardKey.keyL) {
                _seekRelative(const Duration(seconds: 10));
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
                WindowService.instance.toggleFullscreen();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyL) {
                _toggleLock();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                final delta = pointerSignal.scrollDelta.dy < 0 ? 0.05 : -0.05;
                final next = (_volume + delta).clamp(0.0, PlayerVolumeControl.maxVolume);
                _applyVolume((next * 100).round() / 100.0, showHud: true);
              }
            },
            child: MouseRegion(
              cursor: (_showControls || _isLoading || _activeMenu != null)
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.none,
              onHover: (_) => _handlePointerActivity(),
              child: _isLocked
                  ? Stack(
                      children: [
                        // Locked: swallow every gesture/tap on video area.
                        AbsorbPointer(
                          absorbing: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: _buildPlayerBody(),
                          ),
                        ),
                        // Persistent unlock button (only responsive element).
                        Positioned(
                          top: MediaQuery.paddingOf(context).top + 16,
                          right: 20,
                          child: PlayerLockButton(
                            isLocked: _isLocked,
                            onToggle: _toggleLock,
                          ),
                        ),
                      ],
                    )
                  : PlayerGestureLayer(
                      // v1.1.9: lock mode disables ALL gestures (seek, volume,
                      // brightness, double-tap, 2x hold) — lock button only.
                      enabled: !_isLocked,
                      host: PlayerGestureHost(
                        position: () => _player.state.position,
                        duration: () => _player.state.duration,
                        seekTo: (t) {
                          _onUserSeek(t);
                          _player.seek(t);
                        },
                        seekBy: (d) => _seekRelative(d),
                        volume: () => _isMuted ? 0.0 : _volume,
                        setVolume: (v) => _applyVolume(v, showHud: true),
                        speed: () => _playbackRate,
                        setSpeed: _setPlaybackRate,
                        toggleControls: _handleScreenTap,
                        toggleFullscreen: () =>
                            WindowService.instance.toggleFullscreen(),
                      ),
                      child: _buildPlayerBody(),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundStack() {
    return Stack(
      children: [
        // Loading Backdrop
        if (_isLoading && widget.backdropUrl != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: Image.network(widget.backdropUrl!, fit: BoxFit.cover),
            ),
          ),

        // Video Player
        Center(
          child: _isLoading
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.logoUrl != null)
                      AnimatedBuilder(
                        animation: _logoAnimController,
                        builder: (context, child) {
                          final val = _logoAnimController.value;
                          return Opacity(
                            opacity: 0.3 + (val * 0.7),
                            child: Transform.scale(
                              scale: 0.95 + (val * 0.1),
                              child: child,
                            ),
                          );
                        },
                        child: Image.network(
                          widget.logoUrl!,
                          height: 100,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      const CircularProgressIndicator(color: PlayerTheme.accent),
                    const SizedBox(height: 32),
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                )
              : SizedBox.expand(
                  child: ValueListenableBuilder<int>(
                    valueListenable: PlayerSettings.changeNotifier,
                    builder: (context, _, __) {
                      return mk.Video(
                        controller: _videoController,
                        fit: _videoFit,
                        controls: mk.NoVideoControls,
                        subtitleViewConfiguration: PlayerSettings.getSubtitleViewConfiguration(),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _handleDownloadMedia() async {
    final mediaId = widget.detail?.id ?? _currentTitle;
    final season = _currentEpisode?.season;
    final episode = _currentEpisode?.episode;

    final existing = DownloadService.instance.tasksNotifier.value.where((t) {
      if (t.mediaId == mediaId && t.season == season && t.episode == episode) {
        return true;
      }
      return false;
    }).firstOrNull;

    if (existing != null) {
      if (existing.status == DownloadStatus.downloading) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download already in progress in background.')),
        );
        return;
      } else if (existing.status == DownloadStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This media is already downloaded.')),
        );
        return;
      }
    }

    try {
      String? customDir;
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        customDir = await DownloadPathHelper.pickDownloadsDirectory();
        if (customDir == null) {
          // User canceled folder selection
          return;
        }
      }

      await DownloadService.instance.startDownload(
        title: widget.detail?.name ?? _currentTitle,
        mediaId: mediaId,
        type: widget.detail?.type ?? (widget.detail?.videos.isNotEmpty == true ? 'series' : 'movie'),
        season: season,
        episode: episode,
        episodeTitle: _currentEpisode?.title,
        posterUrl: widget.detail?.poster,
        backdropUrl: widget.detail?.background,
        year: widget.detail?.year,
        source: _currentSource,
        customDownloadDir: customDir,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download started in background. Track progress in Downloads tab.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed to start: $e')),
        );
      }
    }
  }

  Widget _buildControlsOverlay() {
    final buffered = _buffered;

    final episodeTitle = _currentEpisode?.title;
    final episodeSubtitle = _currentEpisode != null
        ? 'S${_currentEpisode!.season ?? 1}:E${_currentEpisode!.episode ?? 1}${episodeTitle != null && episodeTitle.isNotEmpty ? " • $episodeTitle" : ""}'
        : widget.detail?.year;

    final isOfflineFile = _currentSource.name == 'Downloaded';

    return Stack(
      children: [
        // v1.2.0-T2.8: party banner — host LIVE pill / guest locked note.
        if (PartySession.instance.inParty) _buildPartyBanner(),

        // Outside Tap Barrier to dismiss active floating menu
        if (_activeMenu != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _activeMenu = null),
              child: Container(color: Colors.transparent),
            ),
          ),

        // Top Header Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: (!_showControls && !_isLoading) || _showSubSyncBar || _showTextSyncOverlay,
            child: AnimatedOpacity(
              opacity: (_showControls || _isLoading) && !_showSubSyncBar && !_showTextSyncOverlay
                  ? 1.0
                  : 0.0,
              duration: const Duration(milliseconds: 200),
              child: MouseRegion(
                onEnter: (_) {
                  _isHoveringUI = true;
                  _hideTimer?.cancel();
                },
                onExit: (_) {
                  _isHoveringUI = false;
                  _startHideControlsTimer();
                },
                child: ValueListenableBuilder<List<DownloadTask>>(
                  valueListenable: DownloadService.instance.tasksNotifier,
                  builder: (context, tasks, _) {
                    final mediaId = widget.detail?.id ?? _currentTitle;
                    final season = _currentEpisode?.season;
                    final episode = _currentEpisode?.episode;
                    final isDownloading = tasks.any((t) =>
                        t.mediaId == mediaId &&
                        t.season == season &&
                        t.episode == episode &&
                        t.status == DownloadStatus.downloading);

                    return PlayerTopBar(
                      title: widget.detail?.name ?? _currentTitle,
                      subtitle: episodeSubtitle,
                      quality: _currentSource.name,
                      onDownload: (_isLoading || isOfflineFile) ? null : _handleDownloadMedia,
                      isDownloading: isDownloading,
                      onToggleEpisodes: (!_isLoading && widget.detail?.videos.isNotEmpty == true)
                          ? _toggleEpisodesPanel
                          : null,
                      isEpisodesActive: _showEpisodesPanel || _showSourcesPanel,
                      onLock: _toggleLock,
                      isLocked: _isLocked,
                      onPip: PipService.isSupported
                          ? () => PipService.enterPip()
                          : null,
                      onBack: () {
                        WindowService.instance.exitFullscreen();
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),

          // Bottom Transport Bar
          if (!_isLoading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: (!_showControls && _activeMenu == null) || _showTextSyncOverlay,
                child: AnimatedOpacity(
                  opacity: (_showControls || _activeMenu != null) && !_showTextSyncOverlay ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: MouseRegion(
                    onEnter: (_) {
                      _isHoveringUI = true;
                      _hideTimer?.cancel();
                    },
                    onExit: (_) {
                      _isHoveringUI = false;
                      _startHideControlsTimer();
                    },
                    child: ValueListenableBuilder<bool>(
                      valueListenable: WindowService.instance.isFullscreenNotifier,
                      builder: (context, isFs, _) {
                        return PlayerTransport(
                          isPlaying: _isPlaying,
                          position: _position,
                          duration: _duration,
                          buffered: buffered,
                          positionListenable: _positionNotifier,
                          bufferedListenable: _bufferNotifier,
                          skipSegments: _skipSegments,
                          volume: _volume,
                          isMuted: _isMuted || _volume == 0,
                          playbackRate: _playbackRate,
                          isSubtitlesActive: _isSubtitleEnabled && _currentSubtitleVariant != null,
                          isSubSyncActive: _selectedEmbeddedSubtitleIndex == null && (_showSubSyncBar || _subtitleDelayMs != 0),
                          isAudioActive: _selectedAudioTrackIndex > 0,
                          isQualityManual:
                              _qualityChoice != QualityChoice.auto,
                          isEpisodesActive: _showEpisodesPanel || _showSourcesPanel,
                          isFullscreen: isFs,
                          onToggleEpisodes: (widget.detail?.videos.isNotEmpty == true)
                              ? _toggleEpisodesPanel
                              : null,
                          onPlayPause: () {
                            _togglePlayPause();
                          },
                          onSeek: (pos) {
                            _onUserSeek(pos);
                            _player.seek(pos);
                          },
                          onSeekBack10: () {
                            _seekRelative(const Duration(seconds: -10));
                          },
                          onSeekForward10: () {
                            _seekRelative(const Duration(seconds: 10));
                          },
                          onVolumeChanged: (vol) => _applyVolume(vol),
                          onToggleMute: () => _toggleMute(),
                          onToggleAspectMenu: () => _toggleMenu('aspect'),
                          onToggleSpeedMenu: () => _toggleMenu('speed'),
                          onToggleAudioMenu: () => _toggleMenu('audio'),
                          onToggleQualityMenu: () => _toggleMenu('quality'),
                          onToggleSubtitleMenu: () => _toggleMenu('subtitle'),
                          onToggleSubSync: () {
                            if (_selectedEmbeddedSubtitleIndex != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Subtitle sync is not supported for embedded subtitles. Please select an external subtitle.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            if (_currentSubtitlePath == null || _currentSubtitleVariant == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please load an external subtitle to use subtitle sync.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _showSubSyncBar = !_showSubSyncBar;
                              _activeMenu = null;
                            });
                          },
                          onToggleFullscreen: () => WindowService.instance.toggleFullscreen(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

          // Floating Subtitle Menu Popover
          if (_activeMenu == 'subtitle' && !_isLoading)
            Positioned(
              bottom: MediaQuery.sizeOf(context).height < 500
                  ? 44
                  : (MediaQuery.sizeOf(context).width < 560
                      ? 60
                      : (MediaQuery.sizeOf(context).width < 680 ? 76 : 96)),
              right: MediaQuery.sizeOf(context).width < 560
                  ? 8
                  : (MediaQuery.sizeOf(context).width < 680 ? 12 : 28),
              left: MediaQuery.sizeOf(context).width < 560 ? 8 : null,
              child: Align(
                alignment: MediaQuery.sizeOf(context).width < 560
                    ? Alignment.bottomCenter
                    : Alignment.bottomRight,
                child: PlayerSubtitleMenu(
                  groups: _subtitleGroups,
                  embeddedSubtitles: _embeddedSubtitles,
                  selectedEmbeddedIndex: _selectedEmbeddedSubtitleIndex,
                  selectedVariant: _currentSubtitleVariant,
                  isSubtitleEnabled: _isSubtitleEnabled,
                  movieTitle: widget.detail?.name ?? widget.title,
                  imdbId: widget.detail?.id,
                  season: _currentEpisode?.season,
                  episode: _currentEpisode?.episode,
                  year: widget.detail?.year != null ? int.tryParse(widget.detail!.year!) : null,
                  delaySec: _subtitleDelayMs / 1000.0,
                  onSelectVariant: (v) {
                    if (v != null) _loadSubtitle(v);
                  },
                  onSelectEmbedded: (emb) => _selectEmbeddedSubtitle(emb),
                  onToggleOff: _disableSubtitles,
                  onOpenSyncBar: () {
                    if (_selectedEmbeddedSubtitleIndex != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Subtitle sync is not supported for embedded subtitles.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _activeMenu = null;
                      _showSubSyncBar = true;
                    });
                  },
                  onOpenStyleBar: () {
                    setState(() => _activeMenu = 'style');
                  },
                  onOpenTextSync: () {
                    if (_selectedEmbeddedSubtitleIndex != null || _currentSubtitlePath == null || _currentCues.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Speech sync requires an external subtitle file.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _activeMenu = null;
                      _showTextSyncOverlay = true;
                    });
                  },
                  onClose: () => setState(() => _activeMenu = null),
                ),
              ),
            ),

          // Floating Audio Menu Popover
          if (_activeMenu == 'audio' && !_isLoading)
            Positioned(
              bottom: MediaQuery.sizeOf(context).height < 500
                  ? 46
                  : (MediaQuery.sizeOf(context).width < 680 ? 76 : 96),
              right: MediaQuery.sizeOf(context).width < 680 ? 12 : 28,
              child: PlayerAudioMenu(
                audioTracks: _audioTracks,
                selectedIndex: _selectedAudioTrackIndex,
                delaySec: _audioDelaySec,
                onTrackSelected: (idx) {
                  setState(() => _selectedAudioTrackIndex = idx);
                  try {
                    final matching = _player.state.tracks.audio.firstWhere(
                      (t) => t.id == idx.toString(),
                      orElse: () => AudioTrack(idx.toString(), null, null),
                    );
                    _player.setAudioTrack(matching);
                    final np = _player.platform as dynamic;
                    np.setProperty('aid', idx.toString());
                  } catch (_) {}
                  final match = _audioTracks.where((t) => t.index == idx).firstOrNull;
                  _showAudioHudToast(match?.title ?? 'Track $idx');
                },
                onDelayChanged: (sec) {
                  setState(() => _audioDelaySec = sec);
                  try {
                    final np = _player.platform as dynamic;
                    np.setProperty('audio-delay', sec.toString());
                  } catch (_) {}
                  _showAudioHudToast('AUDIO SYNC: ${sec > 0 ? "+" : ""}${sec.toStringAsFixed(2)}s');
                },
                onClose: () => setState(() => _activeMenu = null),
              ),
            ),

          // Floating Quality Menu Popover (P7 — manual rendition picker)
          if (_activeMenu == 'quality' && !_isLoading)
            Positioned(
              bottom: MediaQuery.sizeOf(context).height < 500
                  ? 46
                  : (MediaQuery.sizeOf(context).width < 680 ? 76 : 96),
              right: MediaQuery.sizeOf(context).width < 680 ? 12 : 28,
              child: PlayerQualityMenu(
                options: QualityService.optionsFor(
                  isHls: QualityService.isHlsUrl(_currentSource.url),
                  badges: {
                    if (_currentSource.quality != null)
                      _currentSource.quality!,
                    for (final s in _failoverChain)
                      if (s.quality != null) s.quality!,
                  },
                  renditionLabels: {
                    for (final r in _currentSource.renditions) r.label,
                  },
                ),
                current: _qualityChoice,
                onSelected: _applyQualityChoice,
                onClose: () => setState(() => _activeMenu = null),
              ),
            ),

          // Floating Speed Menu Popover
          if (_activeMenu == 'speed' && !_isLoading)
            Positioned(
              bottom: MediaQuery.sizeOf(context).height < 500
                  ? 46
                  : (MediaQuery.sizeOf(context).width < 680 ? 76 : 96),
              right: MediaQuery.sizeOf(context).width < 680 ? 12 : 28,
              child: PlayerSpeedMenu(
                currentRate: _playbackRate,
                onRateSelected: _setPlaybackRate,
                onClose: () => setState(() => _activeMenu = null),
              ),
            ),

          // Floating Aspect Ratio Popover
          if (_activeMenu == 'aspect' && !_isLoading)
            Positioned(
              bottom: MediaQuery.sizeOf(context).height < 500
                  ? 46
                  : (MediaQuery.sizeOf(context).width < 680 ? 76 : 96),
              right: MediaQuery.sizeOf(context).width < 680 ? 12 : 28,
              child: PlayerAspectMenu(
                currentFit: _videoFit,
                subtitleScale: _subtitleScale,
                onFitSelected: (fit) => setState(() => _videoFit = fit),
                onSubtitleScaleChanged: _setSubtitleScale,
                onClose: () => setState(() => _activeMenu = null),
              ),
            ),

          // Floating Subtitle Appearance & Customization Modal
          if (_activeMenu == 'style' && !_isLoading)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _activeMenu = null),
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
                    onTap: () {}, // Prevent tap through
                    child: PlayerSubStyleModal(
                      player: _player,
                      onClose: () => setState(() => _activeMenu = null),
                    ),
                  ),
                ),
              ),
            ),

          // Top Floating Live SubSyncBar
          if (_showSubSyncBar && !_isLoading && _selectedEmbeddedSubtitleIndex == null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 16,
              left: 0,
              right: 0,
              child: SubSyncBar(
                delaySec: _subtitleDelayMs / 1000.0,
                isTextSyncAvailable: _selectedEmbeddedSubtitleIndex == null && _currentSubtitlePath != null && _currentCues.isNotEmpty,
                onDelayChanged: (sec) => _applyLiveDelay(sec),
                onEnterTextSync: () {
                  setState(() {
                    _showSubSyncBar = false;
                    _showTextSyncOverlay = true;
                  });
                },
                onClose: () {
                  setState(() => _showSubSyncBar = false);
                  _startHideControlsTimer();
                },
              ),
            ),

          // In-Player Episodes Side Panel
          if (_showEpisodesPanel && widget.detail?.videos.isNotEmpty == true && !_isLoading)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showEpisodesPanel = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: GestureDetector(
                    onTap: () {},
                    child: PlayerEpisodesPanel(
                      videos: widget.detail!.videos,
                      currentEpisode: _currentEpisode,
                      onEpisodeSelected: _onEpisodeChosen,
                      onClose: () => setState(() => _showEpisodesPanel = false),
                    ),
                  ),
                ),
              ),
            ),

          // In-Player Sources Side Panel (Targeted Scraping & Error Recovery)
          if (_showSourcesPanel && _sourcesEpisode != null && !_isLoading)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showSourcesPanel = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: GestureDetector(
                    onTap: () {},
                    child: PlayerSourcesPanel(
                      episode: _sourcesEpisode!,
                      detail: widget.detail,
                      currentAddonName: _currentSource.addonName,
                      errorMessage: _sourcesErrorMessage,
                      cachedSources: _cachedSourcesByEpisode['${_sourcesEpisode!.season ?? 1}:${_sourcesEpisode!.episode ?? 1}'],
                      onSourcesLoaded: (sources) {
                        _cachedSourcesByEpisode['${_sourcesEpisode!.season ?? 1}:${_sourcesEpisode!.episode ?? 1}'] = sources;
                      },
                      onPlaySource: _playNewSource,
                      onBackToEpisodes: _onBackToEpisodes,
                      onClose: () => setState(() => _showSourcesPanel = false),
                    ),
                  ),
                ),
              ),
            ),

          // Right Drawer Text Sync
          if (_showTextSyncOverlay && !_isLoading && _currentCues.isNotEmpty && _selectedEmbeddedSubtitleIndex == null)
            Positioned.fill(
              child: TextSyncOverlay(
                player: _player,
                initialCues: _currentCues,
                baseOffsetSec: _subtitleDelayMs / 1000.0,
                onClose: () {
                  setState(() => _showTextSyncOverlay = false);
                  _startHideControlsTimer();
                },
                onSave: _saveTextSyncedCues,
              ),
            ),

          // Floating Skip Button (Skip Intro, Skip Recap, Skip Credits, Skip Preview)
          if (_showSkipButton && _activeSkipSegment != null && !_isLoading && !_showTextSyncOverlay && !_showEpisodesPanel && !_showSourcesPanel)
            Positioned(
              bottom: (_showControls || _activeMenu != null)
                  ? (MediaQuery.paddingOf(context).bottom +
                      (MediaQuery.sizeOf(context).width < 680 ? 108 : 128))
                  : (MediaQuery.paddingOf(context).bottom +
                      (MediaQuery.sizeOf(context).width < 680 ? 22 : 36)),
              right: MediaQuery.sizeOf(context).width < 680 ? 16 : 28,
              child: AnimatedOpacity(
                opacity: _showSkipButton ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: PlayerSkipButton(
                  segment: _activeSkipSegment!,
                  onSkip: () => _handleSkipSegment(_activeSkipSegment!),
                  onDismiss: () => _handleDismissSkipSegment(_activeSkipSegment!),
                ),
              ),
            ),

          // Center Heads-Up Volume Display (HUD)
          if (_showVolumeHud)
            Positioned.fill(
              child: IgnorePointer(
                child: _buildVolumeHud(),
              ),
            ),

          // Center Heads-Up Audio Display (HUD)
          if (_showAudioHud)
            Positioned.fill(
              child: IgnorePointer(
                child: _buildAudioHud(),
              ),
            ),

          // Next-Episode Countdown (Netflix-style binge handoff)
          if (_showNextEpisodeCountdown &&
              _nextEpisodeEngine.prefetchedEpisode != null)
            Positioned.fill(
              child: NextEpisodeCountdown(
                nextEpisode: _nextEpisodeEngine.prefetchedEpisode!,
                showName: widget.detail?.name ?? widget.title,
                backdropUrl: widget.backdropUrl,
                onPlayNow: _playNextEpisode,
                onCancel: _cancelNextEpisode,
              ),
            ),
        ],
      );
  }

  Widget _buildVolumeHud() {
    final effectiveVol = _isMuted ? 0.0 : _volume;
    final isBoosting = !_isMuted && _volume > 1.001;
    final pct = (effectiveVol * 100).round();
    final boostColor = _volume > 1.75
        ? const Color(0xFFFF3D00)
        : (_volume > 1.0 ? const Color(0xFFFF8A00) : Colors.white);

    IconData volIcon;
    if (_isMuted || _volume == 0) {
      volIcon = Icons.volume_off_rounded;
    } else if (_volume > 1.0) {
      volIcon = Icons.volume_up_rounded;
    } else if (_volume < 0.5) {
      volIcon = Icons.volume_down_rounded;
    } else {
      volIcon = Icons.volume_up_rounded;
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1117).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isBoosting
                ? boostColor.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.15),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isBoosting ? boostColor.withValues(alpha: 0.28) : Colors.black54,
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  volIcon,
                  color: isBoosting ? boostColor : Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  _isMuted ? 'Muted' : '$pct%',
                  style: TextStyle(
                    color: isBoosting ? boostColor : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (isBoosting) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: boostColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: boostColor.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, size: 13, color: boostColor),
                        const SizedBox(width: 2),
                        Text(
                          _volume > 1.75 ? 'MAX BOOST' : 'BOOST',
                          style: TextStyle(
                            color: boostColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 140,
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  children: [
                    Container(color: Colors.white.withValues(alpha: 0.15)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (effectiveVol / PlayerVolumeControl.maxVolume).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: isBoosting
                              ? LinearGradient(
                                  colors: [
                                    Colors.white,
                                    const Color(0xFFFF8A00),
                                    if (_volume > 1.75) const Color(0xFFFF3D00),
                                  ],
                                )
                              : null,
                          color: isBoosting ? null : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioHudToast(String text) {
    _audioHudTimer?.cancel();
    setState(() {
      _audioHudText = text;
      _showAudioHud = true;
    });
    _audioHudTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showAudioHud = false);
    });
  }

  Widget _buildAudioHud() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1117).withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF7C5CFF).withValues(alpha: 0.5),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C5CFF).withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.audiotrack_rounded,
              color: Color(0xFF00D2EF),
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              _audioHudText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerBody() {
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSettings.enabled,
      builder: (context, enabled, _) {
        if (enabled) {
          return LiquidGlassView(
            realTimeCapture: _showControls && !_isLoading,
            useSync: true,
            pixelRatio: 0.85,
            refreshRate: LiquidGlassRefreshRate.deviceRefreshRate,
            regionCapture: true,
            backgroundWidget: _buildBackgroundStack(),
            child: _buildControlsOverlay(),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: _buildBackgroundStack()),
            RepaintBoundary(child: _buildControlsOverlay()),
          ],
        );
      },
    );
  }
}
