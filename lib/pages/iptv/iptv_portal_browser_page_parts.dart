part of 'iptv_portal_browser_page.dart';

class _CategoryListRow extends StatefulWidget {
  final IptvCategory category;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryListRow({
    required this.category,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_CategoryListRow> createState() => _CategoryListRowState();
}

class _CategoryListRowState extends State<_CategoryListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white70;
    final inkFaint = isLight ? PrismLight.inkFaint : Colors.white38;
    final hoverFill = isLight ? PrismLight.raisedBottom : DizzyVoid.surface1;
    final isFavCategory =
        widget.category.id == _IptvPortalBrowserPageState.favoritesCategoryId;
    final showCount = IptvSettings.showCategoryCount.value;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? (isFavCategory
                        ? DizzyGlow.gold.withValues(alpha: 0.15)
                        : palette.primaryColor.withValues(alpha: 0.15))
                  : (_hovered ? hoverFill : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isSelected
                    ? (isFavCategory
                          ? DizzyGlow.gold.withValues(alpha: 0.6)
                          : palette.primaryColor.withValues(alpha: 0.6))
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 16,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? (isFavCategory
                              ? DizzyGlow.gold
                              : palette.primaryColor)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                if (isFavCategory) ...[
                  const Icon(
                    Icons.star_rounded,
                    color: DizzyGlow.gold,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    widget.category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isSelected
                          ? (isFavCategory
                                ? (isLight
                                      ? PrismAccent.starTextLight
                                      : const Color(0xFFFFD54F))
                                : ink)
                          : (_hovered
                                ? ink
                                : (isFavCategory
                                      ? (isLight
                                            ? PrismAccent.starTextLight
                                            : DizzyGlow.gold)
                                      : inkSoft)),
                      fontSize: 12.5,
                      fontWeight: widget.isSelected
                          ? FontWeight.w800
                          : (isFavCategory ? FontWeight.w700 : FontWeight.w600),
                    ),
                  ),
                ),
                if (showCount) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? (isFavCategory
                                ? DizzyGlow.gold.withValues(alpha: 0.3)
                                : palette.primaryColor.withValues(alpha: 0.3))
                          : (isFavCategory
                                ? DizzyGlow.gold.withValues(alpha: 0.12)
                                : (isLight
                                      ? PrismLight.raisedBottom
                                      : Colors.white.withValues(alpha: 0.06))),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: TextStyle(
                        color: isFavCategory
                            ? (isLight
                                  ? PrismAccent.starTextLight
                                  : DizzyGlow.gold)
                            : (widget.isSelected
                                  ? PrismAccent.text(isLight)
                                  : inkFaint),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelListRow extends StatefulWidget {
  final int index;
  final IptvStream stream;
  final VerifiedPortal? portal;
  final bool isAlive;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _LiveChannelListRow({
    super.key,
    required this.index,
    required this.stream,
    this.portal,
    required this.isAlive,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_LiveChannelListRow> createState() => _LiveChannelListRowState();
}

class _LiveChannelListRowState extends State<_LiveChannelListRow> {
  bool _hovered = false;
  List<EpgEntry>? _cachedEpg;

  @override
  void initState() {
    super.initState();
    _cachedEpg =
        _IptvPortalBrowserPageState._sharedEpgCache[widget.stream.streamId];
  }

  void _loadEpg() async {
    if (!IptvSettings.showEpgSnippet.value) return;
    if (_cachedEpg != null ||
        widget.portal == null ||
        widget.stream.streamId.isEmpty) {
      return;
    }
    try {
      final entries = await IptvClient.shortEpg(
        widget.portal!.portal,
        widget.stream.streamId,
        limit: 2,
      );
      if (mounted && entries.isNotEmpty) {
        _IptvPortalBrowserPageState._sharedEpgCache[widget.stream.streamId] =
            entries;
        setState(() => _cachedEpg = entries);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final s = widget.stream;
    final indexFormatted = widget.index.toString().padLeft(3, '0');
    final currentEpg = _cachedEpg?.isNotEmpty == true
        ? _cachedEpg!.first
        : null;
    final nextEpg = _cachedEpg != null && _cachedEpg!.length > 1
        ? _cachedEpg![1]
        : null;
    final screenW = MediaQuery.sizeOf(context).width;
    final isVerySmall = screenW < 440;
    final showLogo = IptvSettings.showStreamLogos.value;
    final showEpg = IptvSettings.showEpgSnippet.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white70;
    final inkFaint = isLight ? PrismLight.inkFaint : Colors.white38;
    final panel = isLight ? PrismLight.raisedTop : DizzyVoid.voidB;
    final hoverFill = isLight ? PrismLight.raisedBottom : DizzyVoid.surface1;
    final well = isLight ? PrismLight.raisedBottom : DizzyVoid.voidB;
    final hairline = isLight ? PrismLight.borderSubtle : DizzyVoid.surface2;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovered = true);
          _loadEpg();
        },
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(
              horizontal: isVerySmall ? 8 : 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: _hovered ? hoverFill : panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovered
                    ? palette.primaryColor.withValues(alpha: 0.7)
                    : hairline,
                width: _hovered ? 1.4 : 1.0,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: palette.primaryColor.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Index
                if (!isVerySmall) ...[
                  SizedBox(
                    width: 30,
                    child: Text(
                      indexFormatted,
                      style: TextStyle(
                        color: inkFaint,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // ── CHANNEL LOGO BAY ──
                if (showLogo) ...[
                  Container(
                    width: isVerySmall ? 52 : 64,
                    height: isVerySmall ? 40 : 46,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: well,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: hairline),
                    ),
                    child: s.icon.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: CachedNetworkImage(
                              imageUrl: s.icon,
                              fit: BoxFit.contain,
                              memCacheWidth: 128,
                              errorWidget: (_, _, _) => Icon(
                                Icons.live_tv_rounded,
                                color: inkFaint,
                                size: 20,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.live_tv_rounded,
                            color: inkFaint,
                            size: 20,
                          ),
                  ),
                  SizedBox(width: isVerySmall ? 8 : 12),
                ],

                // Channel Title & EPG Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (widget.isAlive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.greenAccent.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fiber_manual_record_rounded,
                                    color: Colors.greenAccent,
                                    size: 7,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      if (showEpg) ...[
                        const SizedBox(height: 2),
                        if (currentEpg != null) ...[
                          Text(
                            'NOW: ${currentEpg.title}${nextEpg != null ? "  |  NEXT: ${nextEpg.title}" : ""}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: inkSoft, fontSize: 11),
                          ),
                        ] else ...[
                          Text(
                            'Live Stream Feed',
                            style: TextStyle(color: inkFaint, fontSize: 11),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Format Tag
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: well,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: hairline),
                  ),
                  child: Text(
                    s.containerExt.toUpperCase(),
                    style: TextStyle(
                      color: inkSoft,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Favorite Button
                IconButton(
                  icon: Icon(
                    widget.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: widget.isFavorite
                        ? (isLight ? PrismAccent.starTextLight : DizzyGlow.gold)
                        : inkFaint,
                    size: 21,
                  ),
                  tooltip: widget.isFavorite
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                  onPressed: widget.onToggleFavorite,
                ),

                const SizedBox(width: 4),

                // Play Icon Button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _hovered ? palette.primaryColor : well,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: _hovered ? PrismAccent.onAccent : ink,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelGridCard extends StatefulWidget {
  final int index;
  final IptvStream stream;
  final VerifiedPortal? portal;
  final bool isAlive;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _LiveChannelGridCard({
    super.key,
    required this.index,
    required this.stream,
    this.portal,
    required this.isAlive,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_LiveChannelGridCard> createState() => _LiveChannelGridCardState();
}

class _LiveChannelGridCardState extends State<_LiveChannelGridCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final s = widget.stream;
    final showLogo = IptvSettings.showStreamLogos.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white70;
    final inkFaint = isLight ? PrismLight.inkFaint : Colors.white38;
    final panel = isLight ? PrismLight.raisedTop : DizzyVoid.voidB;
    final hoverFill = isLight ? PrismLight.raisedBottom : DizzyVoid.surface1;
    final well = isLight ? PrismLight.raisedBottom : DizzyVoid.voidB;
    final hairline = isLight ? PrismLight.borderSubtle : DizzyVoid.surface2;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _hovered ? hoverFill : panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hovered
                    ? palette.primaryColor.withValues(alpha: 0.8)
                    : hairline,
                width: _hovered ? 1.5 : 1.0,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: palette.primaryColor.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: logo/index + live badge + star
                Row(
                  children: [
                    if (showLogo && s.icon.isNotEmpty)
                      Container(
                        width: 44,
                        height: 32,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: well,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: hairline),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: s.icon,
                            fit: BoxFit.contain,
                            memCacheWidth: 100,
                            errorWidget: (_, _, _) => Icon(
                              Icons.live_tv_rounded,
                              color: inkFaint,
                              size: 16,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: well,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${widget.index}',
                          style: TextStyle(
                            color: inkSoft,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    const Spacer(),

                    if (widget.isAlive)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),

                    GestureDetector(
                      onTap: widget.onToggleFavorite,
                      child: Icon(
                        widget.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: widget.isFavorite
                            ? (isLight
                                  ? PrismAccent.starTextLight
                                  : DizzyGlow.gold)
                            : inkFaint,
                        size: 19,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Channel Title
                Text(
                  s.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 6),

                // Bottom row: format tag + Play Icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: well,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: hairline),
                      ),
                      child: Text(
                        s.containerExt.toUpperCase(),
                        style: TextStyle(
                          color: inkSoft,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _hovered ? palette.primaryColor : well,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: _hovered ? PrismAccent.onAccent : ink,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelCompactListRow extends StatefulWidget {
  final int index;
  final IptvStream stream;
  final VerifiedPortal? portal;
  final bool isAlive;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _LiveChannelCompactListRow({
    super.key,
    required this.index,
    required this.stream,
    this.portal,
    required this.isAlive,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_LiveChannelCompactListRow> createState() =>
      _LiveChannelCompactListRowState();
}

class _LiveChannelCompactListRowState
    extends State<_LiveChannelCompactListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final s = widget.stream;
    final showLogo = IptvSettings.showStreamLogos.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkFaint = isLight ? PrismLight.inkFaint : Colors.white38;
    final panel = isLight ? PrismLight.raisedTop : DizzyVoid.voidB;
    final hoverFill = isLight ? PrismLight.raisedBottom : DizzyVoid.surface1;
    final hairline = isLight ? PrismLight.borderSubtle : DizzyVoid.surface2;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _hovered ? hoverFill : panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered
                    ? palette.primaryColor.withValues(alpha: 0.7)
                    : hairline,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    widget.index.toString().padLeft(3, '0'),
                    style: TextStyle(
                      color: inkFaint,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (showLogo && s.icon.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 32,
                    height: 24,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: s.icon,
                        fit: BoxFit.contain,
                        memCacheWidth: 64,
                        errorWidget: (_, _, _) => Icon(
                          Icons.live_tv_rounded,
                          color: inkFaint,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.isAlive) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
                GestureDetector(
                  onTap: widget.onToggleFavorite,
                  child: Icon(
                    widget.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: widget.isFavorite
                        ? (isLight ? PrismAccent.starTextLight : DizzyGlow.gold)
                        : inkFaint,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.play_arrow_rounded,
                  color: _hovered ? PrismAccent.text(isLight) : inkFaint,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VodSeriesCard extends StatefulWidget {
  final IptvStream stream;
  final bool isSeries;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _VodSeriesCard({
    super.key,
    required this.stream,
    required this.isSeries,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_VodSeriesCard> createState() => _VodSeriesCardState();
}

class _VodSeriesCardState extends State<_VodSeriesCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stream;
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final well = isLight ? PrismLight.raisedBottom : DizzyVoid.surface1;
    final hairline = isLight ? PrismLight.borderSubtle : DizzyVoid.surface3;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            scale: _hovered ? 1.035 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: well,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _hovered ? const Color(0xFF7C5CFF) : hairline,
                        width: _hovered ? 1.4 : 1.0,
                      ),
                      boxShadow: _hovered
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF7C5CFF,
                                ).withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          s.icon.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: s.icon,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 256,
                                  errorWidget: (_, _, _) => const Center(
                                    child: Icon(
                                      Icons.movie_rounded,
                                      color: Colors.white38,
                                      size: 32,
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.movie_rounded,
                                    color: Colors.white38,
                                    size: 32,
                                  ),
                                ),
                          if (_hovered)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black45,
                                child: const Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Color(0xFF7C5CFF),
                                    size: 40,
                                  ),
                                ),
                              ),
                            ),
                          // Floating Favorite Star Button
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: widget.onToggleFavorite,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: widget.isFavorite
                                          ? DizzyGlow.gold
                                          : Colors.white24,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Icon(
                                    widget.isFavorite
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    color: widget.isFavorite
                                        ? DizzyGlow.gold
                                        : Colors.white70,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesEpisodesSheet extends StatefulWidget {
  final VerifiedPortal portal;
  final IptvStream series;

  const _SeriesEpisodesSheet({required this.portal, required this.series});

  @override
  State<_SeriesEpisodesSheet> createState() => _SeriesEpisodesSheetState();
}

class _SeriesEpisodesSheetState extends State<_SeriesEpisodesSheet> {
  bool _isLoading = true;
  List<IptvEpisode> _episodes = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    try {
      final eps = await IptvClient.seriesEpisodes(
        widget.portal.portal,
        widget.series.streamId,
      );
      if (mounted) {
        setState(() {
          _episodes = eps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _isLoading = false;
        });
      }
    }
  }

  void _playEpisode(IptvEpisode ep) {
    final epIndex = _episodes.indexWhere((e) => e.id == ep.id);
    final initialIndex = epIndex >= 0 ? epIndex : 0;

    final hits = _episodes.map((e) {
      final s = IptvStream(
        streamId: e.id,
        name: '${widget.series.name} - S${e.season}E${e.episode} ${e.title}',
        icon: e.image.isNotEmpty ? e.image : widget.series.icon,
        categoryId: widget.series.categoryId,
        containerExt: e.containerExt,
        kind: 'series',
      );
      return ChannelHit(
        portal: widget.portal,
        stream: s,
        streamUrl: IptvClient.streamUrl(widget.portal.portal, s),
      );
    }).toList();

    final currentStream = (hits.isNotEmpty && initialIndex < hits.length)
        ? hits[initialIndex].stream
        : IptvStream(
            streamId: ep.id,
            name:
                '${widget.series.name} - S${ep.season}E${ep.episode} ${ep.title}',
            icon: ep.image.isNotEmpty ? ep.image : widget.series.icon,
            categoryId: widget.series.categoryId,
            containerExt: ep.containerExt,
            kind: 'series',
          );

    final ch = HardcodedChannel(
      id: ep.id,
      name: currentStream.name,
      short: 'TV',
      category: widget.series.name,
      keywords: [widget.series.name],
      gradient: const [Color(0xFF7C5CFF), Color(0xFF00D2EF)],
    );

    Navigator.pop(context);
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: IptvPlayerPage(
          channel: ch,
          hits: hits.isNotEmpty
              ? hits
              : [
                  ChannelHit(
                    portal: widget.portal,
                    stream: currentStream,
                    streamUrl: IptvClient.streamUrl(
                      widget.portal.portal,
                      currentStream,
                    ),
                  ),
                ],
          initialHitIndex: initialIndex,
          isLive: false,
          categoryTitle: '${widget.series.name} Episodes',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
    final well = isLight ? PrismLight.raisedBottom : DizzyVoid.surface1;
    final accentText = PrismAccent.text(isLight);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: BoxDecoration(
        color: palette.cardBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: isLight
                    ? PrismLight.inkFaint.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.series.name,
                    style: TextStyle(
                      color: ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: inkSoft),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                  )
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    itemCount: _episodes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final ep = _episodes[index];
                      return ListTile(
                        tileColor: well,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF7C5CFF,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'S${ep.season}E${ep.episode}',
                            style: TextStyle(
                              color: accentText,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          ep.title.isNotEmpty
                              ? ep.title
                              : 'Episode ${ep.episode}',
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Color(0xFF7C5CFF),
                        ),
                        onTap: () => _playEpisode(ep),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _VerticalScrollButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _VerticalScrollButton({required this.icon, required this.onTap});

  @override
  State<_VerticalScrollButton> createState() => _VerticalScrollButtonState();
}

class _VerticalScrollButtonState extends State<_VerticalScrollButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF7C5CFF) : Colors.black87,
            shape: BoxShape.circle,
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF7C5CFF)
                  : Colors.white.withValues(alpha: 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(widget.icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
