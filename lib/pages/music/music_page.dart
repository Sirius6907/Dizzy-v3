import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/perf/image_caps.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/music/music_track.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/music/music_download_service.dart';
import '../../services/music/music_library_service.dart';
import '../../services/music/music_player_controller.dart';
import '../../services/music/music_radio_service.dart';
import '../../services/music/music_mini_pip_service.dart';
import '../../services/music/music_service.dart';
import '../../services/music/music_settings.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/performance_liquid_lens.dart';
import '../settings/settings_page.dart';
import '../../utils/navigation/route_transitions.dart';


import 'widgets/music_sidebar.dart';
import 'widgets/music_top_header.dart';
import 'widgets/music_mobile_bottom_nav.dart';
import 'widgets/music_desktop_pip_widget.dart';
import 'widgets/music_bottom_player_bar.dart';
import 'widgets/music_expanded_player.dart';
import 'widgets/music_lyrics_drawer.dart';
import 'widgets/music_queue_drawer.dart';
import 'widgets/music_shortcuts_modal.dart';
import 'widgets/music_downloaded_tracks_modal.dart';
import 'widgets/music_track_details_modal.dart';
import 'modals/music_artist_detail_modal.dart';
import 'modals/music_album_detail_modal.dart';
import 'modals/music_curated_playlist_detail_modal.dart';
import 'modals/music_user_playlist_detail_modal.dart';
import 'views/music_home_view.dart';
import 'views/music_search_view.dart';
import 'views/music_browse_view.dart';
import 'views/music_radio_view.dart';
import 'views/music_library_view.dart';

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  final MusicService _musicService = MusicService.instance;
  final MusicPlayerController _playerController = MusicPlayerController.instance;
  final MusicLibraryService _libraryService = MusicLibraryService.instance;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  String _activeTab = 'Home'; // 'Home', 'Search', 'Browse', 'Radio', 'Library'

  Map<String, List<MusicTrack>> _sections = {};
  List<MusicArtist> _trendingArtists = [];
  List<MusicAlbum> _newReleases = [];
  List<MusicPlaylist> _curatedPlaylists = [];
  MusicTrack? _heroTrack;

  MusicSearchData _searchData = MusicSearchData.empty;
  MusicArtistDetails? _activeArtistModal;
  MusicAlbumDetails? _activeAlbumModal;
  MusicPlaylistDetails? _activeCuratedPlaylistModal;
  UserPlaylist? _activeUserPlaylistModal;

  bool _isLoading = true;
  bool _isSearching = false;
  bool _hasSearched = false;
  String _activeQuery = '';
  String _selectedFilter = 'All';
  Timer? _debounceTimer;

  bool _isPlayerExpanded = false;
  bool _showQueueDrawer = false;
  bool _showLyricsDrawer = false;
  bool _showShortcutsModal = false;
  bool _showDownloadsModal = false;
  String? _toastMessage;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _playerController.addListener(_onStateChanged);
    _libraryService.addListener(_onStateChanged);
    MusicDownloadService.instance.addListener(_onStateChanged);
    MusicSettings.changeNotifier.addListener(_onStateChanged);
    AppThemeService.currentPalette.addListener(_onStateChanged);
    MusicMiniPipService.instance.isMiniPipMode.addListener(_onStateChanged);
    _libraryService.init();
    MusicDownloadService.instance.init();
    _loadMusicData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _toastTimer?.cancel();
    _playerController.removeListener(_onStateChanged);
    _libraryService.removeListener(_onStateChanged);
    MusicDownloadService.instance.removeListener(_onStateChanged);
    MusicSettings.changeNotifier.removeListener(_onStateChanged);
    AppThemeService.currentPalette.removeListener(_onStateChanged);
    MusicMiniPipService.instance.isMiniPipMode.removeListener(_onStateChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  Future<void> _loadMusicData() async {
    setState(() => _isLoading = true);

    try {
      final sectionsFuture = _musicService.fetchFeaturedSections();
      final artistsFuture = _musicService.fetchTrendingArtists();
      final releasesFuture = _musicService.fetchNewReleases();
      final playlistsFuture = _musicService.fetchCuratedPlaylists();

      final results = await Future.wait([
        sectionsFuture,
        artistsFuture,
        releasesFuture,
        playlistsFuture,
      ]);

      final sections = results[0] as Map<String, List<MusicTrack>>;
      final artists = results[1] as List<MusicArtist>;
      final releases = results[2] as List<MusicAlbum>;
      final playlists = results[3] as List<MusicPlaylist>;

      MusicTrack? hero;
      if (sections.isNotEmpty && sections.values.first.isNotEmpty) {
        hero = sections.values.first.first;
      }

      if (mounted) {
        setState(() {
          _sections = sections;
          _trendingArtists = artists;
          _newReleases = releases;
          _curatedPlaylists = playlists;
          _heroTrack = hero;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading music data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _hasSearched = false;
        _searchData = MusicSearchData.empty;
        _activeQuery = '';
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() {
        _isSearching = true;
        _activeQuery = trimmed;
        if (_activeTab != 'Search') _activeTab = 'Search';
      });

      final results = await _musicService.searchFull(trimmed);

      if (mounted) {
        setState(() {
          _searchData = results;
          _isSearching = false;
          _hasSearched = true;
        });
      }
    });
  }

  void _onGenreTap(String query) {
    _searchController.text = query;
    _onSearchChanged(query);
  }

  Future<void> _openArtistModal(String artistId) async {
    _showToast('Loading artist details...');
    final details = await _musicService.fetchArtistDetails(artistId);
    if (details != null && mounted) {
      setState(() {
        _activeArtistModal = details;
      });
    }
  }

  Future<void> _openAlbumModal(String albumId) async {
    _showToast('Loading album...');
    final details = await _musicService.fetchAlbumDetails(albumId);
    if (details != null && mounted) {
      setState(() {
        _activeAlbumModal = details;
      });
    }
  }

  Future<void> _openCuratedPlaylistModal(String playlistId) async {
    _showToast('Loading playlist...');
    final details = await _musicService.fetchPlaylistDetails(playlistId);
    if (details != null && mounted) {
      setState(() {
        _activeCuratedPlaylistModal = details;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_searchFocusNode.hasFocus) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _playerController.togglePlayPause();
    } else if (key == LogicalKeyboardKey.keyJ) {
      final newPos = _playerController.position - const Duration(seconds: 5);
      _playerController.seekTo(newPos.inSeconds < 0 ? Duration.zero : newPos);
      _showToast('Seek -5s');
    } else if (key == LogicalKeyboardKey.keyL) {
      final newPos = _playerController.position + const Duration(seconds: 5);
      _playerController.seekTo(newPos);
      _showToast('Seek +5s');
    } else if (key == LogicalKeyboardKey.keyM) {
      _playerController.setVolume(_playerController.volume > 0 ? 0.0 : 1.0);
      _showToast(_playerController.volume == 0 ? 'Muted' : 'Unmuted');
    } else if (key == LogicalKeyboardKey.keyQ) {
      setState(() => _showQueueDrawer = !_showQueueDrawer);
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() => _isPlayerExpanded = !_isPlayerExpanded);
    } else if (key == LogicalKeyboardKey.slash ||
        (HardwareKeyboard.instance.isShiftPressed &&
            key == LogicalKeyboardKey.slash)) {
      setState(() => _showShortcutsModal = !_showShortcutsModal);
    } else if (key == LogicalKeyboardKey.escape) {
      if (_isPlayerExpanded) {
        setState(() => _isPlayerExpanded = false);
      } else if (_showQueueDrawer) {
        setState(() => _showQueueDrawer = false);
      } else if (_showLyricsDrawer) {
        setState(() => _showLyricsDrawer = false);
      } else if (_showShortcutsModal) {
        setState(() => _showShortcutsModal = false);
      } else if (_showDownloadsModal) {
        setState(() => _showDownloadsModal = false);
      } else if (_activeArtistModal != null ||
          _activeAlbumModal != null ||
          _activeCuratedPlaylistModal != null ||
          _activeUserPlaylistModal != null) {
        setState(() {
          _activeArtistModal = null;
          _activeAlbumModal = null;
          _activeCuratedPlaylistModal = null;
          _activeUserPlaylistModal = null;
          _showDownloadsModal = false;
        });
      } else {
        Navigator.maybePop(context);
      }
    }
  }

  void _showCreatePlaylistDialog({MusicTrack? initialTrack}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13151C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: const Color(0xFF7C5CFF).withValues(alpha: 0.3),
          ),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.playlist_add_rounded,
              color: Color(0xFF7C5CFF),
              size: 26,
            ),
            SizedBox(width: 10),
            Text(
              'New Playlist',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (initialTrack != null) ...[
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: initialTrack.coverUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      // P12: decode-capped (was full-res).
                      memCacheWidth: ImageCaps.kThumb,
                      maxWidthDiskCache: ImageCaps.kThumb,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          initialTrack.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          initialTrack.artist,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter playlist title...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1B1E2B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF7C5CFF)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C5CFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final pl = await _libraryService.createPlaylist(name);
                if (initialTrack != null) {
                  await _libraryService.addTrackToPlaylist(pl.id, initialTrack);
                  _showToast('Added "${initialTrack.title}" to "$name"');
                } else {
                  _showToast('Created playlist "$name"');
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text(
              'Create',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistMenu(MusicTrack track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final playlists = _libraryService.userPlaylists;
        return PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F121C).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        // P12: decode-capped (was full-res).
                        memCacheWidth: ImageCaps.kThumb,
                        maxWidthDiskCache: ImageCaps.kThumb,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            style: const TextStyle(
                              color: Color(0xFF9E9EA8),
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 10),

                // Spotify-Style Quick Actions Row
                Row(
                  children: [
                    // Start Radio
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          MusicRadioService.instance.startRadioForTrack(context, track);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C5CFF).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF7C5CFF).withValues(alpha: 0.35)),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.radio_rounded, color: Color(0xFF7C5CFF), size: 20),
                              SizedBox(height: 4),
                              Text(
                                'Song Radio',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Play Next
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _playerController.playTrackNext(track);
                          _showToast('"${track.title}" will play next ⏭️');
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.playlist_play_rounded, color: Colors.white, size: 20),
                              SizedBox(height: 4),
                              Text(
                                'Play Next',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Add to Queue
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _playerController.addTrackToQueue(track);
                          _showToast('Added to queue 📥');
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.queue_music_rounded, color: Colors.white, size: 20),
                              SizedBox(height: 4),
                              Text(
                                'Add Queue',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Quick Offline Download Action
                Builder(
                  builder: (context) {
                    final isDownloaded = MusicDownloadService.instance.isDownloaded(track.id);
                    final isQueued = MusicDownloadService.instance.isQueued(track.id);

                    return InkWell(
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (isDownloaded) {
                          await MusicDownloadService.instance.deleteDownloadedTrack(track.id);
                          _showToast('Removed "${track.title}" from downloads');
                        } else if (!isQueued) {
                          MusicDownloadService.instance.queueTrack(track);
                          _showToast('Added "${track.title}" to download queue');
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDownloaded
                              ? const Color(0xFF00B0FF).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDownloaded
                                ? const Color(0xFF00B0FF).withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isDownloaded
                                  ? Icons.download_done_rounded
                                  : (isQueued ? Icons.hourglass_top_rounded : Icons.download_rounded),
                              color: isDownloaded ? const Color(0xFF00E5FF) : Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isDownloaded
                                    ? 'Downloaded Offline (Tap to Remove)'
                                    : (isQueued ? 'Downloading / Queued...' : 'Download Track Offline'),
                                style: TextStyle(
                                  color: isDownloaded ? const Color(0xFF00E5FF) : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            if (isDownloaded)
                              const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),

                // Audio Specifications & ID3 Info
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    MusicTrackDetailsModal.show(context, track);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Color(0xFF00D2EF), size: 20),
                        SizedBox(width: 12),
                        Text(
                          'Song Info & Audio Specs (FLAC/Bitrate)',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Save to Playlist',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showCreatePlaylistDialog(initialTrack: track);
                      },
                      icon: const Icon(
                        Icons.add_rounded,
                        color: Color(0xFF7C5CFF),
                        size: 18,
                      ),
                      label: const Text(
                        'New Playlist',
                        style: TextStyle(
                          color: Color(0xFF7C5CFF),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.playlist_add_rounded,
                            color: Colors.white38,
                            size: 40,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'No custom playlists yet',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C5CFF),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showCreatePlaylistDialog(initialTrack: track);
                            },
                            child: const Text(
                              'Create First Playlist',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final pl = playlists[index];
                        final inPlaylist = pl.tracks.any((t) => t.id == track.id);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          tileColor: const Color(0xFF1B1E2B),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Color(0xFF7C5CFF),
                            ),
                          ),
                          title: Text(
                            pl.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${pl.tracks.length} tracks',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            inPlaylist
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: inPlaylist
                                ? const Color(0xFF00D294)
                                : Colors.white60,
                          ),
                          onTap: () async {
                            if (inPlaylist) {
                              await _libraryService.removeTrackFromPlaylist(
                                pl.id,
                                track.id,
                              );
                              _showToast('Removed from "${pl.title}"');
                            } else {
                              await _libraryService.addTrackToPlaylist(
                                pl.id,
                                track,
                              );
                              _showToast('Added to "${pl.title}"');
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 900;
  }

  @override
  Widget build(BuildContext context) {
    if (MusicMiniPipService.instance.isMiniPipMode.value) {
      return const MusicDesktopPipWidget();
    }

    final isDesktop = _isDesktop(context);

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF080A0F),
        body: Stack(
          children: [
            // Dynamic Ambient Background Atmosphere
            if (MusicSettings.enableAmbientLights.value)
              const Positioned.fill(
                child: AnimatedAmbientBackground(),
              ),

            // Main App Shell Layout
            Row(
              children: [
                if (isDesktop)
                  MusicSidebar(
                    activeTab: _activeTab,
                    onTabSelected: (tab) {
                      setState(() {
                        _activeTab = tab;
                        if (tab != 'Search') _hasSearched = false;
                      });
                    },
                    onShortcutsTap: () => setState(() => _showShortcutsModal = true),
                  ),

                // Main Page Content Area
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _buildTabContent(isDesktop),
                      ),

                      // Sticky Top Header (Search bar, status, settings)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: MusicTopHeader(
                          isDesktop: isDesktop,
                          searchController: _searchController,
                          searchFocusNode: _searchFocusNode,
                          isSearching: _isSearching,
                          onSearchChanged: _onSearchChanged,
                          onClearSearch: _clearSearch,
                          onSettingsTap: () {
                            Navigator.push(
                              context,
                              LiquidRevealRoute(
                                page: const SettingsPage(),
                                tapPosition: null,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Mobile Bottom Navigation Bar
            if (!isDesktop)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: MusicMobileBottomNav(
                  activeTab: _activeTab,
                  onTabSelected: (tab) {
                    setState(() {
                      _activeTab = tab;
                      if (tab != 'Search') _hasSearched = false;
                    });
                  },
                ),
              ),

            // Floating Mini-Player Bar
            if (_playerController.hasTrack && !_isPlayerExpanded)
              Positioned(
                left: isDesktop ? 260 : 12,
                right: 12,
                bottom: isDesktop ? 16 : (64.0 + MediaQuery.paddingOf(context).bottom + 10.0),
                child: MusicBottomPlayerBar(
                  playerController: _playerController,
                  isSaved: _libraryService.isTrackLiked(
                    _playerController.currentTrack?.id ?? '',
                  ),
                  onToggleSave: () {
                    if (_playerController.currentTrack != null) {
                      _libraryService.toggleLikeTrack(_playerController.currentTrack!);
                    }
                  },
                  onExpandTap: () => setState(() => _isPlayerExpanded = true),
                  onQueueTap: () => setState(() => _showQueueDrawer = true),
                  onLyricsTap: () => setState(() => _showLyricsDrawer = true),
                  onAddToPlaylist: () {
                    if (_playerController.currentTrack != null) {
                      _showAddToPlaylistMenu(_playerController.currentTrack!);
                    }
                  },
                ),
              ),

            // Queue Drawer
            if (_showQueueDrawer)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: MusicQueueDrawer(
                  onClose: () => setState(() => _showQueueDrawer = false),
                ),
              ),

            // Synced Lyrics Drawer
            if (_showLyricsDrawer && _playerController.hasTrack)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: MusicLyricsDrawer(
                  track: _playerController.currentTrack!,
                  playerController: _playerController,
                  onClose: () => setState(() => _showLyricsDrawer = false),
                ),
              ),

            // Modals: Artist Detail
            if (_activeArtistModal != null)
              Positioned.fill(
                child: MusicArtistDetailModal(
                  details: _activeArtistModal!,
                  onClose: () => setState(() => _activeArtistModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                  onOpenAlbum: _openAlbumModal,
                ),
              ),

            // Modals: Album Detail
            if (_activeAlbumModal != null)
              Positioned.fill(
                child: MusicAlbumDetailModal(
                  details: _activeAlbumModal!,
                  onClose: () => setState(() => _activeAlbumModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                ),
              ),

            // Modals: Curated Playlist Detail
            if (_activeCuratedPlaylistModal != null)
              Positioned.fill(
                child: MusicCuratedPlaylistDetailModal(
                  details: _activeCuratedPlaylistModal!,
                  onClose: () => setState(() => _activeCuratedPlaylistModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                ),
              ),

            // Modals: User Playlist Detail
            if (_activeUserPlaylistModal != null)
              Positioned.fill(
                child: MusicUserPlaylistDetailModal(
                  playlist: _activeUserPlaylistModal!,
                  onClose: () => setState(() => _activeUserPlaylistModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onRemoveTrack: (trackId) async {
                    await _libraryService.removeTrackFromPlaylist(_activeUserPlaylistModal!.id, trackId);
                    setState(() {
                      final updated = _libraryService.userPlaylists.firstWhere(
                        (p) => p.id == _activeUserPlaylistModal!.id,
                        orElse: () => _activeUserPlaylistModal!,
                      );
                      _activeUserPlaylistModal = updated;
                    });
                  },
                ),
              ),

            // Modals: Shortcuts
            if (_showShortcutsModal)
              Positioned.fill(
                child: MusicShortcutsModal(
                  onClose: () => setState(() => _showShortcutsModal = false),
                ),
              ),

            // Modals: Downloaded Offline Tracks
            if (_showDownloadsModal)
              Positioned.fill(
                child: MusicDownloadedTracksModal(
                  onClose: () => setState(() => _showDownloadsModal = false),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                ),
              ),

            // Fullscreen Expanded Now-Playing Player
            if (_isPlayerExpanded && _playerController.hasTrack)
              Positioned.fill(
                child: MusicExpandedPlayer(
                  playerController: _playerController,
                  isSaved: _libraryService.isTrackLiked(
                    _playerController.currentTrack?.id ?? '',
                  ),
                  onToggleSave: () {
                    if (_playerController.currentTrack != null) {
                      _libraryService.toggleLikeTrack(_playerController.currentTrack!);
                    }
                  },
                  onCollapse: () => setState(() => _isPlayerExpanded = false),
                  onQueueTap: () => setState(() => _showQueueDrawer = true),
                  onAddToPlaylist: () {
                    if (_playerController.currentTrack != null) {
                      _showAddToPlaylistMenu(_playerController.currentTrack!);
                    }
                  },
                ),
              ),

            // Temporary Notification Toast
            if (_toastMessage != null)
              Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C5CFF),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7C5CFF).withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _toastMessage!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(bool isDesktop) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF7C5CFF)),
            SizedBox(height: 16),
            Text(
              'Loading music discovery...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_activeTab == 'Search' || _hasSearched || _searchController.text.isNotEmpty) {
      return MusicSearchView(
        scrollController: _scrollController,
        searchData: _searchData,
        isSearching: _isSearching,
        activeQuery: _activeQuery,
        selectedFilter: _selectedFilter,
        onFilterSelected: (filter) => setState(() => _selectedFilter = filter),
        onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
        onAddToPlaylist: _showAddToPlaylistMenu,
        onOpenArtistModal: _openArtistModal,
        onOpenAlbumModal: _openAlbumModal,
        onOpenCuratedPlaylistModal: _openCuratedPlaylistModal,
        currentPlayingTrack: _playerController.currentTrack,
        isPlaying: _playerController.isPlaying,
      );
    }
    if (_activeTab == 'Browse') {
      return MusicBrowseView(
        scrollController: _scrollController,
        onGenreTap: _onGenreTap,
      );
    }
    if (_activeTab == 'Radio') {
      return MusicRadioView(
        scrollController: _scrollController,
        onGenreTap: _onGenreTap,
      );
    }
    if (_activeTab == 'Library') {
      return MusicLibraryView(
        scrollController: _scrollController,
        likedTracks: _libraryService.likedTracks,
        userPlaylists: _libraryService.userPlaylists,
        recentTracks: _libraryService.recentTracks,
        onCreatePlaylist: _showCreatePlaylistDialog,
        onOpenDownloads: () => setState(() => _showDownloadsModal = true),
        onPlayLiked: () {
          final liked = _libraryService.likedTracks;
          if (liked.isNotEmpty) {
            _playerController.playTrack(liked.first, playlistQueue: liked);
          } else {
            _showToast('No liked songs yet');
          }
        },
        onOpenUserPlaylist: (pl) => setState(() => _activeUserPlaylistModal = pl),
        onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
        onAddToPlaylist: _showAddToPlaylistMenu,
        currentPlayingTrack: _playerController.currentTrack,
        isPlaying: _playerController.isPlaying,
      );
    }

    return MusicHomeView(
      scrollController: _scrollController,
      isDesktop: isDesktop,
      onRefresh: _loadMusicData,
      heroTrack: _heroTrack,
      trendingArtists: _trendingArtists,
      newReleases: _newReleases,
      curatedPlaylists: _curatedPlaylists,
      sections: _sections,
      onArtistTap: (artist) {
        if (artist.id.isNotEmpty) {
          _openArtistModal(artist.id);
        } else {
          _onGenreTap(artist.name);
        }
      },
      onAlbumTap: (album) => _openAlbumModal(album.id),
      onCuratedPlaylistTap: (pl) => _openCuratedPlaylistModal(pl.id),
      onAddToPlaylist: _showAddToPlaylistMenu,
      onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
      onToggleSave: (t) {
        _libraryService.toggleLikeTrack(t);
        _showToast(
          _libraryService.isTrackLiked(t.id)
              ? 'Saved to Library'
              : 'Removed from Library',
        );
      },
      isTrackSaved: (id) => _libraryService.isTrackLiked(id),
    );
  }
}
