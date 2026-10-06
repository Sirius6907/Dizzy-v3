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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/models/movie/video.dart';
import 'package:dizzy/models/movie/movie_detail.dart';
import 'package:dizzy/models/subtitle/subtitle_model.dart';
import 'package:dizzy/services/subtitles/subtitle_service.dart';
import 'package:dizzy/services/subtitles/subtitle_parser.dart';

import '../../models/stream/stream_model.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/stream/torrent_stream_service.dart';
import '../../services/media/global_media_coordinator.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/player/player_settings.dart';
import '../../services/player/playback_brain.dart';
import '../../services/player/quality_service.dart';
import '../../services/player/smart_quality_policy.dart';
import '../../services/player/auto_skip_policy.dart';
import '../../services/player/audio_track_preference.dart';
import '../../services/player/dub_mode_service.dart';
import '../../services/player/bandwidth_meter.dart';
import '../../services/player/hls_rendition_parser.dart';
import '../../services/errors/app_error_log.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../widgets/common/offline_aware_scaffold.dart';

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
import '../../services/stream/instant_play_gate.dart';
import '../../services/stream/last_good_source_store.dart';
import '../../services/watchparty/party_session.dart';
import '../../services/watchparty/party_playback_session.dart';
import '../../services/system/resource_governor.dart';
import '../../utils/perf/storage_guard.dart';
import '../../widgets/player/next_episode_countdown.dart';
import '../../services/errors/app_log.dart';
import '../../services/theme/app_theme_service.dart';
import '../../design/dizzy_tokens.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
part 'player_screen_part_party.dart';
part 'player_screen_part_stream.dart';
part 'player_screen_part_controls.dart';
part 'player_screen_part_playback.dart';
part 'player_screen_part_ui.dart';

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
  // Polish P4: first-run gesture hints (once per device).
  bool _showGestureHints = false;
  double _playbackRate = 1.0;
  BoxFit _videoFit = BoxFit.contain;
  List<PlayerAudioTrack> _audioTracks = [];

  // Party sync (v1.2.0-T2.8) — null when not in a Watch Together room.
  PartyPlaybackSession? _partySession;

  // Lock mode (v1.1.8) — swallows all player-area input when locked.
  bool _isLocked = false;
  int _selectedAudioTrackIndex = 0;
  /// F1: the language-tag audio auto-select fires once per source. Reset on
  /// every episode/source switch so each new media gets its own decision,
  /// and never re-fires after the user has picked a track by hand.
  bool _audioAutoSelectDone = false;
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
  /// F1: the single source of truth for "which source is dead" and "how
  /// many switches are left". Owns the failed-fingerprint set and the
  /// switch cap, so the ranker, the quality picker and the failover path
  /// can never disagree about what has already died.
  late final InstantPlayGate _playGate = InstantPlayGate(
    autoplayEnabled: () => PlayerSettings.autoplayFirstVerified.value,
    autoFailover: () => PlayerSettings.autoFailover.value,
  );
  /// Live view of the gate's dead-source set (this-session only).
  Set<String> get _failedFingerprints => _playGate.deadFingerprints;
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
  DateTime? _lastScreenTapTime;
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

    // Polish P4: gesture hints once per device (Easy English, dismissable).
    unawaited(SharedPreferences.getInstance().then((prefs) {
      if (mounted && !(prefs.getBool('player_gesture_hints_seen') ?? false)) {
        setState(() => _showGestureHints = true);
      }
    }));

    // P5: 5s quality probe — was 2s. A speed check every 2s keeps the
    // radio awake + burns CPU for the whole 40min session.
    _autoQualityTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _autoQualityTick());

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
            !PlayerSettings.dataSaver.value &&
            StorageGuard.prefetchAllowed) {
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
  static String cleanMediaTitle(String raw) {
    var name = raw;
    name = name.replaceAll(RegExp(r'\.(mkv|mp4|avi|webm|ts|mov|m4v|srt|vtt)$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[._]'), ' ');
    name = name.replaceAll(RegExp(r'\b(2160p|1080p|720p|480p|4k|uhd|ds4k|webrip|web-dl|bluray|brrip|h264|x264|h265|x265|hevc|10bit|ddp5\.1|dd5\.1|atmos|aac|ac3|dts|flac|remux|hdr|dv|proper|repack|hdtv)\b', caseSensitive: false), ' ');
    name = name.replaceAll(RegExp(r'-[a-zA-Z0-9]+$'), '');
    return name.trim().replaceAll(RegExp(r'\s+'), ' ');
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
    // P4: video closed — music may resume, mini-player hides.
    GlobalMediaCoordinator.instance.notifyVideoStopped();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        WindowService.instance.exitFullscreen();
      },
      child: OfflineAwareScaffold(
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

}