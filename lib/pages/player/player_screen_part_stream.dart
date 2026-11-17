part of 'player_screen.dart';

// setState is @protected: the analyzer wants it only inside State
// subclasses, but these methods are a mechanical move out of
// _PlayerScreenState (Dart has no partial classes). Same library, same
// instance, identical runtime behaviour — file-scoped ignore only.
// ignore_for_file: invalid_use_of_protected_member

extension _PlayerScreenStateStreamLifecycle on _PlayerScreenState {
  /// Opens [_currentSource] and reports whether a media actually started.
  ///
  /// Returns false when the source could not be played and the failure was
  /// handed to the failover chain (or to the sources picker). Callers that
  /// replaced a working source use that answer to put the old source back
  /// instead of leaving the user with a dead player.
  Future<bool> _initStream() async {
    String? streamUrl;
    // Set when the failure came from the torrent engine (starved swarm / no
    // metadata). Those failures must move to the next source instead of
    // parking the user on the "pick a source" sheet.
    var torrentRejected = false;

    // F1: every open (first play, failover, quality switch, next episode)
    // goes through here — re-arm the language-tag audio pick per source.
    _audioAutoSelectDone = false;
    _audioUserPicked = false;
    // Per-source measurement state must not leak into the next source.
    _startHlsCapBps = null;

    AppLog.d('[PlayerScreen] Initializing playback:');
    AppLog.d('[PlayerScreen]   Title: $_currentTitle');
    AppLog.d('[PlayerScreen]   Source Name: ${_currentSource.name}');
    AppLog.d('[PlayerScreen]   Addon Name: ${_currentSource.addonName}');
    AppLog.d('[PlayerScreen]   Source Title: ${_currentSource.title}');
    AppLog.d('[PlayerScreen]   Raw URL: ${_currentSource.url}');

    // v1.3.5: an embed source is played by its webview, not by mpv. Until a
    // media URL is captured, the webview IS the player surface — opening mpv
    // with a page URL would only paint a black frame.
    final sourceFp = SourceRanker.fingerprint(_currentSource);
    final embedCaptured =
        _embedCaptureFp == sourceFp && (_embedCaptureUrl ?? '').isNotEmpty;
    if (_currentSource.isEmbedSource && !embedCaptured) {
      if (!mounted) return false;
      setState(() {
        _embedActive = true;
        _isLoading = false;
        _statusMessage = 'Opening player…';
      });
      // The webview IS the player surface until a media URL is captured, so
      // this source is playing (the mpv hand-off happens later).
      return true;
    }

    try {
      final rawUrl = embedCaptured
          ? _embedCaptureUrl
          : _currentSource.url;

      // Handle offline downloaded file playback directly
      if (rawUrl != null &&
          (File(rawUrl).existsSync() || _currentSource.name == 'Downloaded')) {
        AppLog.d(
          '[PlayerScreen] Initializing offline local file playback: $rawUrl',
        );
        await PlayerSettings.applyPreOpenProperties(_player);
        await _player.open(Media(rawUrl), play: true);
        await PlayerSettings.applyPostOpenProperties(_player);
        _setSubtitleScale(_subtitleScale);
        _applyVolume(_isMuted ? 0.0 : _volume, persist: false);
        if (mounted) setState(() => _isLoading = false);
        return true;
      }

      // Bandwidth-aware start: runs before the first open (and before a
      // torrent is added to TorrServer) so a 4K source is never picked on a
      // link that measured too slow. Manual quality bypasses it.
      await _applyStartupQualityGate();

      final infoHash = _currentSource.infoHash;
      final isMagnetUrl = rawUrl != null && rawUrl.startsWith('magnet:');
      final isTorrent =
          (infoHash != null && infoHash.isNotEmpty) || isMagnetUrl;

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
        // A magnet without trackers is DHT-only: the engine then needs 20-40 s
        // to find the first peer and often finds nobody, which is exactly the
        // "no working peers" state the player used to get stuck in.
        magnet = magnetWithTrackers(magnet);

        final useDebrid = await DebridService().isDebridActiveForStreams();
        final seasonNum = _currentEpisode?.season;
        final episodeNum = _currentEpisode?.episode;
        final epTitle = _currentEpisode?.title;

        if (useDebrid) {
          final activeService = await DebridService().getSelectedService();
          if (!mounted) return false;
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
          if (!mounted) return false;
          setState(() => _statusMessage = 'Gathering metadata & peers...');

          // The file's own bitrate estimate (size × runtime) is the floor a
          // swarm must sustain; a slow swarm is rejected before mpv opens.
          final requiredBps =
              StartupBandwidthPolicy.estimatedBitrateBps(
                _currentSource,
                _runtimeReference,
              ) ??
              0;

          streamUrl = await TorrentStreamService().streamTorrent(
            magnet,
            season: seasonNum,
            episode: episodeNum,
            episodeTitle: epTitle,
            fileIdx: _currentSource.fileIdx,
            requiredBps: requiredBps,
          );
          if (streamUrl == null) torrentRejected = true;
        }
      } else if (rawUrl != null && rawUrl.isNotEmpty) {
        streamUrl = rawUrl;
      } else {
        throw Exception('No valid stream source found.');
      }

      if (streamUrl == null) throw Exception('Stream URL is null');

      var sanitizedUrlStr = streamUrl.contains('::')
          ? streamUrl.replaceAll('::', '%3A%3A')
          : streamUrl;

      // Automatically resolve complete CDN headers (Referer, Origin, User-Agent)
      final playerHeaders = PlayerSettings.resolveStreamHeaders(
        sanitizedUrlStr,
        _currentSource.headers,
      );

      // Also merge any proxyHeaders from behaviorHints if present
      final proxyReqHeaders =
          _currentSource.behaviorHints?['proxyHeaders']?['request'];
      if (proxyReqHeaders is Map) {
        playerHeaders.addAll(Map<String, String>.from(proxyReqHeaders));
      }

      // v1.3.5: the embed webview captured this URL — carry its Referer/UA so
      // the CDN accepts the handoff from mpv.
      if (embedCaptured && _embedCaptureHeaders != null) {
        playerHeaders.addAll(_embedCaptureHeaders!);
      }

      // ── HTML player pages ─────────────────────────────────────────────
      // Several extractors stopped handing out direct media URLs and now
      // answer with an HTML player page. Opening that page in mpv gives a
      // black frame, so the stream behind the page is extracted first.
      // The liveness probe may already have found it (cached on the source).
      final preResolved = _currentSource.resolvedMediaUrl;
      if (preResolved != null &&
          preResolved.isNotEmpty &&
          preResolved != sanitizedUrlStr) {
        AppLog.d('[PlayerScreen] Using media URL recovered from player page');
        sanitizedUrlStr = preResolved;
      } else if (!HtmlStreamResolver.looksLikeMediaUrl(sanitizedUrlStr)) {
        final resolved = await HtmlStreamResolver.resolve(
          sanitizedUrlStr,
          headers: playerHeaders,
        );
        if (resolved != null) {
          AppLog.d(
            '[PlayerScreen] HTML page resolved to media '
            '(${resolved.kind}): ${resolved.url}',
          );
          sanitizedUrlStr = resolved.url;
          playerHeaders.addAll(resolved.headers);
        }
      }

      final cleanUri = Uri.parse(sanitizedUrlStr);
      AppLog.d(
        '[PlayerScreen] Opening direct network stream URL: $cleanUri (headers: ${playerHeaders.keys})',
      );

      if (!mounted) return false;
      final epLabel = _currentEpisode != null
          ? 'S${_currentEpisode!.season ?? 1}:E${_currentEpisode!.episode ?? 1} - ${_currentEpisode!.title.isNotEmpty ? _currentEpisode!.title : "Episode ${_currentEpisode!.episode ?? 1}"}'
          : (widget.detail?.name ?? _currentTitle);
      setState(() => _statusMessage = 'Buffering $epLabel...');

      final lowerClean = sanitizedUrlStr.toLowerCase();
      final bool isLive =
          _currentSource.behaviorHints?['isLive'] == true ||
          _currentSource.addonName.toLowerCase() == 'iptv' ||
          _currentSource.name?.toLowerCase() == 'iptv' ||
          lowerClean.contains('/live/') ||
          lowerClean.contains('/hls/live');

      final bool isTorrentStream =
          isTorrent ||
          sanitizedUrlStr.contains(':8090') ||
          sanitizedUrlStr.contains('/stream?link=') ||
          sanitizedUrlStr.contains('/stream?');

      await PlayerSettings.applyPreOpenProperties(
        _player,
        isLive: isLive,
        isTorrent: isTorrentStream,
      );

      // Set native MPV properties for referer and user-agent directly on the player for web streams
      if (!isTorrentStream) {
        try {
          final dynamic platform = _player.platform;
          if (platform != null) {
            final referer =
                playerHeaders['Referer'] ?? playerHeaders['referer'];
            if (referer != null && referer.isNotEmpty) {
              await platform.setProperty('referrer', referer);
            }
            final ua =
                playerHeaders['User-Agent'] ?? playerHeaders['user-agent'];
            if (ua != null && ua.isNotEmpty) {
              await platform.setProperty('user-agent', ua);
            }
            final cookie = playerHeaders['Cookie'] ?? playerHeaders['cookie'];
            if (cookie != null && cookie.isNotEmpty) {
              await platform.setProperty('cookies', 'yes');
              await platform.setProperty(
                'http-header-fields',
                'Cookie: $cookie',
              );
            }
          }
        } catch (e) {
          AppLog.d(
            '[PlayerScreen] Warning setting native header properties: $e',
          );
        }
      }

      final startAt = PlaybackStartPolicy.sanitize(
        _resumeAtOverride ?? widget.initialPosition,
      );

      // HLS master: cap the FIRST rendition to what the measured link can
      // sustain. Without this mpv opens the highest variant (4K) and only
      // downshifts after the auto ladder's 10s window — which already looks
      // like a stall on a poor link.
      final startCap = _startHlsCapBps;
      if (startCap != null && QualityService.isHlsUrl(sanitizedUrlStr)) {
        try {
          final np = _player.platform as dynamic;
          await np.setProperty('hls-bitrate-max', '$startCap');
          AppLog.d('[Quality] HLS start cap: $startCap bps');
        } catch (_) {}
      }

      // Bound the wait for the first frame. Torrents get longer: the local
      // engine still has to seat the demuxer after warm-up. Live edges get
      // the longest window — a slow HLS handshake is not a dead link.
      _armStartupWatchdog(
        Duration(seconds: isLive ? 45 : (isTorrentStream ? 35 : 25)),
      );

      await _player.open(
        Media(
          cleanUri.toString(),
          httpHeaders: isTorrentStream ? null : playerHeaders,
          start: startAt,
        ),
        play: true,
      );

      await PlayerSettings.applyPostOpenProperties(_player);

      _setSubtitleScale(_subtitleScale);
      _applyVolume(_isMuted ? 0.0 : _volume, persist: false);

      AppLog.d(
        '[PlayerScreen SUCCESS] Player opened media successfully for $streamUrl',
      );

      _updateMediaTracks(_player.state.tracks);

      // The media is open even if the screen went away while it opened.
      if (!mounted) return true;
      setState(() {
        _isLoading = false;
      });

      _player.play();
      _startHideControlsTimer();
      // P4: one sound at a time — video starting pauses music.
      unawaited(
        GlobalMediaCoordinator.instance.notifyVideoStarted(
          title: _currentSource.name ?? '',
        ),
      );

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
          final targetId = detail.id.startsWith('tt')
              ? detail.id
              : (detail.tmdbId ?? detail.id);
          if (targetId.isNotEmpty) {
            final s = _currentEpisode?.season;
            final e = _currentEpisode?.episode;
            final initPos = widget.initialPosition?.inSeconds ?? 0;
            final dur =
                PlaybackDurationGuard.trusted(
                  _player.state.duration,
                  reference: _runtimeReference,
                )?.inSeconds ??
                0;
            final progress = (dur > 0 ? (initPos / dur) * 100.0 : 0.0).clamp(
              0.0,
              100.0,
            );

            TraktService.instance.isAuthenticated().then((authed) {
              if (authed) {
                TraktService.instance.scrobbleStart(
                  targetId,
                  progress,
                  season: s,
                  episode: e,
                );
              }
            });
            SimklService.instance.isAuthenticated().then((authed) {
              if (authed) {
                SimklService.instance.scrobbleStart(
                  targetId,
                  progress,
                  season: s,
                  episode: e,
                );
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
      // The media is open: the caller may treat this source as playing.
      return true;
    } catch (e, stackTrace) {
      AppLog.d(
        '[PlayerScreen ERROR] Failed to initialize stream URL: "$streamUrl"',
      );
      AppLog.d('[PlayerScreen ERROR] Exception: $e');
      AppLog.d('[PlayerScreen ERROR] StackTrace:\n$stackTrace');

      if (!mounted) return false;

      // A startup-timeout failover already owns the screen: this throw is the
      // open of the source it is replacing, so do not fight it for the UI.
      if (_failoverInProgress) return false;

      // A torrent that never became playable (no peers / no metadata / swarm
      // too slow) must NOT park the user on a black player or force them into
      // the picker: mark it dead and let the failover chain take the next
      // source (HTTP ranks first in the chain). One plain sentence, no tech.
      if (torrentRejected &&
          PlayerSettings.autoFailover.value &&
          _failoverChain.any(
            (s) => !_failedFingerprints.contains(SourceRanker.fingerprint(s)),
          )) {
        // The swarm's own measured speed is the best link sample we have for
        // a P2P start: remember it so the replacement source is chosen at a
        // rung this link can actually feed.
        final warmupMbps = TorrentStreamService().lastWarmupMbps;
        if (warmupMbps != null && warmupMbps > 0) {
          _startupMbps = warmupMbps;
          AppLog.d(
            '[Quality] torrent swarm measured ${warmupMbps.toStringAsFixed(1)} '
            'Mbps — capping the next source',
          );
        }
        _playGate.markDead(_currentSource);
        _showAudioHudToast(
          'This torrent has no working peers. Trying another source…',
        );
        _attemptSilentFailover(reason: 'torrent-unavailable');
        return false;
      }

      // Open the sources picker for episodes AND movies: a failed movie used
      // to show only status text with no way to switch.
      if (_sourcesPanelAvailable) {
        _openSourcesPanelWithError(
          torrentRejected
              ? 'This torrent has no working peers. Please pick another source below.'
              : 'Source failed to play. Please select another source below.',
        );
        return false;
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
      return false;
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
      final title =
          t.title ?? (lang != null ? lang.toUpperCase() : 'Track ${i + 1}');
      final idx = int.tryParse(t.id) ?? (i + 1);
      audioTracks.add(
        PlayerAudioTrack(
          index: idx,
          title: title,
          language: lang,
          channels: int.tryParse(t.channels?.toString() ?? ''),
        ),
      );
    }

    final subList = tracks.subtitle;
    final embeddedSubs = <PlayerEmbeddedSubtitle>[];
    for (int i = 0; i < subList.length; i++) {
      final t = subList[i];
      if (t.id == 'no' || t.id == 'auto') continue;
      final lang = t.language;
      final title =
          t.title ?? (lang != null ? lang.toUpperCase() : 'Track ${i + 1}');
      final idx = int.tryParse(t.id) ?? (i + 1);
      embeddedSubs.add(
        PlayerEmbeddedSubtitle(index: idx, title: title, language: lang),
      );
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
    //
    // mpv reports streams INCREMENTALLY: the first non-empty list often holds
    // a single track, so locking the gate on that list permanently blocked
    // the Hindi pick. Only a preference that was actually found (and applied)
    // may close the gate, and a manual user pick always wins.
    if (_audioAutoSelectDone || _audioUserPicked || audioTracks.isEmpty) {
      return;
    }
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
    if (preferred == null) return;
    if (preferred == _selectedAudioTrackIndex) {
      _audioAutoSelectDone = true; // already on the right track (alang did it)
      return;
    }
    try {
      final matching = _player.state.tracks.audio.firstWhere(
        (t) => t.id == preferred.toString(),
        orElse: () => AudioTrack(preferred.toString(), null, null),
      );
      _player.setAudioTrack(matching);
      final np = _player.platform as dynamic;
      np.setProperty('aid', preferred.toString());
      _audioAutoSelectDone = true;
      if (mounted) setState(() => _selectedAudioTrackIndex = preferred);
      AppLog.d(
        '[AudioGate] auto-selected track $preferred (hindi=${DubModeService.isHindi})',
      );
    } catch (e) {
      // Leave the gate open: a later (fuller) track list gets another try.
      AppLog.d('[AudioGate] auto-select skipped: $e');
    }
  }
}
