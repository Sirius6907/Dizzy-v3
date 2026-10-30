import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../services/theme/app_theme_service.dart';
import '../../models/anime/anime_media.dart';
import '../../models/stream/stream_model.dart';
import '../../services/anime/anime_scraper_service.dart';
import '../../services/anime/anime_library_service.dart';
import '../player/player_screen.dart';

import '../../services/anime/extractors/anidb_extractor.dart';
import '../../services/stream/stream_probe_race.dart';

/// Theme-aware clay surface tokens for this sheet.
abstract final class _Clay {
  static bool get isLight => AppThemeService.currentPalette.value.isLight;
  static Color get accent => AppThemeService.currentPalette.value.primaryColor;
  static Color get ink => isLight ? PrismLight.ink : Colors.white;
  static Color get inkSoft => isLight ? PrismLight.inkSoft : Colors.white70;
  static Color get muted => isLight ? PrismLight.inkSoft : Colors.white54;
  static Color get panel => isLight ? PrismLight.raisedTop : PrismDark.raised;
  static Color get border =>
      isLight ? PrismLight.borderSubtle : PrismDark.borderSubtle;
}

class AnimeStreamSheet extends StatefulWidget {
  final AnimeMedia anime;
  final int episodeNumber;
  final bool autoPlay;
  final List<AniDbEpisode>? aniDbEpisodes;
  final int? totalEpisodes;

  const AnimeStreamSheet({
    super.key,
    required this.anime,
    required this.episodeNumber,
    this.autoPlay = false,
    this.aniDbEpisodes,
    this.totalEpisodes,
  });

  @override
  State<AnimeStreamSheet> createState() => _AnimeStreamSheetState();
}

class _AnimeStreamSheetState extends State<AnimeStreamSheet> {
  final AnimeScraperService _scraper = AnimeScraperService.instance;
  final AnimeLibraryService _library = AnimeLibraryService.instance;

  final List<StreamSource> _allSources = [];
  String _selectedCategory = 'all'; // 'all', 'sub', 'dub'
  bool _isScraping = true;
  bool _hasAutoPlayed = false;
  String? _error;
  StreamSubscription<StreamSource>? _streamSub;

  @override
  void initState() {
    super.initState();
    _startScraping();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  void _startScraping() {
    setState(() {
      _allSources.clear();
      _isScraping = true;
      _error = null;
    });

    // Parallel probe race: every source is health-checked concurrently.
    // The FIRST source verified alive triggers autoplay instantly —
    // a dead source can no longer block the queue (old serial await
    // added up to 3s of delay per dead source).
    final race = StreamProbeRace(
      onVerifiedBatch: (batch) {
        if (mounted) {
          setState(() => _allSources.addAll(batch));
        }
      },
    );

    race.winner.then((src) {
      if (!mounted || src == null) return;
      if (widget.autoPlay && !_hasAutoPlayed) {
        _hasAutoPlayed = true;
        _playSource(src);
      }
    });

    _streamSub = _scraper
        .scrapeStreamsStream(
          anime: widget.anime,
          episodeNumber: widget.episodeNumber,
        )
        .listen(
          (source) {
            race.offer(source);
          },
          onError: (e) {
            if (mounted) {
              setState(() {
                _isScraping = false;
                _error = e.toString();
              });
            }
          },
          onDone: () {
            race.close();
            if (mounted) {
              setState(() {
                _isScraping = false;
                if (_allSources.isEmpty) {
                  _error =
                      'No playable streams found for Episode ${widget.episodeNumber}.';
                }
              });
            }
          },
        );
  }

  List<StreamSource> get _filteredSources {
    if (_selectedCategory == 'sub') {
      return _allSources
          .where(
            (s) =>
                !(s.description?.toLowerCase().contains('dub') ?? false) &&
                !(s.name?.toLowerCase().contains('dub') ?? false),
          )
          .toList();
    } else if (_selectedCategory == 'dub') {
      return _allSources
          .where(
            (s) =>
                (s.description?.toLowerCase().contains('dub') ?? false) ||
                (s.name?.toLowerCase().contains('dub') ?? false),
          )
          .toList();
    }
    return _allSources;
  }

  void _playSource(StreamSource source) {
    _library.updateProgress(
      anime: widget.anime,
      episodeNumber: widget.episodeNumber,
      positionSeconds: 1,
      durationSeconds: 1440,
    );

    final detail = AnimeScraperService.toMovieDetail(
      widget.anime,
      aniDbEpisodes: widget.aniDbEpisodes,
      customEpisodeCount: widget.totalEpisodes,
    );
    final video = AnimeScraperService.toVideo(
      widget.anime,
      widget.episodeNumber,
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          source: source,
          title:
              '${widget.anime.displayTitle} - Episode ${widget.episodeNumber}',
          backdropUrl: widget.anime.backdropUrl,
          detail: detail,
          episode: video,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSources;

    return Container(
      decoration: BoxDecoration(
        gradient: PrismShadows.surfaceGradient(
          AppThemeService.currentPalette.value.isLight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: PrismShadows.floating(
          isLight: AppThemeService.currentPalette.value.isLight,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              gradient: PrismShadows.pressedGradient(
                AppThemeService.currentPalette.value.isLight,
              ),
              borderRadius: BorderRadius.circular(3),
              boxShadow: PrismShadows.pressed(
                isLight: AppThemeService.currentPalette.value.isLight,
                scale: 0.5,
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.anime.displayTitle} • Ep ${widget.episodeNumber}',
                        style: TextStyle(
                          color: _Clay.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (_isScraping) ...[
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _Clay.accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Cascading native anime extractors...',
                              style: TextStyle(
                                color: PrismAccent.text(_Clay.isLight),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else
                            Text(
                              '${_allSources.length} sources found',
                              style: TextStyle(
                                color: _Clay.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close_rounded, color: _Clay.inkSoft),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Sub / Dub Category Filter Pills
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('All (${_allSources.length})', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Sub', 'sub'),
                const SizedBox(width: 8),
                _buildFilterChip('Dub', 'dub'),
              ],
            ),
          ),

          const SizedBox(height: 6),
          Divider(color: _Clay.border, height: 1),

          // Stream list
          Flexible(
            child: _allSources.isEmpty && _isScraping
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: _Clay.accent),
                        const SizedBox(height: 14),
                        Text(
                          'Extracting MegaPlay, VidWish, AllAnime & Miruro streams...',
                          style: TextStyle(color: _Clay.inkSoft, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _allSources.isEmpty && _error != null
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 40,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: TextStyle(color: _Clay.inkSoft, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _Clay.accent,
                            foregroundColor: PrismAccent.onAccent,
                          ),
                          onPressed: _startScraping,
                          child: const Text('Retry Scraping'),
                        ),
                      ],
                    ),
                  )
                : filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No ${_selectedCategory.toUpperCase()} sources found.',
                      style: TextStyle(color: _Clay.muted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final s = filtered[index];
                      final isDub =
                          (s.description?.toLowerCase().contains('dub') ??
                              false) ||
                          (s.name?.toLowerCase().contains('dub') ?? false);

                      return RepaintBoundary(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _playSource(s),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              constraints: const BoxConstraints(
                                minHeight: PrismSpace.giant,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _Clay.panel,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _Clay.border),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _Clay.accent.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: _Clay.accent,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name ?? 'Stream Source',
                                          style: TextStyle(
                                            color: _Clay.ink,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          s.description ?? s.addonName,
                                          style: TextStyle(
                                            color: _Clay.inkSoft,
                                            fontSize: PrismType.micro,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _Clay.panel,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: _Clay.border),
                                    ),
                                    child: Text(
                                      isDub ? 'DUB' : 'SUB',
                                      style: TextStyle(
                                        color: _Clay.inkSoft,
                                        fontSize: PrismType.micro,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String category) {
    final isSelected = _selectedCategory == category;
    final primaryColor = _Clay.accent;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: PrismSpace.giant,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : _Clay.panel,
          borderRadius: BorderRadius.circular(PrismRadius.pill),
          border: Border.all(color: isSelected ? primaryColor : _Clay.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? PrismAccent.onAccent : _Clay.inkSoft,
            fontSize: PrismType.caption,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
