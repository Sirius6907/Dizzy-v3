import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/dizzy_tokens.dart';
import '../../../models/movie/movie.dart';
import '../../../models/movie/movie_detail.dart';
import '../../../services/metadata/metadata_service.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/home/home_page_settings.dart';
import 'home_hero_slide.dart';
import 'home_carousel_arrow.dart';

class HomeHeroCarousel extends StatefulWidget {
  final List<Movie> movies;

  const HomeHeroCarousel({super.key, required this.movies});

  @override
  State<HomeHeroCarousel> createState() => HomeHeroCarouselState();
}

class HomeHeroCarouselState extends State<HomeHeroCarousel> {
  final PageController _pageController = PageController();
  final Map<String, MovieDetail?> _detailsCache = {};

  Timer? _timer;
  int _index = 0;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    HomePageSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);

    if (widget.movies.isNotEmpty) {
      _fetchDetail(widget.movies.first);
      if (widget.movies.length > 1) _fetchDetail(widget.movies[1]);
    }
    _startTimer();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movies != widget.movies) {
      _index = 0;
      _detailsCache.clear();
      if (widget.movies.isNotEmpty) _fetchDetail(widget.movies.first);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _startTimer();
    }
  }

  @override
  void dispose() {
    HomePageSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!HomePageSettings.heroAutoRotate.value) return;
    if (widget.movies.length < 2) return;
    final interval = Duration(
      seconds: HomePageSettings.heroRotateSeconds.value,
    );
    _timer = Timer.periodic(interval, (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_index + 1) % widget.movies.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _pauseTimer() => _timer?.cancel();

  void _goTo(int index) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _fetchDetail(Movie movie) async {
    if (_detailsCache.containsKey(movie.id)) return;
    _detailsCache[movie.id] = null; // marks as "loading" so we don't refetch
    try {
      final detail = await MetadataService.fetchMeta(
        baseUrl: movie.addonBaseUrl,
        type: movie.type,
        imdbId: movie.id,
      );
      if (mounted) {
        setState(() => _detailsCache[movie.id] = detail);
      }
    } catch (_) {
      // Not critical — falls back to basic Movie data / title text.
    }
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _fetchDetail(widget.movies[index]);
    final next = (index + 1) % widget.movies.length;
    _fetchDetail(widget.movies[next]);
  }

  double _heroHeight(double screenWidth, double screenHeight) {
    final style = HomePageSettings.heroStyle.value;
    if (style == HeroStyle.compact) {
      if (screenWidth < 600) {
        return 340.0;
      } else if (screenWidth < 1100) {
        return 400.0;
      } else {
        return 450.0;
      }
    } else if (style == HeroStyle.minimalist) {
      if (screenWidth < 600) {
        return 220.0;
      } else if (screenWidth < 1100) {
        return 260.0;
      } else {
        return 280.0;
      }
    }

    // Default: Immersive
    if (screenWidth < 600) {
      return (screenHeight * 0.68).clamp(460.0, 640.0);
    } else if (screenWidth < 1100) {
      return (screenHeight * 0.70).clamp(520.0, 740.0);
    } else {
      // Maximized / Widescreen Desktop: generous height
      final targetHeight = screenHeight * 0.85;
      return targetHeight.clamp(680.0, 920.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = _heroHeight(screenWidth, screenHeight);
    final primaryColor = AppThemeService.currentPalette.value.primaryColor;

    if (widget.movies.isEmpty) {
      return SizedBox(height: heroHeight);
    }

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovering = true);
        _pauseTimer();
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        _startTimer();
      },
      child: SizedBox(
        height: heroHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.movies.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, i) {
                final movie = widget.movies[i];
                final detail = _detailsCache[movie.id];
                return HomeHeroSlide(
                  movie: movie,
                  detail: detail,
                  screenWidth: screenWidth,
                );
              },
            ),

            // Dot indicators
            if (widget.movies.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.movies.length, (i) {
                    final active = i == _index;
                    return GestureDetector(
                      onTap: () => _goTo(i),
                      child: Semantics(
                        button: true,
                        selected: active,
                        label: 'Show featured title ${i + 1}',
                        child: AnimatedContainer(
                        duration: DizzyMotion.fast,
                        curve: DizzyMotion.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: active
                              ? primaryColor
                              : Colors.white.withValues(alpha: 0.30),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.55),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

            // Arrows
            if (widget.movies.length > 1 &&
                _isHovering &&
                screenWidth > 600) ...[
              if (_index > 0)
                Positioned(
                  left: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: HomeCarouselArrow(
                      icon: Icons.arrow_back_ios_new_rounded,
                      label: 'Previous featured title',
                      onTap: () => _goTo(_index - 1),
                    ),
                  ),
                ),
              if (_index < widget.movies.length - 1)
                Positioned(
                  right: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: HomeCarouselArrow(
                      icon: Icons.arrow_forward_ios_rounded,
                      label: 'Next featured title',
                      onTap: () => _goTo(_index + 1),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

