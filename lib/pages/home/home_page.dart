import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_tokens.dart';

import '../../models/movie/movie.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie_section.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/catalog/catalog_service.dart';
import '../../services/catalog/recommend_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/home/home_page_settings.dart';
import '../../services/home/brand_sections_cache.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/offline_aware_scaffold.dart';
import '../../widgets/home/continue_watching_slider.dart';
import 'home_notice_banner.dart';
import 'widgets/home_glass_app_bar.dart';
import 'widgets/home_hero_carousel.dart';
import 'widgets/home_scroll_track.dart';
import 'widgets/home_loading_skeleton.dart';
import 'widgets/home_brand_rail.dart';
import 'home_rails.dart';
import '../../widgets/movie/movie_slider_section.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import '../../services/theme/dock_settings.dart';
import '../../widgets/prism/prism_dock.dart';
import '../../services/updater/app_updater_service.dart';
import '../../widgets/updater/update_dialog.dart';
import '../../services/p2p/p2p_settings_service.dart';
import '../../widgets/p2p/p2p_warning_dialog.dart';
import '../../widgets/cloud/consent_onboarding_sheet.dart';
import '../../widgets/onboarding/username_gate_screen.dart';
import '../../services/cloud/cloud_auth_service.dart';

/// Trending row (P22 warm catalog edge feed → snapshot → hidden).
/// Fail-soft by design: offline/empty = no row, never an error.
/// Cards open DetailsPage via the built-in title fallback (tmdb: ids
/// auto-resolve through Cinemeta by title+year on tap).
/// Pure: catalog cards → top-of-home "New & Trending" section (null when
/// empty). Unit-tested.
MovieSection? buildTrendingSection(List<CatalogCard> cards) {
  if (cards.isEmpty) return null;
  return MovieSection(
    title: 'New & Trending',
    subtitle: 'Fresh in Hindi & English',
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

/// Personal rail from the taste engine (Phase 2). Null when the user is
/// still cold (under three events) so the row never shows fake relevance.
/// Pure: catalog cards → "For You" section. Unit-tested.
MovieSection? buildForYouSection(List<CatalogCard> cards) {
  if (cards.isEmpty) return null;
  final reason = cards.first.reason;
  final subtitle = reason.startsWith('genre:') && reason.length > 6
      ? 'More ${reason.substring(6)} for you'
      : 'Picked from what you watch';
  return MovieSection(
    title: 'For You',
    subtitle: subtitle,
    contentType: 'mixed',
    addonBaseUrl: '',
    catalog: AddonCatalog(
      type: 'mixed',
      id: 'for_you',
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

  // India-first rails (2026-11-09). Kept out of [_sections] so the addon
  // stream and similar-section injections never reorder or duplicate them;
  // they render below the addon sections, behind the language chips.
  MovieSection? _indiaSection;
  MovieSection? _hindiSection;
  final Map<String, MovieSection?> _southByLang = {};

  // Provider catalogs (Netflix / HBO Max / …) render as one brand rail.
  final List<MovieSection> _brandSections = [];


  static bool _hasShownIntro = false;
  late bool _showIntro;

  @override
  void initState() {
    super.initState();
    _showIntro = !_hasShownIntro;
    _hasShownIntro = true;

    HomePageSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onThemeChanged);
    MyListService.items.addListener(_onSettingsChanged);
    ContinueWatchingService.activeItems.addListener(_onSettingsChanged);
    LanguageChipState.instance.addListener(_onChipChanged);
    LanguageChipState.instance.load();

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

    // v1.3.3: the name is the first screen after the intro — before the
    // privacy sheet, because identity is the promise and consent is the
    // settings. Non-blocking when the server is unreachable.
    await UsernameGateFlow.maybeShow(context);
    if (!mounted) return;

    // S2 (v1.1.9): consent is explicit and shown once, after other startup UI.
    if (!CloudAuthService.onboarded.value) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor:
            AppThemeService.currentPalette.value.cardBackgroundColor,
        builder: (_) => const ConsentOnboardingSheet(),
      );
    }
    if (!mounted) return;
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
    AppThemeService.currentPalette.removeListener(_onThemeChanged);
    MyListService.items.removeListener(_onSettingsChanged);
    ContinueWatchingService.activeItems.removeListener(_onSettingsChanged);
    LanguageChipState.instance.removeListener(_onChipChanged);
    _scrollController.dispose();
    super.dispose();
  }

  List<MovieSection?> get _allRails => [_indiaSection, _hindiSection, _southByLang['all']];

  void _onChipChanged() {
    if (!mounted) return;
    _ensureSouthForChip();
    setState(() {});
  }

  /// The combined ta/te/ml rail is fetched at load; a specific-language chip
  /// that has no cached row yet fetches just that language.
  Future<void> _ensureSouthForChip() async {
    final chip = LanguageChipState.instance.value;
    if (!southRailLanguages.containsKey(chip) ||
        _southByLang.containsKey(chip)) {
      return;
    }
    final section = await _fetchSouthSection(chip);
    if (!mounted) return;
    setState(() => _southByLang[chip] = section);
  }

  Future<MovieSection?> _fetchSouthSection(String languages) async {
    try {
      final cards = await CatalogService.fetchFeed(
        feed: 'discover',
        type: 'movie',
        region: 'IN',
        language: languages,
      );
      if (cards == null || cards.isEmpty) return null;
      return buildRailSection(
        cards,
        title: 'South Blockbusters',
        subtitle: 'Tamil · Telugu · Malayalam',
        catalogId: 'south_blockbusters',
      );
    } catch (_) {
      return null;
    }
  }

  Future<MovieSection?> _fetchIndiaTrendingSection() async {
    try {
      // `fresh` (no language = hi+en) is the only genuinely real-time feed:
      // 45-day rolling window blended with now_playing(IN) + weekly trending,
      // so evergreen classics (3 Idiots-class) can never re-surface as
      // "trending" (2026-11-10 user report).
      final cards = await CatalogService.fetchFeed(
        feed: 'fresh',
        type: 'all',
      );
      if (cards == null || cards.isEmpty) return null;
      return buildRailSection(
        cards,
        title: 'India Trending',
        subtitle: 'What India is watching',
        catalogId: 'india_trending',
      );
    } catch (_) {
      return null;
    }
  }

  Future<MovieSection?> _fetchHindiNewSection() async {
    try {
      final cards = await CatalogService.fetchFeed(
        feed: 'fresh',
        type: 'all',
        language: 'hi',
      );
      if (cards == null || cards.isEmpty) return null;
      return buildRailSection(
        cards,
        title: 'Hindi New',
        subtitle: 'Fresh releases this month',
        catalogId: 'hindi_new',
      );
    } catch (_) {
      return null;
    }
  }

  /// Repaint only — a palette switch changes no catalog data, so it must not
  /// trigger the four recommendation fetches in [_refreshSimilarSections].
  void _onThemeChanged() {
    if (mounted) setState(() {});
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
    // A brand beat, not a loading gate. The splash leaves as soon as the
    // first home data lands; the ceiling keeps a slow network from turning
    // launch into a two-second stare at a logo.
    const minBeat = Duration(milliseconds: 250);
    const maxBeat = Duration(milliseconds: 600);
    final started = DateTime.now();
    while (mounted) {
      final elapsed = DateTime.now().difference(started);
      if (elapsed >= maxBeat) break;
      if (!_loading && elapsed >= minBeat) break;
      await Future.delayed(const Duration(milliseconds: 40));
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
      // `fresh` is the self-updating home rail: rolling release window,
      // Hindi and English interleaved 1:1, no manual curation.
      final cards = await CatalogService.fetchFeed(
        feed: 'fresh',
        type: 'all',
      );
      if (cards == null || cards.isEmpty) return null;
      return buildTrendingSection(cards);
    } catch (_) {
      return null;
    }
  }

  Future<MovieSection?> _fetchForYouSection() async {
    try {
      final cards = await RecommendService.fetch();
      if (cards == null || cards.isEmpty) return null;
      return buildForYouSection(cards);
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
      _indiaSection = null;
      _hindiSection = null;
      _southByLang.clear();
      _brandSections.clear();
    });

    // Seed the brand rail from the last-good cache before the network
    // answers (Part A, 2026-11-12). A slow or blipping addon start used to
    // blank the rail for the whole session; the cached rail renders
    // immediately and fresh sections replace it as they stream in.
    try {
      final cachedBrand = await BrandSectionsCache.load();
      if (mounted && cachedBrand.isNotEmpty && _brandSections.isEmpty) {
        setState(() => _brandSections.addAll(cachedBrand));
      }
    } catch (_) {
      // Fail-soft: the cache is an optimization, never a requirement.
    }

    try {
      final listFuture = HomePageSettings.fetchBestSimilarSection();
      final watchingFuture =
          HomePageSettings.fetchContinueWatchingSimilarSection();
      final traktFuture = HomePageSettings.fetchTraktRecommendationsSection();
      final simklFuture = HomePageSettings.fetchSimklRecommendationsSection();
      final trendingFuture = _fetchTrendingSection();
      final forYouFuture = _fetchForYouSection();
      final indiaFuture = _fetchIndiaTrendingSection();
      final hindiFuture = _fetchHindiNewSection();
      final southFuture = _fetchSouthSection('ta,te,ml');

      await for (final section in _manager.streamHomeSections()) {
        if (!mounted) return;
        if (isHiddenHomeSection(section)) continue;
        if (section.subtitle == providerAddonName) {
          setState(() {
            // Fresh replaces cached: drop any last-good section for the
            // same addon catalog so the rail never shows a stale row
            // beside its fresh twin.
            _brandSections.removeWhere(
              (s) =>
                  BrandSectionsCache.identityKey(s) ==
                  BrandSectionsCache.identityKey(section),
            );
            _brandSections.add(section);
            _featuredMovies = _pickFeatured(
              orderForFeatured(
                _allRails.whereType<MovieSection>().toList(),
                _sections,
              ),
            );
            if (_loading && _featuredMovies.isNotEmpty) _loading = false;
          });
          continue;
        }

        setState(() {
          insertHomeSection(_sections, section);

          // Re-pick featured movies with the new section
          _featuredMovies =
              _pickFeatured(orderForFeatured(_allRails.whereType<MovieSection>().toList(), _sections));

          // Stop full-page loading as soon as we have enough to show the hero
          if (_loading && _featuredMovies.isNotEmpty) {
            _loading = false;
          }
        });
      }

      // Persist the fresh brand sections as the new last-good cache once
      // the stream has finished (or died) — Part A, 2026-11-12.
      if (_brandSections.isNotEmpty) {
        unawaited(BrandSectionsCache.save(_brandSections));
      }

      // Inject recommendation sections (List, Continue Watching, Trakt, Simkl)
      final results = await Future.wait([
        listFuture,
        watchingFuture,
        traktFuture,
        simklFuture,
        trendingFuture,
        forYouFuture,
        indiaFuture,
        hindiFuture,
        southFuture,
      ]);
      if (mounted) {
        // Fresh rail first, then the personal rail above it once warm.
        final trending = results[4];
        final forYou = results[5];
        if (trending != null) {
          setState(() => _sections.insert(0, trending));
        }
        if (forYou != null) {
          setState(() => _sections.insert(0, forYou));
        }
        setState(() {
          _indiaSection = results[6];
          _hindiSection = results[7];
          _southByLang['all'] = results[8];
          _featuredMovies = _pickFeatured(
            orderForFeatured(_allRails.whereType<MovieSection>().toList(), _sections),
          );
        });
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
      for (final movie in section.movies.where((m) => !isHiddenHeroMovie(m)).take(3)) {
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
        if (isHiddenHeroMovie(movie)) continue;
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: palette.isLight
              ? [PrismLight.bg, PrismLight.bg]
              : [PrismDark.bg, PrismDark.sunken],
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
              child: _buildHomeList(palette),
            ),
        ],
      ),
    );

    return OfflineAwareScaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      body: _buildBody(backgroundContent, topPadding, context),
    );
  }

  /// Home list: notice → hero → continue watching → addon sections →
  /// language chips → India rails → dock clearance.
  Widget _buildHomeList(AppThemePalette palette) {
    final chip = LanguageChipState.instance.value;
    final rails = railsForChip(
      chip,
      india: _indiaSection,
      hindi: _hindiSection,
      south: _southByLang[southRailLanguages.containsKey(chip) ? chip : 'all'],
    );
    final len = _sections.length;
    final itemCount = len + 6 + rails.length;

    return ListView.builder(
      controller: _scrollController,
      clipBehavior: Clip.none,
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Phase E: notice slot (update banner / announcements /
        // activeNotice). Renders SizedBox.shrink() when idle.
        if (index == 0) return const HomeNoticeBanner();
        if (index == 1) {
          // No featured movie (offline cold start / empty catalog):
          // keep the app-bar clearance only. Reserving the full
          // hero height left a blank screen above Continue Watching.
          if (!HomePageSettings.enableSpotlight.value ||
              _featuredMovies.isEmpty) {
            return SizedBox(
              height: PrismLayout.homeAppBarClearance(context),
            );
          }
          return HomeHeroCarousel(movies: _featuredMovies);
        }
        if (index == 2) {
          return const ContinueWatchingSlider(typeFilter: 'main');
        }
        if (index >= 3 && index < 3 + len) {
          final sectionIdx = index - 3;
          final isLastTwo = sectionIdx >= (len - 2);
          return ValueListenableBuilder<bool>(
            valueListenable: HomePageSettings.enableCalendar,
            builder: (context, calEnabled, _) {
              return MovieSliderSection(
                section: _sections[sectionIdx],
                showCalendarButton: calEnabled && isLastTwo,
              );
            },
          );
        }
        if (index == 3 + len) {
          return HomeBrandRail(brandSections: _brandSections);
        }
        if (index == 4 + len) {
          return _buildLanguageChips(palette);
        }
        if (index < 5 + len + rails.length) {
          final railIdx = index - (5 + len);
          return MovieSliderSection(section: rails[railIdx]);
        }
        return SizedBox(height: PrismLayout.dockClearance(context));
      },
    );
  }

  /// Sticky-in-place language filter for the India rails. 'All' shows every
  /// rail; a language narrows the set (Hindi New / the South rail).
  Widget _buildLanguageChips(AppThemePalette palette) {
    final selected = LanguageChipState.instance.value;
    const chips = <String, String>{
      'all': 'All',
      'hi': 'Hindi',
      'ta': 'Tamil',
      'te': 'Telugu',
      'ml': 'Malayalam',
    };

    Widget chip(String value, String label) {
      final isSelected = selected == value;
      return GestureDetector(
        onTap: () => LanguageChipState.instance.set(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? palette.primaryColor
                : palette.cardBackgroundColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : palette.silverAccent,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (final entry in chips.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: chip(entry.key, entry.value),
            ),
        ],
      ),
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
          child: PrismDock(
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
      color: AppThemeService.currentPalette.value.isLight
          ? PrismLight.bg
          : PrismDark.bg,
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
        duration: const Duration(milliseconds: 300),
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
                        colors: palette.isLight
                            ? const [
                                PrismLight.ink,
                                PrismLight.ink,
                                PrismLight.ink,
                                PrismAccent.accentTextLight,
                              ]
                            : [
                                Colors.white,
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
