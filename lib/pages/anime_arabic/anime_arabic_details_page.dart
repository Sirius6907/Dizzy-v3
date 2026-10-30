import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/prism_tokens.dart';

import '../../services/anime_arabic/anime_arabic_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/slider_arrow.dart';
import 'anime_arabic_stream_sheet.dart';

class _Space {
  static const md = 16.0;
  static const xl = 32.0;
}

class _Palette {
  static Color get bg =>
      AppThemeService.currentPalette.value.scaffoldBackgroundColor;
  static Color get surface =>
      AppThemeService.currentPalette.value.cardBackgroundColor;
  static Color get accent => AppThemeService.currentPalette.value.primaryColor;
  static const gold = DizzyGlow.gold;

  static bool get isLight => AppThemeService.currentPalette.value.isLight;

  /// Content sits on an opaque clay sheet, so readable text is ink in light
  /// mode (white stays for dark clay).
  static Color get ink => isLight ? PrismLight.ink : Colors.white;
  static Color get inkSoft => isLight ? PrismLight.inkSoft : Colors.white70;
  static Color get muted => isLight ? PrismLight.inkSoft : Colors.white54;
  static Color get faint => isLight ? PrismLight.inkFaint : Colors.white38;

  /// Raised tile / chip fill.
  static Color get panel => isLight ? PrismLight.raisedTop : PrismDark.raised;
  static Color get border =>
      isLight ? PrismLight.borderSubtle : PrismDark.borderSubtle;

  /// Carved input / sunken fill.
  static Color get field =>
      isLight ? PrismLight.raisedBottom : PrismDark.sunken;

  static Color get star => isLight ? PrismAccent.starTextLight : gold;

  /// Accent for *text* on clay; the raw accent is below AA at small sizes.
  static Color get accentText => PrismAccent.text(isLight);

  /// Selected-tile wash; kept faint in light so accent text stays readable.
  static Color get accentTint =>
      accent.withValues(alpha: isLight ? 0.12 : 0.25);
}

class AnimeArabicDetailsPage extends StatefulWidget {
  final ArabicAnimeCard anime;
  final int? initialEpisodeNumber;

  const AnimeArabicDetailsPage({
    super.key,
    required this.anime,
    this.initialEpisodeNumber,
  });

  @override
  State<AnimeArabicDetailsPage> createState() => _AnimeArabicDetailsPageState();
}

class _AnimeArabicDetailsPageState extends State<AnimeArabicDetailsPage>
    with SingleTickerProviderStateMixin {
  final AnimeArabicService _service = AnimeArabicService.instance;

  ArabicAnimeDetails? _details;
  bool _loading = true;
  String? _error;
  bool _isSynopsisExpanded = false;

  int _selectedEpisodeBatch = 0; // 50 episodes per chunk
  int? _highlightedEpisode;
  static const int _chunkSize = 50;

  final TextEditingController _jumpEpController = TextEditingController();

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final ScrollController _recsScrollController = ScrollController();
  bool _canScrollRecsLeft = false;
  bool _canScrollRecsRight = true;
  bool _isHoveringRecs = false;

  @override
  void initState() {
    super.initState();
    _highlightedEpisode = widget.initialEpisodeNumber;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _animController.forward();
    _recsScrollController.addListener(_updateRecsScrollButtons);
    _loadDetails();
  }

  @override
  void dispose() {
    _animController.dispose();
    _jumpEpController.dispose();
    _recsScrollController.removeListener(_updateRecsScrollButtons);
    _recsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _service.getDetails(widget.anime.slug);
      if (mounted) {
        final targetEp = widget.initialEpisodeNumber ?? _highlightedEpisode;
        int batch = 0;
        if (targetEp != null && res.episodes.isNotEmpty) {
          final idx = res.episodes.indexWhere((e) => e.number == targetEp);
          if (idx >= 0) {
            batch = (idx / _chunkSize).floor();
          }
        }
        setState(() {
          _details = res;
          _selectedEpisodeBatch = batch;
          _highlightedEpisode = targetEp;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load anime details: $e';
        });
      }
    }
  }

  void _updateRecsScrollButtons() {
    if (!_recsScrollController.hasClients) return;
    final max = _recsScrollController.position.maxScrollExtent;
    final current = _recsScrollController.offset;
    final canLeft = current > 10;
    final canRight = current < max - 10;

    if (canLeft != _canScrollRecsLeft || canRight != _canScrollRecsRight) {
      setState(() {
        _canScrollRecsLeft = canLeft;
        _canScrollRecsRight = canRight;
      });
    }
  }

  void _scrollRecs(bool right) {
    if (!_recsScrollController.hasClients) return;
    final current = _recsScrollController.offset;
    final target = right ? current + 450 : current - 450;
    _recsScrollController.animateTo(
      target.clamp(0.0, _recsScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _playEpisode(ArabicEpisode episode) {
    if (_details == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AnimeArabicStreamSheet(
        details: _details!,
        episode: episode,
        autoPlay: true,
      ),
    );
  }

  void _jumpToEpisode(String value) {
    final ep = int.tryParse(value.trim());
    if (ep == null || ep <= 0 || _details == null) return;

    final totalEps = _details!.episodes.length;
    final targetEp = ep.clamp(1, totalEps > 0 ? totalEps : 1);
    final targetBatch = ((targetEp - 1) / _chunkSize).floor();

    setState(() {
      _selectedEpisodeBatch = targetBatch;
      _highlightedEpisode = targetEp;
    });

    _jumpEpController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    final isDesktop = screenWidth > 900;
    final isMobile = screenWidth < 600;

    final backdropUrl = _details?.displayBanner ?? widget.anime.cover ?? '';
    final coverUrl = _details?.displayCover ?? widget.anime.cover ?? '';
    final title = _details?.title ?? widget.anime.title;

    // Artwork is clipped to a hero band; every section below it sits on an
    // opaque clay sheet so ink stays legible in both themes.
    final heroHeight = (screenSize.height * (isDesktop ? 0.46 : 0.4)).clamp(
      300.0,
      520.0,
    );
    final overlap = isDesktop ? 110.0 : 64.0;
    final hPad = isDesktop ? 60.0 : (isMobile ? 16.0 : 32.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedAmbientBackground(
        child: Stack(
          children: [
            // 1. Ambient artwork, clipped to the hero band
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdropUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: backdropUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      memCacheWidth: 1280,
                      maxWidthDiskCache: 1280,
                    ),
                  // Cinematic blur & dark gradients
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(color: Colors.transparent),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _Palette.bg.withValues(alpha: 0.3),
                          _Palette.bg.withValues(alpha: 0.75),
                          _Palette.bg,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.2,
                        colors: [
                          _Palette.accent.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Main Scrollable Content
            SafeArea(
              bottom: false,
              child: _loading && _details == null
                  ? Center(
                      child: CircularProgressIndicator(color: _Palette.accent),
                    )
                  : _error != null && _details == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.redAccent,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: _Palette.inkSoft,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _Palette.accent,
                              foregroundColor: PrismAccent.onAccent,
                            ),
                            onPressed: _loadDetails,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: CustomScrollView(
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            // Space above the sheet; the artwork band shows
                            // through here and under the floating top bar.
                            SliverToBoxAdapter(
                              child: SizedBox(height: heroHeight - overlap),
                            ),

                            // Opaque clay sheet: readable content lives
                            // here, never directly on the artwork.
                            SliverToBoxAdapter(
                              child: Container(
                                constraints: BoxConstraints(
                                  minHeight:
                                      screenSize.height -
                                      (heroHeight - overlap),
                                ),
                                padding: EdgeInsets.only(
                                  top: _Space.md,
                                  bottom:
                                      24.0 +
                                      MediaQuery.paddingOf(context).bottom,
                                ),
                                decoration: BoxDecoration(
                                  color: _Palette.bg,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(PrismRadius.xl),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.24,
                                      ),
                                      blurRadius: 28,
                                      offset: const Offset(0, -10),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Main Hero Info Section
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: hPad,
                                      ),
                                      child: isMobile
                                          ? _buildMobileHero(coverUrl, title)
                                          : _buildDesktopHero(coverUrl, title),
                                    ),

                                    const SizedBox(height: _Space.xl),

                                    // Episodes Section
                                    if (_details != null &&
                                        _details!.episodes.isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: hPad,
                                        ),
                                        child: _buildEpisodesSection(),
                                      ),

                                    const SizedBox(height: _Space.xl),

                                    // Related Anime Rail
                                    if (_details != null &&
                                        _details!.related.isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(left: hPad),
                                        child: _buildRelatedSection(),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // 3. Floating Glass Back Button & Title Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top + 8,
                      bottom: 12,
                      left: 20,
                      right: 20,
                    ),
                    decoration: BoxDecoration(
                      // Nearly opaque in light so the bar reads as clay over
                      // the artwork instead of washing the title out.
                      color: _Palette.bg.withValues(
                        alpha: _Palette.isLight ? 0.92 : 0.65,
                      ),
                      border: Border(
                        bottom: BorderSide(color: _Palette.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'رجوع',
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: _Palette.ink,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _Palette.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
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
      ),
    );
  }

  Widget _buildDesktopHero(String coverUrl, String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPoster(coverUrl, 230, 335),
        const SizedBox(width: 36),
        Expanded(child: _buildMetaDetails(title)),
      ],
    );
  }

  Widget _buildMobileHero(String coverUrl, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(child: _buildPoster(coverUrl, 165, 245)),
        const SizedBox(height: 20),
        _buildMetaDetails(title),
      ],
    );
  }

  Widget _buildPoster(String coverUrl, double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _Palette.accent.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: coverUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                memCacheWidth: 500,
                memCacheHeight: 750,
                maxWidthDiskCache: 500,
                errorWidget: (_, __, ___) => Container(
                  color: _Palette.surface,
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: _Palette.faint,
                    size: 40,
                  ),
                ),
              )
            : Container(color: _Palette.surface),
      ),
    );
  }

  Widget _buildMetaDetails(String title) {
    final status = _details?.status ?? widget.anime.tag ?? 'يعرض الآن';
    final rating = _details?.rating ?? widget.anime.rating;
    final year = _details?.year;
    final studio = _details?.studio;
    final genres = _details?.genres ?? const [];
    final description = _details?.description ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _Palette.ink,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),

        // Badges Row
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (rating != null && rating.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _Palette.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _Palette.gold.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: _Palette.star, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      rating,
                      style: TextStyle(
                        color: _Palette.star,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            if (year != null && year.isNotEmpty)
              _buildPill(year, _Palette.panel, _Palette.inkSoft),
            _buildPill(status, _Palette.accentTint, _Palette.accentText),
            if (studio != null && studio.isNotEmpty)
              _buildPill(studio, _Palette.field, _Palette.inkSoft),
          ],
        ),

        const SizedBox(height: 14),

        // Genres
        if (genres.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: genres.map((g) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _Palette.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _Palette.border),
                ),
                child: Text(
                  g,
                  style: TextStyle(
                    color: _Palette.inkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 18),

        // Action Button (Watch highlighted/latest/first ep)
        if (_details != null && _details!.episodes.isNotEmpty)
          Builder(
            builder: (_) {
              final targetEpNum =
                  _highlightedEpisode ?? _details!.episodes.first.number;
              final targetEp = _details!.episodes.firstWhere(
                (e) => e.number == targetEpNum,
                orElse: () => _details!.episodes.first,
              );
              return ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Palette.accent,
                  foregroundColor: PrismAccent.onAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 8,
                  shadowColor: _Palette.accent.withValues(alpha: 0.5),
                ),
                onPressed: () => _playEpisode(targetEp),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  'مشاهدة الحلقة $targetEpNum',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              );
            },
          ),

        const SizedBox(height: 18),

        // Synopsis
        if (description.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                maxLines: _isSynopsisExpanded ? null : 3,
                overflow: _isSynopsisExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  color: _Palette.inkSoft,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (description.length > 140)
                GestureDetector(
                  onTap: () => setState(
                    () => _isSynopsisExpanded = !_isSynopsisExpanded,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _isSynopsisExpanded ? 'عرض أقل' : 'عرض المزيد',
                      style: TextStyle(
                        color: _Palette.accentText,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildPill(String text, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildEpisodesSection() {
    final episodes = _details!.episodes;
    final totalEpisodes = episodes.length;
    final totalBatches = (totalEpisodes / _chunkSize).ceil();

    final startIndex = _selectedEpisodeBatch * _chunkSize;
    final endIndex = (startIndex + _chunkSize).clamp(0, totalEpisodes);
    final currentBatchEpisodes = episodes.sublist(startIndex, endIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Icon(Icons.video_library_rounded, color: _Palette.accent, size: 22),
            const SizedBox(width: 10),
            Text(
              'الحلقات ($totalEpisodes)',
              style: TextStyle(
                color: _Palette.ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),

            // Jump to Episode field
            if (totalEpisodes > 1)
              SizedBox(
                width: 110,
                height: 36,
                child: TextField(
                  controller: _jumpEpController,
                  keyboardType: TextInputType.number,
                  onSubmitted: _jumpToEpisode,
                  style: TextStyle(color: _Palette.ink, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'اذهب لرقم...',
                    hintStyle: TextStyle(color: _Palette.muted, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                    filled: true,
                    fillColor: _Palette.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _Palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _Palette.accent),
                    ),
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 16),

        // Batches tabs if > 50 episodes
        if (totalBatches > 1)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: totalBatches,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final batchStart = index * _chunkSize + 1;
                final batchEnd = ((index + 1) * _chunkSize).clamp(
                  1,
                  totalEpisodes,
                );
                final isSelected = index == _selectedEpisodeBatch;

                return InkWell(
                  onTap: () => setState(() {
                    _selectedEpisodeBatch = index;
                    _highlightedEpisode = null;
                  }),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? _Palette.accentTint : _Palette.panel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? _Palette.accent : _Palette.border,
                      ),
                    ),
                    child: Text(
                      '$batchStart - $batchEnd',
                      style: TextStyle(
                        color: isSelected
                            ? _Palette.accentText
                            : _Palette.inkSoft,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // Episode Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            int crossAxisCount = 2;
            if (w > 1200) {
              crossAxisCount = 6;
            } else if (w > 900) {
              crossAxisCount = 5;
            } else if (w > 650) {
              crossAxisCount = 4;
            } else if (w > 450) {
              crossAxisCount = 3;
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
              itemCount: currentBatchEpisodes.length,
              itemBuilder: (context, index) {
                final ep = currentBatchEpisodes[index];
                final isHighlighted = ep.number == _highlightedEpisode;
                return _buildEpisodeCard(ep, isHighlighted);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildEpisodeCard(ArabicEpisode episode, bool isHighlighted) {
    final thumb =
        episode.thumb ?? _details?.displayBanner ?? widget.anime.cover ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _playEpisode(episode),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: _Palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted ? _Palette.accent : _Palette.border,
              width: isHighlighted ? 2 : 1,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: _Palette.accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  memCacheWidth: 500,
                  memCacheHeight: 750,
                  maxWidthDiskCache: 500,
                  errorWidget: (_, __, ___) =>
                      Container(color: _Palette.surface),
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _Palette.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'EP ${episode.number}',
                        style: const TextStyle(
                          color: PrismAccent.onAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        episode.title.isNotEmpty
                            ? episode.title
                            : 'الحلقة ${episode.number}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelatedSection() {
    final related = _details!.related;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.recommend_rounded, color: _Palette.accent, size: 22),
              const SizedBox(width: 10),
              Text(
                'أنميات ذات صلة',
                style: TextStyle(
                  color: _Palette.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringRecs = true),
            onExit: (_) => setState(() => _isHoveringRecs = false),
            child: SizedBox(
              height: 235,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ListView.separated(
                    clipBehavior: Clip.none,
                    controller: _recsScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: related.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final item = related[index];
                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            CinematicSlideRoute(
                              page: AnimeArabicDetailsPage(anime: item),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 130,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  width: 130,
                                  height: 180,
                                  color: _Palette.surface,
                                  child:
                                      (item.cover != null &&
                                          item.cover!.isNotEmpty)
                                      ? CachedNetworkImage(
                                          imageUrl: item.cover!,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 260,
                                          maxWidthDiskCache: 260,
                                          errorWidget: (_, __, ___) => Icon(
                                            Icons.movie_rounded,
                                            color: _Palette.faint,
                                          ),
                                        )
                                      : Icon(
                                          Icons.movie_rounded,
                                          color: _Palette.faint,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _Palette.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Desktop Floating Scroll Arrows (Matching Home Page & Anime Slider)
                  if (isDesktop) ...[
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      left: _canScrollRecsLeft && _isHoveringRecs ? 10 : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SliderArrow(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => _scrollRecs(false),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      right: _canScrollRecsRight && _isHoveringRecs ? 10 : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SliderArrow(
                          icon: Icons.arrow_forward_ios_rounded,
                          onTap: () => _scrollRecs(true),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
