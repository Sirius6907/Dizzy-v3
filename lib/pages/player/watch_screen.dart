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
part 'watch_screen_part_layout.dart';
part 'watch_screen_part_sources.dart';
part 'watch_screen_part_sheets.dart';

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
  bool _synopsisExpanded = false;

}
