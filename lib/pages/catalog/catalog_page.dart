import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_tokens.dart';

import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/movie/movie_card.dart';

class CatalogPage extends StatefulWidget {
  final MovieSection section;

  const CatalogPage({super.key, required this.section});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final List<Movie> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;

  String? _selectedGenre;
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  final ScrollController _genreScrollController = ScrollController();

  bool _canScrollGenresLeft = false;
  bool _canScrollGenresRight = true;
  bool _isHoveringGenres = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _genreScrollController.addListener(_updateGenreScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateGenreScrollButtons();
    });
    _loadItems(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _genreScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && _hasMore) {
        _loadItems();
      }
    }
  }

  void _updateGenreScrollButtons() {
    if (!_genreScrollController.hasClients) return;
    setState(() {
      _canScrollGenresLeft = _genreScrollController.position.pixels > 0;
      _canScrollGenresRight =
          _genreScrollController.position.pixels <
          _genreScrollController.position.maxScrollExtent;
    });
  }

  void _scrollGenres(double directionMultiplier) {
    if (!_genreScrollController.hasClients) return;
    final viewportWidth = _genreScrollController.position.viewportDimension;
    final target =
        _genreScrollController.offset +
        (viewportWidth * 0.7 * directionMultiplier);
    _genreScrollController.animateTo(
      target.clamp(0.0, _genreScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadItems({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _items.clear();
        _hasMore = true;
        _error = null;
      });
    }

    if (!_hasMore) return;

    setState(() => _isLoading = true);

    try {
      List<Movie> newItems = [];

      if (_isSearching && _searchQuery.isNotEmpty) {
        // Search usually doesn't support pagination in Stremio natively in the same way,
        // but we'll try to fetch it.
        if (refresh) {
          newItems = await MetadataService.search(
            baseUrl: widget.section.addonBaseUrl,
            type: widget.section.contentType,
            catalogId: widget.section.catalog.id,
            query: _searchQuery,
          );
          _hasMore =
              false; // Usually search returns all relevant results or doesn't support skip
        }
      } else {
        newItems = await MetadataService.fetchCatalog(
          baseUrl: widget.section.addonBaseUrl,
          type: widget.section.contentType,
          catalogId: widget.section.catalog.id,
          genre: _selectedGenre,
          skip: _items.length,
        );
      }

      if (!mounted) return;

      setState(() {
        if (newItems.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(newItems);
        }
        _isLoading = false;
      });

      // If content doesn't fill the viewport yet, load more immediately.
      // This fixes fullscreen mode where the initial batch doesn't produce
      // enough scroll extent to ever trigger _onScroll.
      if (_hasMore && !_isLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          if (_scrollController.position.maxScrollExtent <= 0) {
            _loadItems();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onGenreSelected(String? genre) {
    if (_selectedGenre == genre) return;
    setState(() {
      _selectedGenre = genre;
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadItems(refresh: true);
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchQuery = '';
      });
      _loadItems(refresh: true);
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query.trim();
      _selectedGenre = null; // Clear genre when searching
    });
    _loadItems(refresh: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
    _loadItems(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.06);

    final topPadding = MediaQuery.of(context).padding.top;
    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;

    // Calculate safe top padding for grid based on if genres are available
    final hasGenres = widget.section.catalog.genres.isNotEmpty && !_isSearching;
    final gridTopPadding =
        topPadding + kToolbarHeight + (hasGenres ? 60 : 20) + 20;

    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // ── Main Content Grid ──
          if (_items.isEmpty && _isLoading)
            Center(
              child: CircularProgressIndicator(color: palette.primaryColor),
            )
          else if (_items.isEmpty && _error != null)
            ErrorView(error: _error, onRetry: () => _loadItems(refresh: true))
          else if (_items.isEmpty)
            Center(
              child: Text(
                'No items found',
                style: TextStyle(color: inkSoft, fontSize: 16),
              ),
            )
          else
            GridView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                sizing.sidePadding,
                gridTopPadding,
                sizing.sidePadding,
                40 + MediaQuery.paddingOf(context).bottom, // Bottom padding
              ),
              physics: const BouncingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    ((MediaQuery.sizeOf(context).width -
                                sizing.sidePadding * 2 +
                                sizing.spacing) /
                            (sizing.cardWidth + sizing.spacing))
                        .floor()
                        .clamp(2, 10),
                childAspectRatio: 1 / 1.48,
                crossAxisSpacing: sizing.spacing,
                mainAxisSpacing: sizing.spacing,
              ),
              itemCount: _items.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: palette.primaryColor,
                    ),
                  );
                }
                return MovieCard(movie: _items[index]);
              },
            ),

          // ── App Bar & Filters ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  padding: EdgeInsets.only(top: topPadding),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.scaffoldBackgroundColor.withValues(alpha: 0.90),
                        palette.scaffoldBackgroundColor.withValues(alpha: 0.60),
                      ],
                    ),
                    border: Border(bottom: BorderSide(color: hairline)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Row
                      SizedBox(
                        height: kToolbarHeight,
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_rounded,
                                size: 20,
                              ),
                              color: ink,
                              tooltip: 'Back',
                              onPressed: () => Navigator.pop(context),
                            ),
                            if (!_isSearching)
                              Expanded(
                                child: Text(
                                  widget.section.title,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (_isSearching)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: TextField(
                                    controller: _searchController,
                                    autofocus: true,
                                    style: TextStyle(color: ink, fontSize: 16),
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: _onSearchSubmitted,
                                    decoration: InputDecoration(
                                      hintText: 'Search...',
                                      hintStyle: TextStyle(color: inkSoft),
                                      border: InputBorder.none,
                                      suffixIcon: IconButton(
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 20,
                                        ),
                                        color: inkSoft,
                                        tooltip: 'Clear search',
                                        onPressed: _clearSearch,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (!_isSearching &&
                                widget.section.catalog.supportsSearch)
                              IconButton(
                                icon: const Icon(Icons.search_rounded),
                                color: inkSoft,
                                tooltip: 'Search',
                                onPressed: () {
                                  setState(() {
                                    _isSearching = true;
                                  });
                                },
                              ),
                            if (!_isSearching) const SizedBox(width: 8),
                          ],
                        ),
                      ),

                      // Genres Row
                      if (hasGenres)
                        MouseRegion(
                          onEnter: (_) =>
                              setState(() => _isHoveringGenres = true),
                          onExit: (_) =>
                              setState(() => _isHoveringGenres = false),
                          child: Stack(
                            children: [
                              SizedBox(
                                height: 50,
                                child: ListView.separated(
                                  controller: _genreScrollController,
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  physics: const BouncingScrollPhysics(),
                                  itemCount:
                                      widget.section.catalog.genres.length + 1,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    if (index == 0) {
                                      return _GenreChip(
                                        label: 'All',
                                        isSelected: _selectedGenre == null,
                                        onTap: () => _onGenreSelected(null),
                                      );
                                    }
                                    final genre = widget
                                        .section
                                        .catalog
                                        .genres[index - 1];
                                    return _GenreChip(
                                      label: genre,
                                      isSelected: _selectedGenre == genre,
                                      onTap: () => _onGenreSelected(genre),
                                    );
                                  },
                                ),
                              ),
                              if (isDesktop) ...[
                                if (_canScrollGenresLeft)
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: _buildScrollArrow(
                                      Icons.arrow_back_ios_new_rounded,
                                      'Scroll genres left',
                                      () => _scrollGenres(-1),
                                      _isHoveringGenres,
                                    ),
                                  ),
                                if (_canScrollGenresRight)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: _buildScrollArrow(
                                      Icons.arrow_forward_ios_rounded,
                                      'Scroll genres right',
                                      () => _scrollGenres(1),
                                      _isHoveringGenres,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollArrow(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
    bool isVisible,
  ) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    return Center(
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !isVisible,
          child: Tooltip(
            message: tooltip,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isLight
                      ? PrismLight.raisedTop
                      : Colors.black.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLight ? PrismLight.borderSubtle : Colors.white24,
                  ),
                ),
                child: Icon(icon, color: ink, size: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenreChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final inkSoft = isLight
        ? PrismLight.inkSoft
        : Colors.white.withValues(alpha: 0.7);
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.12);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.primaryColor
              : (isLight
                    ? PrismLight.raisedTop
                    : Colors.white.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? palette.primaryColor : hairline,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: palette.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : inkSoft,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
