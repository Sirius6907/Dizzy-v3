import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';

import '../../models/movie/movie.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie_section.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/catalog/catalog_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/home/home_page_settings.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/offline_aware_scaffold.dart';
import '../../widgets/home/continue_watching_slider.dart';
import 'widgets/home_glass_app_bar.dart';
import 'widgets/home_hero_carousel.dart';
import 'widgets/home_scroll_track.dart';
import 'widgets/home_loading_skeleton.dart';
import '../../widgets/movie/movie_slider_section.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import '../../services/theme/dock_settings.dart';
import '../../widgets/common/app_liquid_dock.dart';
import '../../services/updater/app_updater_service.dart';
import '../../widgets/updater/update_dialog.dart';
import '../../services/p2p/p2p_settings_service.dart';
import '../../widgets/p2p/p2p_warning_dialog.dart';
import '../../widgets/cloud/consent_onboarding_sheet.dart';
import '../../widgets/onboarding/onboarding_superpower_sheet.dart';
import '../../services/cloud/cloud_auth_service.dart';

/// Trending row (P22 warm catalog edge feed → snapshot → hidden).
/// Fail-soft by design: offline/empty = no row, never an error.
/// Cards open DetailsPage via the built-in title fallback (tmdb: ids
/// auto-resolve through Cinemeta by title+year on tap).
/// Pure: catalog cards → top-of-home "Trending Now" section (null when
/// empty). Unit-tested.
MovieSection? buildTrendingSection(List<CatalogCard> cards) {
  if (cards.isEmpty) return null;
  return MovieSection(
    title: 'Trending Now',
    subtitle: 'What everyone is watching',
    contentType: 'mixed',
    addonBaseUrl: '',
    catalog: AddonCatalog(
      type: 'mixed',
      id: 'trending',
      genres: const [],
      supportsSearch: false,
      supportsSkip: false,
    ),
    movies: [
      for (final c in cards)
        Movie(
          id: 'tmdb:${c.id}',
          name: c.title,
          poster: c.poster,
          year: c.year.isEmpty ? null : c.year,
          type: c.mediaType == 'tv' ? 'series' : 'movie',
          addonBaseUrl: '',
          imdbRating: c.rating > 0 ? c.rating.toStringAsFixed(1) : null,
        ),
    ],
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _manager = AddonManager.instance;
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  final List<MovieSection> _sections = [];
  String? _error;

  List<Movie> _featuredMovies = [];

  static bool _hasShownIntro = false;
  late bool _showIntro;

  @override
  void initState() {
    super.initState();
    _showIntro = !_hasShownIntro;
    _hasShownIntro = true;

    HomePageSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    MyListService.items.addListener(_onSettingsChanged);
    ContinueWatchingService.activeItems.addListener(_onSettingsChanged);

    if (_showIntro) {
      _playIntro();
    }

    _loadHome();
    if (!_showIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runStartupDialogs();
      });
    }
  }

  static bool _hasRunStartupDialogs = false;
  static bool _hasAutoCheckedUpdate = false;

  Future<void> _runStartupDialogs() async {
    if (_hasRunStartupDialogs || !mounted) return;
    _hasRunStartupDialogs = true;

    // 1. Check & show Update dialog first
    await _checkAutoUpdate();
    if (!mounted) return;

    // 2. Check & show P2P warning dialog after update dialog
    await _checkP2pWarning();
    if (!mounted) return;

    // S2 (v1.1.9): consent is explicit and shown once, after other startup UI.
    if (!CloudAuthService.onboarded.value) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: DizzyVoid.surface1,
        builder: (_) => const ConsentOnboardingSheet(),
      );
    }
    if (!mounted) return;

    // UX4: Guided Onboarding Superpower Cards (one-time on first launch)
    await OnboardingSuperpowerSheet.maybeShow(context);
  }

  Future<void> _checkAutoUpdate() async {
    if (_hasAutoCheckedUpdate) return;
    _hasAutoCheckedUpdate = true;
    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();
      if (updateInfo != null && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      }
    } catch (e) {
      debugPrint('[HomePage] Auto update check failed: $e');
    }
  }

  Future<void> _checkP2pWarning() async {
    try {
      final shouldShow = await P2pSettingsService.shouldShowWarning();
      if (shouldShow && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => const P2pWarningDialog(),
        );
      }
    } catch (e) {
      debugPrint('[HomePage] P2P warning check failed: $e');
    }
  }

  @override
  void dispose() {
    HomePageSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    MyListService.items.removeListener(_onSettingsChanged);
    ContinueWatchingService.activeItems.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    _refreshSimilarSections();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _injectSimilarSections({
    MovieSection? listSection,
    MovieSection? watchingSection,
    MovieSection? traktSection,
    MovieSection? simklSection,
  }) {
    if (!mounted) return;
    setState(() {
      // Remove any existing recommendation sections by title or catalog ID so they NEVER duplicate
      _sections.removeWhere(
        (s) =>
            s.title.toLowerCase().startsWith('because you') ||
            s.catalog.id == 'bestsimilar' ||
            s.catalog.id == 'bestsimilar_list' ||
            s.catalog.id == 'bestsimilar_watching' ||
            s.catalog.id == 'trakt_recommendations' ||
            s.catalog.id == 'simkl_recommendations',
      );

      final toInsert = <MovieSection>[];
      if (watchingSection != null) toInsert.add(watchingSection);
      if (listSection != null) toInsert.add(listSection);
      if (traktSection != null) toInsert.add(traktSection);
      if (simklSection != null) toInsert.add(simklSection);

      if (toInsert.isEmpty) return;

      switch (HomePageSettings.similarPosition.value) {
        case SimilarSectionPosition.top:
          _sections.insertAll(0, toInsert);
          break;
        case SimilarSectionPosition.underCinemeta:
          final insertIdx = _sections.length > 1 ? 1 : _sections.length;
          _sections.insertAll(insertIdx, toInsert);
          break;
        case SimilarSectionPosition.middle:
          final insertIdx = _sections.length ~/ 2;
          _sections.insertAll(insertIdx, toInsert);
          break;
        case SimilarSectionPosition.bottom:
          _sections.addAll(toInsert);
          break;
      }
    });
  }

  Future<void> _refreshSimilarSections() async {
    if (!mounted) return;
    final listFuture = HomePageSettings.fetchBestSimilarSection(
      forceRefresh: true,
    );
    final watchingFuture = HomePageSettings.fetchContinueWatchingSimilarSection(
      forceRefresh: true,
    );
    final traktFuture = HomePageSettings.fetchTraktRecommendationsSection(
      forceRefresh: true,
    );
    final simklFuture = HomePageSettings.fetchSimklRecommendationsSection(
      forceRefresh: true,
    );

    final results = await Future.wait([
      listFuture,
      watchingFuture,
      traktFuture,
      simklFuture,
    ]);
    if (!mounted) return;
    _injectSimilarSections(
      listSection: results[0],
      watchingSection: results[1],
      traktSection: results[2],
      simklSection: results[3],
    );
  }

  Future<void> _playIntro() async {
    // Show intro for 1.8 seconds so it feels fast and allows full dock shader pre-warming
    await Future.delayed(const Duration(milliseconds: 1800));

    // If still loading critical data, wait a bit longer (up to a timeout or until ready)
    while (_loading && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (mounted) {
      setState(() => _showIntro = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runStartupDialogs();
      });
    }
  }

  Future<MovieSection?> _fetchTrendingSection() async {
    try {
      final cards = await CatalogService.fetchFeed(
        feed: 'trending',
        type: 'all',
      );
      if (cards == null || cards.isEmpty) return null;
      return buildTrendingSection(cards);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadHome() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _sections.clear();
      _featuredMovies.clear();
    });

    try {
      final listFuture = HomePageSettings.fetchBestSimilarSection();
      final watchingFuture =
          HomePageSettings.fetchContinueWatchingSimilarSection();
      final traktFuture = HomePageSettings.fetchTraktRecommendationsSection();
      final simklFuture = HomePageSettings.fetchSimklRecommendationsSection();
      final trendingFuture = _fetchTrendingSection();

      await for (final section in _manager.streamHomeSections()) {
        if (!mounted) return;

        setState(() {
          _sections.add(section);

          // Re-pick featured movies with the new section
          _featuredMovies = _pickFeatured(_sections);

          // Stop full-page loading as soon as we have enough to show the hero
          if (_loading && _featuredMovies.isNotEmpty) {
            _loading = false;
          }
        });
      }

      // Inject recommendation sections (List, Continue Watching, Trakt, Simkl)
      final results = await Future.wait([
        listFuture,
        watchingFuture,
        traktFuture,
        simklFuture,
        trendingFuture,
      ]);
      if (mounted) {
        // Trending (warm catalog edge feed) goes FIRST — above everything.
        final trending = results[4];
        if (trending != null) {
          setState(() => _sections.insert(0, trending));
        }
        _injectSimilarSections(
          listSection: results[0],
          watchingSection: results[1],
          traktSection: results[2],
          simklSection: results[3],
        );
      }

      // If we got through the whole stream and still loading (e.g., no addons worked)
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Picks a handful of varied movies to rotate through in the hero —
  /// one from each of the first few sections so it isn't just a wall of
  /// the same catalog, deduped by id+type.
  List<Movie> _pickFeatured(List<MovieSection> sections) {
    final featured = <Movie>[];
    final seen = <String>{};

    for (final section in sections) {
      for (final movie in section.movies.take(3)) {
        final key = '${movie.type}:${movie.id}';
        if (seen.add(key)) {
          featured.add(movie);
          break;
        }
      }
      if (featured.length >= 6) break;
    }

    // Fallback: if sections were too sparse to get variety, top up from
    // the first section's list.
    if (featured.length < 2 && sections.isNotEmpty) {
      for (final movie in sections.first.movies) {
        final key = '${movie.type}:${movie.id}';
        if (seen.add(key)) featured.add(movie);
        if (featured.length >= 6) break;
      }
    }

    return featured;
  }

  void _navigateToSettings(Offset? tapPosition) async {
    await Navigator.push(
      context,
      LiquidRevealRoute(page: const SettingsPage(), tapPosition: tapPosition),
    );
    // Reload when returning from settings (addons may have changed)
    _loadHome();
  }

  void _navigateToSearch(Offset? tapPosition) {
    Navigator.push(
      context,
      LiquidRevealRoute(page: const SearchPage(), tapPosition: tapPosition),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final palette = AppThemeService.currentPalette.value;

    final backgroundContent = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [DizzyColors.bg, DizzyVoid.voidA],
        ),
      ),
      child: Stack(
        children: [
          // ── Main scrollable content ──
          if (_loading && !_showIntro && _sections.isEmpty)
            HomeLoadingSkeleton(topPadding: topPadding)
          else if (_error != null && _sections.isEmpty)
            ErrorView(error: _error, onRetry: _loadHome)
          else
            RefreshIndicator(
              color: palette.primaryColor,
              backgroundColor: palette.cardBackgroundColor,
              onRefresh: _loadHome,
              child: ListView.builder(
                controller: _scrollController,
                clipBehavior: Clip.none,
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                itemCount: _sections.length + 3,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    if (!HomePageSettings.enableSpotlight.value) {
                      return SizedBox(height: topPadding + 76);
                    }
                    return HomeHeroCarousel(movies: _featuredMovies);
                  }
                  if (index == 1) {
                    return const ContinueWatchingSlider(typeFilter: 'main');
                  }
                  if (index == _sections.length + 2) {
                    return SizedBox(
                      height: 110.0 + MediaQuery.paddingOf(context).bottom,
                    );
                  }
                  final sectionIdx = index - 2;
                  final isLastTwo = sectionIdx >= (_sections.length - 2);
                  return ValueListenableBuilder<bool>(
                    valueListenable: HomePageSettings.enableCalendar,
                    builder: (context, calEnabled, _) {
                      return MovieSliderSection(
                        section: _sections[sectionIdx],
                        showCalendarButton: calEnabled && isLastTwo,
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );

    return OfflineAwareScaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      body: _buildBody(backgroundContent, topPadding, context),
    );
  }

  /// Uses the same shader-free composition on every platform. This avoids
  /// capturing the scrolling page and keeps Skia and Impeller visually equal.
  Widget _buildBody(
    Widget backgroundContent,
    double topPadding,
    BuildContext context,
  ) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final overlayChildren = <Widget>[
      // ── Floating glass app bar ──
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: HomeGlassAppBar(
          topPadding: topPadding,
          onSearchTap: _navigateToSearch,
          onSettingsTap: _navigateToSettings,
        ),
      ),

      // ── Custom Scroll Track ──
      if (MediaQuery.sizeOf(context).width > 800) // Desktop only
        Positioned(
          right: 24,
          bottom: 40,
          child: HomeScrollTrack(controller: _scrollController),
        ),

      // ── Liquid Dock Navbar ──
      Positioned(
        bottom: 12.0 + bottomInset,
        left: 0,
        right: 0,
        child: Center(
          child: AppLiquidDock(
            currentDestination: DockItemKey.home,
            onSettingsTap: () => _navigateToSettings(null),
            onSearchTap: () => _navigateToSearch(null),
          ),
        ),
      ),

      // ── Intro Splash Screen ──
      Positioned.fill(child: _buildIntroOverlay(context)),
    ];

    return Container(
      color: DizzyVoid.voidA,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: backgroundContent),
          ...overlayChildren,
        ],
      ),
    );
  }

  Widget _buildIntroOverlay(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final titleSize = (screenWidth * 0.08).clamp(40.0, 56.0);
    final subtitleSize = (screenWidth * 0.03).clamp(16.0, 20.0);
    final iconSize = (screenWidth * 0.12).clamp(48.0, 72.0);
    final palette = AppThemeService.currentPalette.value;

    return IgnorePointer(
      ignoring: !_showIntro,
      child: AnimatedOpacity(
        opacity: _showIntro ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        child: Container(
          color: palette.scaffoldBackgroundColor,
          child: Stack(
            children: [
              // Metallic ambient light orb behind the logo
              Center(
                child: Container(
                  width: iconSize * 3.5,
                  height: iconSize * 3.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        palette.primaryColor.withValues(alpha: 0.22),
                        palette.accentColor.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primaryColor.withValues(alpha: 0.28),
                            blurRadius: 36,
                            spreadRadius: 2,
                            offset: const Offset(-4, -4),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 28,
                            offset: const Offset(6, 12),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/icon.png',
                        width: iconSize * 1.5,
                        height: iconSize * 1.5,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          const Color(0xFFFFFFFF),
                          palette.silverAccent,
                          const Color(0xFFCBD5E1),
                          palette.primaryColor.withValues(alpha: 0.85),
                        ],
                        stops: const [0.0, 0.35, 0.70, 1.0],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        'Dizzy',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your Cinema Universe',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: subtitleSize,
                        fontWeight: FontWeight.w600,
                        color: palette.accentColor.withValues(alpha: 0.7),
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: palette.silverAccent.withValues(alpha: 0.12),
                        width: 1,
                      ),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.04),
                          palette.primaryColor.withValues(alpha: 0.04),
                        ],
                      ),
                    ),
                    child: Text(
                      'by sirius',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.amberAccent.withValues(alpha: 0.75),
                        letterSpacing: 3.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
