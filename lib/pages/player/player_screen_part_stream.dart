part of 'player_screen.dart';

// setState is @protected: the analyzer wants it only inside State
// subclasses, but these methods are a mechanical move out of
// _PlayerScreenState (Dart has no partial classes). Same library, same
// instance, identical runtime behaviour — file-scoped ignore only.
// ignore_for_file: invalid_use_of_protected_member

extension _PlayerScreenStateStreamLifecycle on _PlayerScreenState {
  Future<void> _initStream() async {
    String? streamUrl;

    // F1: every open (first play, failover, quality switch, next episode)
    // goes through here — re-arm the language-tag audio pick per source.
    _audioAutoSelectDone = false;

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
      // P4: one sound at a time — video starting pauses music.
      unawaited(GlobalMediaCoordinator.instance
          .notifyVideoStarted(title: _currentSource.name ?? ''));

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
      // P5: progress flush every 10s — was 5s. Dirty-progress is also
      // flushed on pause/exit, so nothing is lost by halving the rate.
      _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
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

    // F1: the dub gate's second half — language tags pick the track. A
    // Hindi source usually carries several tracks and mpv's default pick
    // is whatever the container listed first, which is regularly English.
    // Only the FIRST discovery acts, so a later manual pick is never undone.
    if (_audioAutoSelectDone || audioTracks.isEmpty) return;
    _audioAutoSelectDone = true;
    final preferred = AudioTrackPreference.pick(
      tracks: [
        for (final t in audioTracks)
          AudioTrackOption(
            index: t.index,
            language: t.language,
            title: t.title,
          ),
      ],
      hindi: DubModeService.isHindi,
    );
    if (preferred == null || preferred == _selectedAudioTrackIndex) return;
    try {
      final matching = _player.state.tracks.audio.firstWhere(
        (t) => t.id == preferred.toString(),
        orElse: () => AudioTrack(preferred.toString(), null, null),
      );
      _player.setAudioTrack(matching);
      final np = _player.platform as dynamic;
      np.setProperty('aid', preferred.toString());
      if (mounted) setState(() => _selectedAudioTrackIndex = preferred);
      AppLog.d('[AudioGate] auto-selected track $preferred (hindi=${DubModeService.isHindi})');
    } catch (e) {
      AppLog.d('[AudioGate] auto-select skipped: $e');
    }
  }

}
