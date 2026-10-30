import 'package:flutter/material.dart';

import '../../design/prism_shadows.dart';
import '../../design/prism_tokens.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/offline_aware_scaffold.dart';
import '../../widgets/movie/movie_card.dart';

class DiscoverPage extends StatefulWidget {
  final String query;
  final bool isGenre;

  const DiscoverPage({super.key, required this.query, required this.isGenre});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  bool _isLoading = true;
  String? _error;
  List<MovieSection> _sections = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final manager = AddonManager.instance;
      List<MovieSection> sections;

      if (widget.isGenre) {
        sections = await manager.fetchByGenre(widget.query);
      } else {
        sections = await manager.searchAll(widget.query);
      }

      if (!mounted) return;
      setState(() {
        _sections = sections;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;

    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        final isLight = palette.isLight;
        final ink = isLight ? PrismLight.ink : Colors.white;

        return OfflineAwareScaffold(
          backgroundColor: palette.scaffoldBackgroundColor,
          body: Stack(
            children: [
              // ── Main Content Grid ──
              if (_isLoading)
                Center(
                  child: CircularProgressIndicator(color: palette.primaryColor),
                )
              else if (_error != null)
                ErrorView(error: _error, onRetry: _fetchData)
              else if (_sections.isEmpty)
                Center(
                  child: Text(
                    'No results found for "${widget.query}"',
                    style: TextStyle(
                      color: isLight ? PrismLight.inkSoft : Colors.white54,
                      fontSize: 16,
                    ),
                  ),
                )
              else
                _buildSectionsList(topPadding + kToolbarHeight + 20),

              // ── Tactile App Bar (no GPU blur shaders) ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: kToolbarHeight + topPadding,
                  padding: EdgeInsets.only(
                    top: topPadding,
                    left: 16,
                    right: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: PrismShadows.surfaceGradient(isLight),
                    border: Border(
                      bottom: BorderSide(
                        color: isLight
                            ? PrismLight.borderSubtle
                            : Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    boxShadow: PrismShadows.raised(
                      isLight: isLight,
                      scale: 0.6,
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: ink),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isGenre
                              ? 'Genre: ${widget.query}'
                              : 'Search: ${widget.query}',
                          style: TextStyle(
                            color: ink,
                            fontSize: isDesktop ? 22 : 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionsList(double topPadding) {
    // Let's aggregate all movies across sections into a single responsive grid
    final allMoviesMap = <String, Movie>{};
    for (var section in _sections) {
      for (var movie in section.movies) {
        if (!allMoviesMap.containsKey(movie.id)) {
          allMoviesMap[movie.id] = movie;
        }
      }
    }
    final allMovies = allMoviesMap.values.toList();

    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        sizing.sidePadding,
        topPadding,
        sizing.sidePadding,
        40 + MediaQuery.paddingOf(context).bottom,
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
      itemCount: allMovies.length,
      itemBuilder: (context, index) {
        return MovieCard(movie: allMovies[index]);
      },
    );
  }
}
