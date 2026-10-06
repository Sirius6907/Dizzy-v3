part of 'player_screen.dart';

extension _PlayerScreenStatePartySync on _PlayerScreenState {
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
        // Cinema-hall parity: same title (host seek-jump / failover
        // re-announce) → guest seek + play/pause match kare, sirf toast nahi.
        final s = PartySession.instance;
        if (msg.mediaRef == s.mediaRef) {
          final resync = PartyPlaybackSession.sameTitleResync(
            msg,
            guestPositionMs: _player.state.position.inMilliseconds,
            guestPlaying: _player.state.playing,
          );
          if (resync.seekMs != null) {
            await _player.seek(Duration(milliseconds: resync.seekMs!));
          }
          if (resync.play != null) {
            if (resync.play!) {
              await _player.play();
            } else {
              await _player.pause();
            }
          }
          return;
        }
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
  /// Polish P5: tokens only — same copy, same colors.
  Widget _buildPartyBanner() {
    final isHost = PartySession.instance.isHost;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 56,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DizzySpace.md - 2,
              vertical: DizzySpace.xs - 1,
            ),
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
                fontSize: DizzyType.caption,
                fontWeight: DizzyType.wBold,
              ),
            ),
          ),
        ),
      ),
    );
  }

}
