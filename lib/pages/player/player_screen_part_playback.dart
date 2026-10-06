part of 'player_screen.dart';

// setState is @protected: the analyzer wants it only inside State
// subclasses, but these methods are a mechanical move out of
// _PlayerScreenState (Dart has no partial classes). Same library, same
// instance, identical runtime behaviour — file-scoped ignore only.
// ignore_for_file: invalid_use_of_protected_member

extension _PlayerScreenStatePlaybackEngine on _PlayerScreenState {
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

    // F1: poison the chain first, then let the gate pick the replacement.
    _playGate.markDead(_currentSource);
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

    // F1: a new episode is fresh media — dead sources and the switch cap
    // from the previous one must not follow the user into the next one.
    if (newEpisode.id != _currentEpisode?.id ||
        newEpisode.episode != _currentEpisode?.episode ||
        newEpisode.season != _currentEpisode?.season) {
      _playGate.reset();
    }

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
        // F1: auto-skip intro/recap/credits, ON by default. Credits ride the
        // existing "Skip Intro (Smart)" switch (it already promises the
        // next-episode hand-off); previews NEVER auto-skip. The policy lives
        // in `AutoSkipPolicy` so the rule is unit-tested, not inline.
        final t = matched.type.toLowerCase();
        final autoOn = AutoSkipPolicy.shouldAutoSkip(
          t,
          autoSkipIntro: PlayerSettings.autoSkipIntro.value,
          autoSkipRecap: PlayerSettings.autoSkipRecap.value,
          autoSkipCredits: PlayerSettings.skipIntroHeuristics.value,
        );
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
          // P3/P9: restore PROFILE buffers — never hardcode 150MB here
          // (that re-blows the phone budget on every de-escalation).
          await platform.setProperty('demuxer-max-bytes',
              '${PlayerSettings.demuxerMaxBytesMB * 1024 * 1024}');
          await platform.setProperty('demuxer-max-back-bytes',
              '${PlayerSettings.demuxerMaxBytesMB * 1024 * 1024 ~/ 3}');
          await platform.setProperty(
              'demuxer-readahead-secs', '${PlayerSettings.readaheadSecs}');
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
    // P5: stall check every 5s — was 2s. Detection threshold is still a
    // 10s+ no-progress window, so nothing is missed; CPU wakes 60% less.
    _stallWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
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

    // F1: the gate decides whether we may switch and which source is next.
    // A dead chain (or the switch cap) hands the choice to the picker.
    final next = _playGate.advance(
      chain: _failoverChain,
      failed: _currentSource,
    );
    if (next == null) {
      _failoverChain = [];
      setState(() => _showSourcesPanel = true); // let the user decide now
      return;
    }

    _failoverInProgress = true;
    final savedPos = _player.state.position;

    AppLog.d('[Failover] $reason → switching to ${next.name ?? next.addonName} '
        '(switch ${_playGate.switches})');

    unawaited(() async {
      try {
        await _player.stop();
        setState(() => _isLoading = true);
        _currentSource = next;
        _bandwidthMeter.reset(); // fresh source → fresh speed history
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
          // F1: one Easy-English line, no source names / no tech words.
          // The real reason went to the admin log above.
          _showAudioHudToast(kTryingNextSourceMessage);
          // Cinema-hall parity: backup source live → guest ko turant sahi
          // position (500ms heartbeat ka wait nahi). host_state me real
          // position hoti hai; same-ref media_switch me 0 hoti — wo KABHI NAHI.
          if (PartySession.instance.isHost) {
            unawaited(_partySession?.sendAction('host_state'));
          }
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
    // F1: weak/straining device + AV1 file → prefer the H264 twin (same
    // badge). `SmartQualityPolicy` folds device tier, low-RAM, Low-End Mode
    // and the live resource level into one signal, so a budget phone dodges
    // AV1 even while the governor is still calm. AV1 remains a fallback.
    final capability = SmartQualityPolicy.liveCapability();
    final ranked = [_currentSource, ..._failoverChain]
        .where((s) =>
            !_failedFingerprints.contains(SourceRanker.fingerprint(s)))
        .toList();
    final match = SmartQualityPolicy.pickProgressive(
      ranked: ranked,
      choice: choice,
      capability: capability,
    );
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
    // F1: the meter reports the RAW speed verdict; SmartQualityPolicy owns
    // the Data Saver ceiling so the cap has exactly one home.
    final target = SmartQualityPolicy.autoLadderStep(
      bandwidthTarget: _bandwidthMeter.stableTarget(dataSaver: false),
      dataSaver: PlayerSettings.dataSaver.value,
    );
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

  void _onPlayerSettingsChanged() {
    PlayerSettings.applyToPlayer(_player);
  }

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

}
