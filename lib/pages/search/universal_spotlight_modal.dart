import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/anime/anime_media.dart';
import '../../models/movie/movie.dart';
import '../../models/music/music_track.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/anime/anilist_service.dart';
import '../../services/music/music_player_controller.dart';
import '../../services/music/music_service.dart';
import '../../services/search/search_history_helper.dart';
import '../../services/theme/app_theme_service.dart';
import '../../utils/perf/image_caps.dart';
import '../anime/anime_details_page.dart';
import '../details/details_page.dart';

/// Phase UX1 — Universal Spotlight Search
/// Unified instant search modal across Movies, TV Series, Anime, Music, and Artists.
class UniversalSpotlightModal extends StatefulWidget {
  final String? initialQuery;

  const UniversalSpotlightModal({super.key, this.initialQuery});

  static Future<void> show(BuildContext context, {String? initialQuery}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) => UniversalSpotlightModal(initialQuery: initialQuery),
    );
  }

  @override
  State<UniversalSpotlightModal> createState() => _UniversalSpotlightModalState();
}

enum SpotlightCategory { all, movies, anime, music, artists }

class _UniversalSpotlightModalState extends State<UniversalSpotlightModal> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  bool _isLoading = false;
  SpotlightCategory _activeCategory = SpotlightCategory.all;

  List<Movie> _movies = [];
  List<AnimeMedia> _animeList = [];
  List<MusicTrack> _tracks = [];
  List<MusicArtist> _artists = [];
  List<MusicAlbum> _albums = [];

  List<String> _searchHistory = [];
  static const String _historyKey = 'spotlight_search_history';

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialQuery!.trim();
      _performSearch(widget.initialQuery!.trim());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    if (mounted) {
      setState(() {
        _searchHistory = history;
      });
    }
  }

  Future<void> _saveQueryToHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    final next = SearchHistoryHelper.add(history, trimmed);
    await prefs.setStringList(_historyKey, next);
    if (mounted) {
      setState(() {
        _searchHistory = next;
      });
    }
  }

  Future<void> _removeHistoryItem(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    final next = SearchHistoryHelper.remove(history, query);
    await prefs.setStringList(_historyKey, next);
    if (mounted) {
      setState(() {
        _searchHistory = next;
      });
    }
  }

  Future<void> _clearAllHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) {
      setState(() {
        _searchHistory = [];
      });
    }
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isLoading = false;
        _movies = [];
        _animeList = [];
        _tracks = [];
        _artists = [];
        _albums = [];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 320), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _searchMoviesAndSeries(query),
        _searchAnime(query),
        _searchMusic(query),
      ]);

      if (!mounted) return;
      final movieRes = results[0] as List<Movie>;
      final animeRes = results[1] as List<AnimeMedia>;
      final musicRes = results[2] as MusicSearchData?;

      setState(() {
        _movies = movieRes;
        _animeList = animeRes;
        _tracks = musicRes?.tracks ?? [];
        _artists = musicRes?.artists ?? [];
        _albums = musicRes?.albums ?? [];
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Movie>> _searchMoviesAndSeries(String query) async {
    try {
      final sections = await AddonManager.instance.searchAll(query);
      final list = <Movie>[];
      final seenIds = <String>{};
      for (final s in sections) {
        for (final m in s.movies) {
          if (!seenIds.contains(m.id)) {
            seenIds.add(m.id);
            list.add(m);
          }
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<AnimeMedia>> _searchAnime(String query) async {
    try {
      final res = await AnilistService.instance.searchAnime(query, page: 1, perPage: 12);
      return res;
    } catch (_) {
      return [];
    }
  }

  Future<MusicSearchData?> _searchMusic(String query) async {
    try {
      final data = await MusicService.instance.searchFull(query);
      return data;
    } catch (_) {
      return null;
    }
  }

  void _openMovie(Movie movie) {
    _saveQueryToHistory(_searchController.text);
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsPage(movie: movie),
      ),
    );
  }

  void _openAnime(AnimeMedia anime) {
    _saveQueryToHistory(_searchController.text);
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeDetailsPage(anime: anime),
      ),
    );
  }

  void _playMusicTrack(MusicTrack track) {
    _saveQueryToHistory(_searchController.text);
    MusicPlayerController.instance.playTrack(track, playlistQueue: _tracks);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing "${track.title}" • ${track.artist}'),
        backgroundColor: const Color(0xFF1E212B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.currentPalette.value;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 16,
        vertical: isDesktop ? 40 : 20,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 820,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1117).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.primaryColor.withValues(alpha: 0.16),
                blurRadius: 36,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Color(0x99000000),
                blurRadius: 40,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(theme),
              _buildFilterChips(theme),
              const Divider(color: Color(0x1AFFFFFF), height: 1),
              Flexible(child: _buildBody(theme)),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppThemePalette theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.search_rounded,
              color: theme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              autofocus: true,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Search movies, series, anime, songs, artists…',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 15,
                  fontWeight: FontWeight.normal,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: _onQueryChanged,
              onSubmitted: (q) {
                _saveQueryToHistory(q);
                _performSearch(q);
              },
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
              onPressed: () {
                _searchController.clear();
                _onQueryChanged('');
              },
              tooltip: 'Clear',
            ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.white38, size: 22),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close (Esc)',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(AppThemePalette theme) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _categoryChip('All Results', SpotlightCategory.all, theme),
          _categoryChip('Movies & TV (${_movies.length})', SpotlightCategory.movies, theme),
          _categoryChip('Anime (${_animeList.length})', SpotlightCategory.anime, theme),
          _categoryChip('Music (${_tracks.length})', SpotlightCategory.music, theme),
          _categoryChip('Artists & Albums (${_artists.length + _albums.length})', SpotlightCategory.artists, theme),
        ],
      ),
    );
  }

  Widget _categoryChip(String label, SpotlightCategory cat, AppThemePalette theme) {
    final selected = _activeCategory == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _activeCategory = cat),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12.5,
        ),
        backgroundColor: const Color(0xFF161821),
        selectedColor: theme.primaryColor.withValues(alpha: 0.35),
        side: BorderSide(
          color: selected ? theme.primaryColor : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildBody(AppThemePalette theme) {
    if (_searchController.text.trim().isEmpty) {
      return _buildEmptyOrHistoryState(theme);
    }

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 16),
            const Text(
              'Searching across Dizzy Universe…',
              style: TextStyle(color: Colors.white60, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    final totalCount = _movies.length + _animeList.length + _tracks.length + _artists.length + _albums.length;
    if (totalCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, color: Colors.white24, size: 54),
              const SizedBox(height: 14),
              Text(
                'No results for "${_searchController.text.trim()}"',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Try checking the spelling or searching with a different term.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      physics: const BouncingScrollPhysics(),
      children: [
        if ((_activeCategory == SpotlightCategory.all || _activeCategory == SpotlightCategory.movies) &&
            _movies.isNotEmpty)
          _buildMovieSection(theme),
        if ((_activeCategory == SpotlightCategory.all || _activeCategory == SpotlightCategory.anime) &&
            _animeList.isNotEmpty)
          _buildAnimeSection(theme),
        if ((_activeCategory == SpotlightCategory.all || _activeCategory == SpotlightCategory.music) &&
            _tracks.isNotEmpty)
          _buildMusicTracksSection(theme),
        if ((_activeCategory == SpotlightCategory.all || _activeCategory == SpotlightCategory.artists) &&
            (_artists.isNotEmpty || _albums.isNotEmpty))
          _buildArtistsAndAlbumsSection(theme),
      ],
    );
  }

  Widget _buildEmptyOrHistoryState(AppThemePalette theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      physics: const BouncingScrollPhysics(),
      children: [
        if (_searchHistory.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RECENT SEARCHES',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              TextButton(
                onPressed: _clearAllHistory,
                child: const Text(
                  'Clear All',
                  style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SearchHistoryHelper.shown(_searchHistory).map((q) {
              return InputChip(
                avatar: const Icon(Icons.history_rounded, size: 16, color: Colors.white54),
                label: Text(q),
                labelStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
                backgroundColor: const Color(0xFF191C26),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onPressed: () {
                  _searchController.text = q;
                  _searchController.selection = TextSelection.fromPosition(
                    TextPosition(offset: q.length),
                  );
                  _performSearch(q);
                },
                onDeleted: () => _removeHistoryItem(q),
                deleteIconColor: Colors.white38,
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],
        const Text(
          'QUICK EXPLORE',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _quickTile(
              icon: Icons.movie_outlined,
              label: 'Trending Movies',
              query: 'Marvel',
            ),
            _quickTile(
              icon: Icons.tv_rounded,
              label: 'Popular Series',
              query: 'Game of Thrones',
            ),
            _quickTile(
              icon: Icons.animation_rounded,
              label: 'Anime Hits',
              query: 'Demon Slayer',
            ),
            _quickTile(
              icon: Icons.music_note_rounded,
              label: 'Top Music',
              query: 'Arijit Singh',
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickTile({
    required IconData icon,
    required String label,
    required String query,
  }) {
    return InkWell(
      onTap: () {
        _searchController.text = query;
        _performSearch(query);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF141620),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieSection(AppThemePalette theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Movies & TV Series', _movies.length, Icons.movie_outlined),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _movies.take(12).length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, idx) {
              final movie = _movies[idx];
              return InkWell(
                onTap: () => _openMovie(movie),
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 105,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 105,
                          height: 120,
                          color: const Color(0xFF1A1D27),
                          child: movie.poster != null && movie.poster!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: movie.poster!,
                                  memCacheWidth: ImageCaps.kThumb,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Center(
                                    child: Icon(Icons.movie_rounded, color: Colors.white24),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.movie_rounded, color: Colors.white24),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        movie.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildAnimeSection(AppThemePalette theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Anime', _animeList.length, Icons.animation_rounded),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _animeList.take(12).length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, idx) {
              final anime = _animeList[idx];
              final title = anime.titleEnglish.isNotEmpty
                  ? anime.titleEnglish
                  : (anime.titleRomaji.isNotEmpty ? anime.titleRomaji : 'Anime');
              return InkWell(
                onTap: () => _openAnime(anime),
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 105,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 105,
                          height: 120,
                          color: const Color(0xFF1A1D27),
                          child: anime.coverImageLarge.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: anime.coverImageLarge,
                                  memCacheWidth: ImageCaps.kThumb,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Center(
                                    child: Icon(Icons.animation_rounded, color: Colors.white24),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.animation_rounded, color: Colors.white24),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMusicTracksSection(AppThemePalette theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Music Tracks', _tracks.length, Icons.music_note_rounded),
        const SizedBox(height: 6),
        ..._tracks.take(6).map((track) {
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 44,
                height: 44,
                color: const Color(0xFF1D202B),
                child: track.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        memCacheWidth: 88,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white24),
                      )
                    : const Icon(Icons.music_note, color: Colors.white24),
              ),
            ),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00E5FF), size: 28),
              onPressed: () => _playMusicTrack(track),
              tooltip: 'Play Now',
            ),
            onTap: () => _playMusicTrack(track),
          );
        }),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildArtistsAndAlbumsSection(AppThemePalette theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Artists & Albums', _artists.length + _albums.length, Icons.album_rounded),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              ..._artists.take(6).map((artist) {
                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: const Color(0xFF1D202B),
                        backgroundImage: artist.pictureUrl.isNotEmpty
                            ? CachedNetworkImageProvider(artist.pictureUrl)
                            : null,
                        child: artist.pictureUrl.isEmpty
                            ? const Icon(Icons.person, color: Colors.white24)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 76,
                        child: Text(
                          artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              ..._albums.take(6).map((album) {
                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 72,
                          height: 72,
                          color: const Color(0xFF1D202B),
                          child: album.coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: album.coverUrl,
                                  memCacheWidth: 144,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(Icons.album, color: Colors.white24),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 72,
                        child: Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _sectionHeader(String title, int count, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF00E5FF)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '($count)',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0D12),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _KeyBadge(label: 'Ctrl+K'),
              SizedBox(width: 6),
              Text(
                'Spotlight everywhere',
                style: TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
            ],
          ),
          Row(
            children: [
              _KeyBadge(label: 'Esc'),
              SizedBox(width: 6),
              Text(
                'to dismiss',
                style: TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeyBadge extends StatelessWidget {
  final String label;

  const _KeyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1F222E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
