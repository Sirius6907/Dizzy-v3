import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';

import '../../utils/perf/image_caps.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';

import '../../models/movie/link.dart';
import '../../models/movie/video.dart';
import '../../models/movie/movie_detail.dart';

import '../../models/stream/stream_model.dart';
import './player_screen.dart';
import './watch_resolve_controller.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/scraper/stream_scraper.dart';
import '../../services/player/player_settings.dart';
import '../../services/theme/glass_settings.dart';
import '../../widgets/common/performance_liquid_lens.dart';
import 'widgets/watch_source_card.dart';
import 'widgets/watch_shimmer_card.dart';
import 'widgets/watch_empty_sources.dart';
import 'widgets/watch_style.dart';

// ---------------------------------------------------------------------------
// WatchScreen
// ---------------------------------------------------------------------------
class WatchScreen extends StatefulWidget {
  final MovieDetail detail;
  final Video? selectedEpisode;
  final String type;
  final Duration? initialPosition;

  const WatchScreen({
    super.key,
    required this.detail,
    this.selectedEpisode,
    required this.type,
    this.initialPosition,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen>
    with SingleTickerProviderStateMixin {
  // Stream sources
  final List<StreamSource> _sources = [];
  bool _isLoadingSources = true;

  // P17: resolve pipeline (scrape + dub gate + batching + autoplay race)
  // lives in WatchResolveController; the screen owns the visible list.
  late final WatchResolveController _resolve;

  // Instant autoplay (Phase 1)
  bool _userPickedSource = false; // set when the user taps a source manually
  bool _autoplayCountdownActive = false;

  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // Scroll
  final ScrollController _sourcesScrollController = ScrollController();
  final ScrollController _mainScrollController = ScrollController();

  // Addon priority caching
  Map<String, int>? _cachedAddonOrder;
  Map<String, int> get _addonOrder {
    if (_cachedAddonOrder != null) return _cachedAddonOrder!;
    final map = <String, int>{};
    final allAddons = AddonManager.instance.addons;
    for (int i = 0; i < allAddons.length; i++) {
      final a = allAddons[i];
      map[a.manifest.name.toLowerCase()] = i;
      map[a.manifest.id.toLowerCase()] = i;
      if (a.manifest.id == 'builtin.dizzyhttp' || a.baseUrl == 'builtin:dizzyhttp') {
        map['dizzyhttp'] = i;
      }
      if (a.manifest.id == 'builtin.dizzy' || a.baseUrl == 'builtin:dizzy') {
        map['dizzy'] = i;
      }
    }
    return _cachedAddonOrder = map;
  }

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _animController.forward();
    // P17: resolve pipeline moved to WatchResolveController (pure move —
    // callbacks below are the old inline setState/snackbar/Navigator code).
    _resolve = WatchResolveController(
      type: widget.type,
      streamId: widget.selectedEpisode?.id ?? widget.detail.id,
      title: widget.detail.name,
      year: int.tryParse(widget.detail.year ?? ''),
      season: widget.selectedEpisode?.season,
      episode: widget.selectedEpisode?.episode,
      mediaTitle: widget.detail.name,
      embeddedStreams: widget.selectedEpisode?.streams ?? const [],
      isMounted: () => mounted,
      shouldAutoOpen: () =>
          !_userPickedSource &&
          PlayerSettings.autoplayFirstVerified.value,
      hindiCountReader: () => _sources
          .where((s) => s.hasAudioLanguage('hindi',
              mediaTitle: widget.detail.name))
          .length,
      onBatch: (batch) {
        if (!mounted) return;
        setState(() {
          _sources.addAll(batch);
          _isLoadingSources = false;
        });
      },
      onLoadingDone: () {
        if (mounted && _isLoadingSources) {
          setState(() => _isLoadingSources = false);
        }
      },
      onInstantOpen: _openPlayerInstant,
      onEnglishFallback: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Is content ka Hindi dub nahi mila — English (default) play kar raha hoon'),
            duration: Duration(seconds: 4),
          ),
        );
      },
    );
    _resolve.start();
  }

  @override
  void dispose() {
    _resolve.dispose();
    _animController.dispose();
    _sourcesScrollController.dispose();
    _mainScrollController.dispose();
    super.dispose();
  }

  /// Opens the player with a verified source the instant it's found.
  /// Shows a short "playing now" chip so the user knows what's happening.
  void _openPlayerInstant(StreamSource source) {
    if (!mounted || _autoplayCountdownActive) return;
    _autoplayCountdownActive = true;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          source: source,
          title: source.displayTitle,
          detail: widget.detail,
          episode: widget.selectedEpisode,
          initialPosition: widget.initialPosition,
          failoverSources: List.of(_sources),
        ),
      ),
    ).then((_) {
      // Player closed — don't auto-hijack with another source after return.
      if (mounted) {
        _autoplayCountdownActive = false;
        _userPickedSource = true;
      }
    });
  }

  String? _selectedAddonFilter;
  String? _selectedSizeFilter;
  String _selectedTypeFilter = 'all'; // 'all', 'debrid', 'torrent', 'direct'
  String _selectedSeederFilter = 'all'; // 'all', 'most', '50+', '20+', '5+', '1+'
  String _selectedAudioFilter = 'all'; // 'all', 'multi', 'english', 'hindi', 'german', 'french', 'spanish', 'russian', 'japanese', 'italian'

  List<StreamSource> get _filteredSources {
    var list = List<StreamSource>.from(_sources);
    if (_selectedAddonFilter != null) {
      list = list.where((s) => s.addonName == _selectedAddonFilter).toList();
    }
    if (_selectedTypeFilter == 'debrid') {
      list = list.where((s) => s.isDebrid).toList();
    } else if (_selectedTypeFilter == 'torrent') {
      list = list.where((s) => s.isTorrent).toList();
    } else if (_selectedTypeFilter == 'direct') {
      list = list.where((s) => s.isHttpDirect).toList();
    }
    if (_selectedSizeFilter != null) {
      switch (_selectedSizeFilter) {
        case '<1gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz < 1024 * 1024 * 1024;
          }).toList();
          break;
        case '1-5gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz >= 1024 * 1024 * 1024 && sz <= 5.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
        case '5-15gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz > 5.0 * 1024 * 1024 * 1024 && sz <= 15.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
        case '15-30gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz > 15.0 * 1024 * 1024 * 1024 && sz <= 30.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
        case '>30gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz > 30.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
      }
    }

    if (_selectedSeederFilter == '50+') {
      list = list.where((s) => (s.seeders ?? 0) >= 50).toList();
    } else if (_selectedSeederFilter == '20+') {
      list = list.where((s) => (s.seeders ?? 0) >= 20).toList();
    } else if (_selectedSeederFilter == '5+') {
      list = list.where((s) => (s.seeders ?? 0) >= 5).toList();
    } else if (_selectedSeederFilter == '1+') {
      list = list.where((s) => (s.seeders ?? 0) >= 1).toList();
    }

    // Filter by audio language / dub
    if (_selectedAudioFilter != 'all') {
      list = list
          .where((s) => s.hasAudioLanguage(_selectedAudioFilter,
              mediaTitle: widget.detail.name))
          .toList();
    }

    // Filter by active status of built-in providers
    if (!AddonManager.instance.isDizzyActive) {
      list = list.where((s) => !s.isTorrent || s.isDebrid).toList();
    }
    if (!AddonManager.instance.isDizzyHttpActive) {
      // v1.2.0-P1: built-in HTTP sources now carry unique site keys
      // ('flystream', 'vidsrc', ...). Legacy 'dizzyhttp' labels from
      // pre-v1.2.0 Continue Watching rows are filtered too.
      list = list
          .where((s) =>
              !ScraperManager.instance.isBuiltinHttpSource(s.addonName) &&
              s.addonName.toLowerCase() != 'dizzyhttp')
          .toList();
    }

    // Cached dynamic addon priority lookup from user's installed addons order
    final addonOrder = _addonOrder;

    if (_selectedSeederFilter == 'most') {
      list.sort((a, b) => (b.seeders ?? 0).compareTo(a.seeders ?? 0));
    } else if (_selectedSizeFilter == 'largest') {
      list.sort((a, b) => (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0));
    } else if (_selectedSizeFilter == 'smallest') {
      list.sort((a, b) => (a.sizeBytes ?? double.infinity).compareTo(b.sizeBytes ?? double.infinity));
    } else {
      list.sort((a, b) {
        final orderA = addonOrder[a.addonName.toLowerCase()] ?? 999;
        final orderB = addonOrder[b.addonName.toLowerCase()] ?? 999;
        if (orderA != orderB) {
          return orderA.compareTo(orderB);
        }
        final qComp = b.qualityRank.compareTo(a.qualityRank);
        if (qComp != 0) return qComp;
        return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
      });
    }
    return list;
  }

  String _getSeederFilterLabel(String filter) {
    switch (filter) {
      case 'most':
        return 'Most Seeds';
      case '50+':
        return '50+ Seeds';
      case '20+':
        return '20+ Seeds';
      case '5+':
        return '5+ Seeds';
      case '1+':
        return 'Active Seeds';
      default:
        return 'All Seeds';
    }
  }

  String _getSizeFilterLabel(String? filter) {
    switch (filter) {
      case '<1gb':
        return '< 1 GB';
      case '1-5gb':
        return '1–5 GB';
      case '5-15gb':
        return '5–15 GB';
      case '15-30gb':
        return '15–30 GB';
      case '>30gb':
        return '> 30 GB';
      case 'largest':
        return 'Largest';
      case 'smallest':
        return 'Smallest';
      default:
        return 'All Sizes';
    }
  }

  bool _isDesktop() => MediaQuery.sizeOf(context).width >= 900;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final bgUrl = widget.detail.background ?? widget.detail.poster;
    final isDesktop = _isDesktop();

    final background = Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: WatchColors.bg)),
        if (bgUrl != null) _buildBackdrop(bgUrl, screenSize, isDesktop),
      ],
    );
    final content = Stack(
      children: [
        SafeArea(
          child: isDesktop
              ? _buildDesktopLayout(screenSize)
              : _buildMobileLayout(screenSize),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          child: _buildBackButton(),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: WatchColors.bg,
      body: ValueListenableBuilder<bool>(
        valueListenable: GlassSettings.enabled,
        builder: (context, enabled, _) {
          if (enabled) {
            return LiquidGlassView(
              realTimeCapture: true,
              useSync: true,
              pixelRatio: 0.85,
              refreshRate: LiquidGlassRefreshRate.deviceRefreshRate,
              regionCapture: true,
              backgroundWidget: background,
              child: content,
            );
          }
          return Stack(children: [background, content]);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Backdrop
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBackdrop(String url, Size screenSize, bool isDesktop) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            // P12: decode-capped (was full-res).
            memCacheWidth: ImageCaps.kCardW,
            maxWidthDiskCache: ImageCaps.kCardW,
            errorWidget: (_, __, ___) => const ColoredBox(color: WatchColors.bg),
          ),
          // Left-to-right dimming: dark on left (text side), lighter on right
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  WatchColors.bg.withValues(alpha: isDesktop ? 0.92 : 0.88),
                  WatchColors.bg.withValues(alpha: isDesktop ? 0.70 : 0.60),
                  WatchColors.bg.withValues(alpha: isDesktop ? 0.20 : 0.15),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Bottom vertical gradient for legibility
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  WatchColors.bg.withValues(alpha: 0.30),
                  WatchColors.bg.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Desktop: side-by-side 60/40
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(Size screenSize) {
    final isWide = screenSize.width >= 1500;
    final leftFlex = isWide ? 5 : 5;
    final rightFlex = isWide ? 5 : 6;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Padding(
          padding: const EdgeInsets.only(
            top: 60,
            left: 48,
            right: 0,
            bottom: 24,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: info region
              Expanded(
                flex: leftFlex,
                child: SingleChildScrollView(
                  controller: _mainScrollController,
                  physics: const BouncingScrollPhysics(),
                  child: _buildInfoRegion(isDesktop: true),
                ),
              ),
              const SizedBox(width: 32),
              // Right: sources panel (extends to right edge)
              Expanded(
                flex: rightFlex,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: _buildSourcesPanel(isDesktop: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mobile: stacked vertically
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMobileLayout(Size screenSize) {
    final filtered = _filteredSources;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          controller: _mainScrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Top padding ──
            const SliverPadding(padding: EdgeInsets.only(top: 60)),

            // ── Info region (single box) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WatchSpace.lg),
                child: _buildInfoRegion(isDesktop: false),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(top: WatchSpace.lg)),

            // ── Sources header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WatchSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.stream_rounded,
                              color: WatchColors.accent,
                              size: 20,
                            ),
                            SizedBox(width: WatchSpace.xs),
                            Text(
                              'Watch Sources',
                              style: TextStyle(
                                color: WatchColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _isLoadingSources
                              ? 'Searching sources...'
                              : '${filtered.length} source${filtered.length == 1 ? '' : 's'} found',
                          style: const TextStyle(
                            color: WatchColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (_sources.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildTypeChip('all', 'All (${_sources.length})', Icons.apps_rounded, null),
                          _buildTypeChip(
                            'debrid',
                            '⚡ Debrid (${_sources.where((s) => s.isDebrid).length})',
                            Icons.bolt_rounded,
                            const Color(0xFF00E5FF),
                          ),
                          _buildTypeChip(
                            'torrent',
                            '🧲 Torrents (${_sources.where((s) => s.isTorrent).length})',
                            Icons.share_rounded,
                            const Color(0xFF7C5CFF),
                          ),
                          _buildTypeChip(
                            'direct',
                            '🌐 Direct (${_sources.where((s) => s.isHttpDirect).length})',
                            Icons.link_rounded,
                            const Color(0xFF10B981),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildSeederFilterDropdown(),
                          _buildSizeFilterDropdown(),
                          _buildAddonFilterDropdown(),
                          _buildAudioFilterDropdown(),
                        ],
                      ),
                    ],
                    const SizedBox(height: WatchSpace.md),
                  ],
                ),
              ),
            ),

            // ── Sources list (virtualized!) ──
            if (_isLoadingSources && filtered.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: WatchSpace.lg),
                sliver: SliverList.builder(
                  itemCount: 4,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: WatchSpace.xs),
                    child: _buildShimmerCard(),
                  ),
                ),
              )
            else if (!_isLoadingSources && filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WatchSpace.lg),
                  child: _buildEmptyState(),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: WatchSpace.lg),
                sliver: SliverList.builder(
                  itemCount: filtered.length + (_isLoadingSources ? 2 : 0),
                  itemBuilder: (context, index) {
                    if (index >= filtered.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: WatchSpace.xs),
                        child: _buildShimmerCard(),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: WatchSpace.xs),
                      child: WatchSourceCard(
                        source: filtered[index],
                        backdropUrl:
                            widget.detail.background ?? widget.detail.poster,
                        logoUrl: widget.detail.logo,
                        detail: widget.detail,
                        episode: widget.selectedEpisode,
                        initialPosition: widget.initialPosition,
                        failoverCandidates: List.of(_sources),
                        onUserPicked: () {
                          _userPickedSource = true;
                          _resolve.cancelAutoplay();
                        },
                      ),
                    );
                  },
                ),
              ),

            // ── Bottom padding ──
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Info Region
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInfoRegion({required bool isDesktop}) {
    final meta = widget.detail;
    final ep = widget.selectedEpisode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Episode info header (if applicable)
        if (ep != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: WatchColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WatchColors.accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              'S${ep.season ?? '?'}E${ep.episode ?? '?'}',
              style: const TextStyle(
                color: WatchColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: WatchSpace.sm),
        ],

        // Logo or title
        _buildLogoOrTitle(meta, isDesktop),
        const SizedBox(height: WatchSpace.sm),

        // Episode title (if applicable, different from series title)
        if (ep != null && ep.title.isNotEmpty && ep.title != meta.name)
          Padding(
            padding: const EdgeInsets.only(bottom: WatchSpace.sm),
            child: Text(
              ep.title,
              style: TextStyle(
                fontSize: isDesktop ? 20 : 17,
                fontWeight: FontWeight.w600,
                color: WatchColors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
          ),

        // Meta row
        _buildMetaRow(meta),
        const SizedBox(height: WatchSpace.md),

        // Genre pills
        if (meta.genres.isNotEmpty) ...[
          _buildGenrePills(meta.genres),
          const SizedBox(height: WatchSpace.lg),
        ],

        // Synopsis
        if (_getSynopsis() != null) ...[
          _buildSynopsis(_getSynopsis()!),
          const SizedBox(height: WatchSpace.lg),
        ],

        // Director
        if (meta.director.isNotEmpty) ...[
          _buildLabelChips('DIRECTOR', meta.director),
          const SizedBox(height: WatchSpace.md),
        ],

        // Cast
        if (meta.cast.isNotEmpty) ...[
          _buildLabelChips('CAST', meta.cast.take(8).toList()),
          const SizedBox(height: WatchSpace.lg),
        ],

        // Action bar
        _buildActionBar(),
        const SizedBox(height: WatchSpace.lg),
      ],
    );
  }

  String? _getSynopsis() {
    final ep = widget.selectedEpisode;
    if (ep != null && ep.overview != null && ep.overview!.isNotEmpty) {
      return ep.overview;
    }
    return widget.detail.description;
  }

  Widget _buildLogoOrTitle(MovieDetail meta, bool isDesktop) {
    if (meta.logo != null && meta.logo!.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 380 : 260,
          maxHeight: isDesktop ? 120 : 80,
        ),
        child: CachedNetworkImage(
          imageUrl: meta.logo!,
          alignment: Alignment.bottomLeft,
          fit: BoxFit.contain,
          // P12: decode-capped (was full-res).
          memCacheWidth: ImageCaps.kLogo,
          maxWidthDiskCache: ImageCaps.kLogo,
          errorWidget: (_, __, ___) => _buildTextTitle(meta.name, isDesktop),
        ),
      );
    }
    return _buildTextTitle(meta.name, isDesktop);
  }

  Widget _buildTextTitle(String text, bool isDesktop) {
    return Text(
      text,
      style: TextStyle(
        fontSize: isDesktop ? 36 : 28,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.5,
        color: WatchColors.textPrimary,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(MovieDetail meta) {
    final items = <Widget>[];

    if (meta.year != null && meta.year!.isNotEmpty) {
      items.add(
        Text(
          meta.year!,
          style: const TextStyle(
            color: WatchColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (meta.runtime != null && meta.runtime!.isNotEmpty) {
      items.add(
        Text(
          meta.runtime!,
          style: const TextStyle(color: WatchColors.textSecondary, fontSize: 14),
        ),
      );
    }

    if (meta.imdbRating != null && meta.imdbRating!.isNotEmpty) {
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: WatchColors.gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: WatchColors.gold.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: WatchColors.gold, size: 14),
              const SizedBox(width: 3),
              Text(
                meta.imdbRating!,
                style: const TextStyle(
                  color: WatchColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final spaced = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      spaced.add(items[i]);
      if (i < items.length - 1) {
        spaced.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: WatchSpace.xs),
            child: Text(
              '·',
              style: TextStyle(color: WatchColors.textTertiary, fontSize: 16),
            ),
          ),
        );
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: spaced,
    );
  }

  Widget _buildGenrePills(List<String> genres) {
    return Wrap(
      spacing: WatchSpace.xs,
      runSpacing: WatchSpace.xs,
      children: genres
          .map(
            (g) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Text(
                g,
                style: const TextStyle(
                  color: WatchColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  bool _synopsisExpanded = false;

  Widget _buildSynopsis(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedCrossFade(
          firstChild: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WatchColors.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          secondChild: Text(
            text,
            style: const TextStyle(
              color: WatchColors.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          crossFadeState: _synopsisExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
              maxLines: 3,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);

            if (!painter.didExceedMaxLines) return const SizedBox.shrink();

            return GestureDetector(
              onTap: () =>
                  setState(() => _synopsisExpanded = !_synopsisExpanded),
              child: Text(
                _synopsisExpanded ? 'Show less' : 'Read more',
                style: const TextStyle(
                  color: WatchColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLabelChips(String label, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: WatchColors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: WatchSpace.xs),
        Wrap(
          spacing: WatchSpace.xs,
          runSpacing: WatchSpace.xs,
          children: items
              .map(
                (name) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: WatchColors.surfaceLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: WatchColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    final links = widget.detail.links.take(4).toList();

    // Fallback if no links provided by addon
    if (links.isEmpty && widget.detail.id.startsWith('tt')) {
      links.add(
        Link(
          name: 'IMDb',
          category: 'imdb',
          url: 'https://www.imdb.com/title/${widget.detail.id}/',
        ),
      );
    }

    if (links.isEmpty) {
      // Generic fallback
      final query = Uri.encodeComponent(
        '${widget.detail.name} ${widget.detail.year ?? ''}',
      );
      links.add(
        Link(
          name: 'Search',
          category: 'web',
          url: 'https://google.com/search?q=$query',
        ),
      );
    }

    return Row(
      children: links.map((link) {
        IconData icon = Icons.link_rounded;
        final nameLower = link.name.toLowerCase();
        final catLower = link.category.toLowerCase();

        if (nameLower.contains('imdb') || catLower.contains('imdb')) {
          icon = Icons.movie_creation_outlined;
        } else if (nameLower.contains('trailer') || catLower.contains('trailer')) {
          icon = Icons.play_circle_outline;
        } else if (nameLower.contains('wiki') || catLower.contains('wiki')) {
          icon = Icons.article_outlined;
        } else if (nameLower.contains('search') || catLower.contains('search')) {
          icon = Icons.search_rounded;
        }

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: link == links.last ? 0 : WatchSpace.sm),
            child: _buildActionButton(
              icon,
              link.name,
              onTap: () async {
                HapticFeedback.lightImpact();
                final uri = Uri.parse(link.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: WatchColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: WatchColors.textSecondary, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: WatchColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sources Panel
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSourcesPanel({required bool isDesktop}) {
    final filtered = _filteredSources;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stream_rounded, color: WatchColors.accent, size: 20),
                SizedBox(width: WatchSpace.xs),
                Text(
                  'Watch Sources',
                  style: TextStyle(
                    color: WatchColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Text(
              _isLoadingSources
                  ? 'Searching sources...'
                  : '${filtered.length} source${filtered.length == 1 ? '' : 's'} found',
              style: const TextStyle(color: WatchColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Stream Type Filter Bar (All / Debrid / Torrents / Direct HTTP)
        if (_sources.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildTypeChip('all', 'All (${_sources.length})', Icons.apps_rounded, null),
              _buildTypeChip(
                'debrid',
                '⚡ Debrid (${_sources.where((s) => s.isDebrid).length})',
                Icons.bolt_rounded,
                const Color(0xFF00E5FF),
              ),
              _buildTypeChip(
                'torrent',
                '🧲 Torrents (${_sources.where((s) => s.isTorrent).length})',
                Icons.share_rounded,
                const Color(0xFF7C5CFF),
              ),
              _buildTypeChip(
                'direct',
                '🌐 Direct (${_sources.where((s) => s.isHttpDirect).length})',
                Icons.link_rounded,
                const Color(0xFF10B981),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildSeederFilterDropdown(),
              _buildSizeFilterDropdown(),
              _buildAddonFilterDropdown(),
              _buildAudioFilterDropdown(),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Source list
        if (isDesktop)
          Expanded(child: _buildSourcesList(filtered, isDesktop))
        else
          _buildSourcesList(filtered, isDesktop),
      ],
    );
  }

  Widget _buildTypeChip(String typeKey, String label, IconData icon, Color? color) {
    final isSelected = _selectedTypeFilter == typeKey;
    final activeColor = color ?? WatchColors.accent;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: activeColor.withValues(alpha: 0.25),
      backgroundColor: DizzyVoid.surface1,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        fontSize: 11.5,
      ),
      side: BorderSide(
        color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.1),
        width: isSelected ? 1.5 : 1.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedTypeFilter = typeKey;
          });
        }
      },
    );
  }

  Widget _buildSourcesList(List<StreamSource> sources, bool isDesktop) {
    if (_isLoadingSources && sources.isEmpty) {
      return _buildShimmerList();
    }

    if (!_isLoadingSources && sources.isEmpty) {
      return _buildEmptyState();
    }

    final list = ListView.separated(
      controller: isDesktop ? _sourcesScrollController : null,
      shrinkWrap: !isDesktop,
      physics: isDesktop
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: sources.length + (_isLoadingSources ? 2 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: WatchSpace.xs),
      itemBuilder: (context, index) {
        if (index >= sources.length) {
          return _buildShimmerCard();
        }
        return WatchSourceCard(
          source: sources[index],
          backdropUrl: widget.detail.background ?? widget.detail.poster,
          logoUrl: widget.detail.logo,
          detail: widget.detail,
          episode: widget.selectedEpisode,
          initialPosition: widget.initialPosition,
          failoverCandidates: List.of(_sources),
          onUserPicked: () {
            _userPickedSource = true;
            _resolve.cancelAutoplay();
          },
        );
      },
    );

    return list;
  }

  Widget _buildSeederFilterDropdown() {
    final currentText = _getSeederFilterLabel(_selectedSeederFilter);

    return Builder(
      builder: (buttonContext) {
        return GestureDetector(
          onTap: () => _isDesktop()
              ? _showSeederGlassDropdown(buttonContext)
              : _showSeederBottomSheet(),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menuButton,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _selectedSeederFilter != 'all'
                        ? const Color(0xFF10B981).withValues(alpha: 0.6)
                        : const Color(0x26FFFFFF),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      color: _selectedSeederFilter != 'all'
                          ? const Color(0xFF10B981)
                          : Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentText,
                      style: TextStyle(
                        color: _selectedSeederFilter != 'all'
                            ? const Color(0xFF10B981)
                            : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSeederGlassDropdown(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, (openAbove ? 10 : -10) * (1 - value)),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: PerformanceLiquidLens(
                      style: PerformanceGlassStyles.menu,
                      child: Container(
                        width: dialogWidth,
                        constraints: BoxConstraints(maxHeight: maxMenuHeight),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x26FFFFFF)),
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSeederDropdownItem('All Seeds', 'all'),
                              const SizedBox(height: 4),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 4),
                              _buildSeederDropdownItem('Most Seeds (High to Low)', 'most'),
                              _buildSeederDropdownItem('50+ Seeds', '50+'),
                              _buildSeederDropdownItem('20+ Seeds', '20+'),
                              _buildSeederDropdownItem('5+ Seeds', '5+'),
                              _buildSeederDropdownItem('Active Seeds (>0)', '1+'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSeederDropdownItem(String title, String value) {
    final isSelected = _selectedSeederFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedSeederFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeFilterDropdown() {
    final currentText = _getSizeFilterLabel(_selectedSizeFilter);

    return Builder(
      builder: (buttonContext) {
        return GestureDetector(
          onTap: () => _isDesktop()
              ? _showSizeGlassDropdown(buttonContext)
              : _showSizeBottomSheet(),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menuButton,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x26FFFFFF)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.data_usage_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSizeGlassDropdown(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, (openAbove ? 10 : -10) * (1 - value)),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: PerformanceLiquidLens(
                      style: PerformanceGlassStyles.menu,
                      child: Container(
                        width: dialogWidth,
                        constraints: BoxConstraints(maxHeight: maxMenuHeight),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x26FFFFFF)),
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSizeDropdownItem('All Sizes', null),
                              const SizedBox(height: 4),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 4),
                              _buildSizeDropdownItem('< 1 GB', '<1gb'),
                              _buildSizeDropdownItem('1 GB – 5 GB', '1-5gb'),
                              _buildSizeDropdownItem('5 GB – 15 GB', '5-15gb'),
                              _buildSizeDropdownItem('15 GB – 30 GB', '15-30gb'),
                              _buildSizeDropdownItem('> 30 GB', '>30gb'),
                              const SizedBox(height: 4),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 4),
                              _buildSizeDropdownItem('Largest First', 'largest'),
                              _buildSizeDropdownItem('Smallest First', 'smallest'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSizeDropdownItem(String title, String? value) {
    final isSelected = _selectedSizeFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedSizeFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAddonFilterDropdown() {
    final addons = _sources.map((e) => e.addonName).toSet().toList();
    if (addons.isEmpty) return const SizedBox.shrink();
    final currentText = _selectedAddonFilter ?? 'All Sources';

    return Builder(
      builder: (buttonContext) {
        return GestureDetector(
          onTap: () => _isDesktop()
              ? _showGlassDropdown(buttonContext, addons)
              : _showAddonBottomSheet(addons),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menuButton,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x26FFFFFF)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGlassDropdown(BuildContext buttonContext, List<String> addons) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(
                        0,
                        (openAbove ? 10 : -10) * (1 - value),
                      ),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: PerformanceLiquidLens(
                      style: PerformanceGlassStyles.menu,
                      child: Container(
                        width: dialogWidth,
                        constraints: BoxConstraints(maxHeight: maxMenuHeight),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x26FFFFFF)),
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDropdownItem('All Sources', null),
                              const SizedBox(height: 4),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 4),
                              ...addons.map((a) => _buildDropdownItem(a, a)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDropdownItem(String title, String? value) {
    final isSelected = _selectedAddonFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedAddonFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  String _getAudioFilterLabel(String key) {
    switch (key) {
      case 'multi':
        return '🌐 Multi-Audio';
      case 'english':
        return '🇺🇸 English / Orig';
      case 'hindi':
        return '🇮🇳 Hindi / Indian';
      case 'german':
        return '🇩🇪 German';
      case 'french':
        return '🇫🇷 French';
      case 'spanish':
        return '🇪🇸 Spanish';
      case 'russian':
        return '🇷🇺 Russian';
      case 'japanese':
        return '🇯🇵 Japanese';
      case 'italian':
        return '🇮🇹 Italian';
      default:
        return 'All Audio';
    }
  }

  Widget _buildAudioFilterDropdown() {
    final currentText = _getAudioFilterLabel(_selectedAudioFilter);
    final isActive = _selectedAudioFilter != 'all';

    return Builder(
      builder: (buttonContext) {
        return GestureDetector(
          onTap: () => _isDesktop()
              ? _showAudioGlassDropdown(buttonContext)
              : _showAudioBottomSheet(),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menuButton,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFFB197FC).withValues(alpha: 0.6)
                        : const Color(0x26FFFFFF),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.audiotrack_rounded,
                      color: isActive ? const Color(0xFFB197FC) : Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentText,
                      style: TextStyle(
                        color: isActive ? const Color(0xFFB197FC) : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAudioGlassDropdown(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: PerformanceLiquidLens(
                    style: PerformanceGlassStyles.menu,
                    child: Container(
                      width: dialogWidth,
                      constraints: BoxConstraints(maxHeight: maxMenuHeight),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x26FFFFFF)),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAudioDropdownItem('All Audio', 'all'),
                            const SizedBox(height: 4),
                            Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            const SizedBox(height: 4),
                            _buildAudioDropdownItem('🌐 Multi-Audio', 'multi'),
                            _buildAudioDropdownItem('🇺🇸 English / Orig', 'english'),
                            _buildAudioDropdownItem('🇮🇳 Hindi / Indian', 'hindi'),
                            _buildAudioDropdownItem('🇩🇪 German', 'german'),
                            _buildAudioDropdownItem('🇫🇷 French', 'french'),
                            _buildAudioDropdownItem('🇪🇸 Spanish', 'spanish'),
                            _buildAudioDropdownItem('🇷🇺 Russian', 'russian'),
                            _buildAudioDropdownItem('🇯🇵 Japanese', 'japanese'),
                            _buildAudioDropdownItem('🇮🇹 Italian', 'italian'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAudioDropdownItem(String title, String value) {
    final isSelected = _selectedAudioFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedAudioFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFFB197FC), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassBottomSheetContainer({
    required BuildContext context,
    required Widget header,
    required Widget content,
  }) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: DizzyColors.surface.withValues(alpha: 0.96),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  header,
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 8),
                  content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheetItem({
    required String title,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : Colors.transparent,
          border: isSelected
              ? Border.all(color: activeColor.withValues(alpha: 0.4))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: activeColor, size: 20),
          ],
        ),
      ),
    );
  }

  void _showAudioBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFB197FC).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.audiotrack_rounded,
                  color: Color(0xFFB197FC),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Audio & Dub Language',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Audio',
                    isSelected: _selectedAudioFilter == 'all',
                    activeColor: const Color(0xFFB197FC),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'all');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🌐 Multi-Audio',
                    isSelected: _selectedAudioFilter == 'multi',
                    activeColor: const Color(0xFFB197FC),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'multi');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇺🇸 English / Original',
                    isSelected: _selectedAudioFilter == 'english',
                    activeColor: const Color(0xFFB197FC),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'english');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇮🇳 Hindi / Indian',
                    isSelected: _selectedAudioFilter == 'hindi',
                    activeColor: const Color(0xFFFF922B),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'hindi');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇩🇪 German',
                    isSelected: _selectedAudioFilter == 'german',
                    activeColor: const Color(0xFFFFD43B),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'german');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇫🇷 French',
                    isSelected: _selectedAudioFilter == 'french',
                    activeColor: const Color(0xFF4DABF7),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'french');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇪🇸 Spanish',
                    isSelected: _selectedAudioFilter == 'spanish',
                    activeColor: const Color(0xFFFAB005),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'spanish');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇷🇺 Russian',
                    isSelected: _selectedAudioFilter == 'russian',
                    activeColor: const Color(0xFF22B8CF),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'russian');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇯🇵 Japanese',
                    isSelected: _selectedAudioFilter == 'japanese',
                    activeColor: const Color(0xFFFF8787),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'japanese');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇮🇹 Italian',
                    isSelected: _selectedAudioFilter == 'italian',
                    activeColor: const Color(0xFF69DB7C),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'italian');
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSeederBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Seeders Filter',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Seeds',
                    isSelected: _selectedSeederFilter == 'all',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = 'all');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Most Seeds (High to Low)',
                    isSelected: _selectedSeederFilter == 'most',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = 'most');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '50+ Seeds',
                    isSelected: _selectedSeederFilter == '50+',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = '50+');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '20+ Seeds',
                    isSelected: _selectedSeederFilter == '20+',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = '20+');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '5+ Seeds',
                    isSelected: _selectedSeederFilter == '5+',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = '5+');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Active Seeds (>0)',
                    isSelected: _selectedSeederFilter == '1+',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = '1+');
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSizeBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder_open_rounded,
                  color: Color(0xFF3B82F6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'File Size Filter',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Sizes',
                    isSelected: _selectedSizeFilter == null,
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Largest First',
                    isSelected: _selectedSizeFilter == 'largest',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = 'largest');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Smallest First',
                    isSelected: _selectedSizeFilter == 'smallest',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = 'smallest');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '< 1 GB',
                    isSelected: _selectedSizeFilter == '<1gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '<1gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '1 - 5 GB',
                    isSelected: _selectedSizeFilter == '1-5gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '1-5gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '5 - 15 GB',
                    isSelected: _selectedSizeFilter == '5-15gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '5-15gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '15 - 30 GB',
                    isSelected: _selectedSizeFilter == '15-30gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '15-30gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '> 30 GB',
                    isSelected: _selectedSizeFilter == '>30gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '>30gb');
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddonBottomSheet(List<String> addons) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.extension_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Source Provider',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Sources',
                    isSelected: _selectedAddonFilter == null,
                    activeColor: Colors.white,
                    onTap: () {
                      setState(() => _selectedAddonFilter = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  for (final addon in addons)
                    _buildBottomSheetItem(
                      title: addon,
                      isSelected: _selectedAddonFilter == addon,
                      activeColor: Colors.white,
                      onTap: () {
                        setState(() => _selectedAddonFilter = addon);
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const WatchEmptySources();
  }

  Widget _buildShimmerList() {
    return Column(
      children: List.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: WatchSpace.xs),
          child: _buildShimmerCard(),
        ),
      ),
    );
  }

  Widget _buildShimmerCard() {
    return const RepaintBoundary(child: WatchShimmerCard());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Back Button
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBackButton() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: WatchColors.bg.withValues(alpha: 0.7),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: WatchColors.textPrimary,
        ),
        onPressed: () => Navigator.pop(context),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
