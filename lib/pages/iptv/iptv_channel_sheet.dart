import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/design/prism_shadows.dart';
import '../../services/theme/app_theme_service.dart';
import '../../models/iptv/iptv_models.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_controller.dart';
import '../../utils/navigation/route_transitions.dart';
import 'iptv_player_page.dart';

class IptvChannelSheet extends StatefulWidget {
  final HardcodedChannel channel;

  const IptvChannelSheet({super.key, required this.channel});

  static Future<void> show(BuildContext context, HardcodedChannel channel) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => IptvChannelSheet(channel: channel),
    );
  }

  @override
  State<IptvChannelSheet> createState() => _IptvChannelSheetState();
}

class _IptvChannelSheetState extends State<IptvChannelSheet> {
  final _ctrl = IptvController.instance;

  bool _isSelecting = false;
  final Set<String> _selectedUrls = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _ctrl.openHardcodedChannel(widget.channel);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _playHit(ChannelHit hit, [Offset? tapPos]) {
    final results = _ctrl.channelResults;
    if (results.isEmpty) return;
    final index = results.indexOf(hit);
    Navigator.pop(context);
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: IptvPlayerPage(
          channel: widget.channel,
          hits: results,
          initialHitIndex: index >= 0 ? index : 0,
          isLive: true,
        ),
        tapPosition: tapPos,
      ),
    );
  }

  void _toggleSelection(String streamUrl) {
    setState(() {
      if (_selectedUrls.contains(streamUrl)) {
        _selectedUrls.remove(streamUrl);
      } else {
        _selectedUrls.add(streamUrl);
      }
    });
  }

  Future<void> _deleteSelectedStreams() async {
    if (_selectedUrls.isEmpty) return;
    final count = _selectedUrls.length;
    final toDelete = Set<String>.from(_selectedUrls);
    setState(() {
      _selectedUrls.clear();
      _isSelecting = false;
    });
    await _ctrl.removeChannelHits(widget.channel.id, toDelete);
    if (mounted) {
      final palette = AppThemeService.currentPalette.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed $count stream feed${count == 1 ? "" : "s"}'),
          duration: const Duration(seconds: 2),
          backgroundColor: palette.isLight
              ? PrismLight.raisedTop
              : PrismDark.raised,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    // P6 hex sweep: these two stay literal on purpose. They are the IPTV brand
    // gradient pair (amethyst + cyan) and are also the gradient stops of the
    // hero wash below, so a surface token swap would change the artwork.
    final primaryColor = ch.gradient.isNotEmpty
        ? ch.gradient.first
        : const Color(0xFF7C5CFF);
    final secondaryColor = ch.gradient.length > 1
        ? ch.gradient.last
        : const Color(0xFF00D2EF);

    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final accent = palette.primaryColor;
    final accentText = PrismAccent.text(isLight);
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white70;
    final inkFaint = isLight ? PrismLight.inkFaint : Colors.white38;
    final panel = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final clayBorder = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.10);
    final starColor = isLight ? PrismAccent.starTextLight : PrismAccent.warning;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final results = _ctrl.channelResults;
        final isScanning = _ctrl.channelIsRunning;
        final status = _ctrl.channelStatus;
        final filteredResults = _searchQuery.trim().isEmpty
            ? results
            : results.where((hit) {
                final q = _searchQuery.trim().toLowerCase();
                final nameMatches = hit.stream.name.toLowerCase().contains(q);
                final portalMatches =
                    hit.portal.name.toLowerCase().contains(q) ||
                    hit.portal.portal.username.toLowerCase().contains(q);
                final formatMatches = hit.stream.containerExt
                    .toLowerCase()
                    .contains(q);
                return nameMatches || portalMatches || formatMatches;
              }).toList();
        final allSelected =
            results.isNotEmpty && _selectedUrls.length == results.length;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          decoration: BoxDecoration(
            gradient: PrismShadows.surfaceGradient(
              AppThemeService.currentPalette.value.isLight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: PrismShadows.floating(
              isLight: AppThemeService.currentPalette.value.isLight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: PrismShadows.pressedGradient(
                      AppThemeService.currentPalette.value.isLight,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Header Banner
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 16, 10),
                child: Row(
                  children: [
                    // Channel Short / Icon Badge
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [primaryColor, secondaryColor],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.4),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          ch.short,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Title & Category
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: PrismAccent.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: PrismAccent.onAccent,
                                    fontSize: PrismType.micro,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                ch.category,
                                style: TextStyle(
                                  color: inkSoft,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ch.name,
                            style: TextStyle(
                              color: ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Pen / Edit Button
                    if (results.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          _isSelecting
                              ? Icons.edit_off_rounded
                              : Icons.edit_rounded,
                          color: _isSelecting ? accentText : inkSoft,
                          size: 22,
                        ),
                        tooltip: _isSelecting
                            ? 'Cancel Selection'
                            : 'Manage / Delete Channels',
                        onPressed: () {
                          setState(() {
                            _isSelecting = !_isSelecting;
                            if (!_isSelecting) _selectedUrls.clear();
                          });
                        },
                      ),

                    // Close Button
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: inkSoft),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Search Input Field
              if (results.isNotEmpty || _searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _searchQuery.isNotEmpty
                            ? accent.withValues(alpha: isLight ? 0.55 : 0.6)
                            : clayBorder,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: ink, fontSize: 13.5),
                      cursorColor: accent,
                      decoration: InputDecoration(
                        hintText:
                            'Search ${results.length} channels (e.g. 1080p, 4K, feed name)...',
                        hintStyle: TextStyle(color: inkFaint, fontSize: 13),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: _searchQuery.isNotEmpty
                              ? accentText
                              : inkFaint,
                          size: 20,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: inkSoft,
                                  size: 18,
                                ),
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val);
                      },
                    ),
                  ),
                ),

              // Selection Toolbar (when in edit mode)
              if (_isSelecting)
                Container(
                  margin: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isLight ? 0.08 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accent.withValues(alpha: isLight ? 0.25 : 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Select All / Deselect All
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: ink,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          minimumSize: const Size(0, 48),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          allSelected
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                          size: 18,
                          color: accentText,
                        ),
                        label: Text(
                          allSelected ? 'Deselect All' : 'Select All',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            if (allSelected) {
                              _selectedUrls.clear();
                            } else {
                              _selectedUrls.clear();
                              _selectedUrls.addAll(
                                results.map((h) => h.streamUrl),
                              );
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${_selectedUrls.length}/${results.length})',
                        style: TextStyle(
                          color: inkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      // Delete Selected
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PrismAccent.danger,
                          foregroundColor: PrismAccent.onAccent,
                          disabledBackgroundColor: PrismAccent.danger
                              .withValues(alpha: 0.35),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          minimumSize: const Size(0, 48),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.delete_rounded, size: 15),
                        label: Text(
                          'Delete (${_selectedUrls.length})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _selectedUrls.isEmpty
                            ? null
                            : _deleteSelectedStreams,
                      ),
                    ],
                  ),
                ),

              // Status Bar / Progress
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: clayBorder),
                  ),
                  child: Row(
                    children: [
                      if (isScanning)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      else
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: isLight
                              ? PrismAccent.successTextLight
                              : PrismAccent.success,
                          size: 16,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status.isNotEmpty
                              ? status
                              : (_searchQuery.trim().isNotEmpty
                                    ? 'Found ${filteredResults.length} of ${results.length} feeds'
                                    : '${results.length} live stream feeds available'),
                          style: TextStyle(
                            color: inkSoft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isScanning)
                        GestureDetector(
                          onTap: _ctrl.stopChannelSearch,
                          child: const Text(
                            'Stop',
                            style: TextStyle(
                              color: PrismAccent.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Discovered Stream Hits List
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isScanning) ...[
                                CircularProgressIndicator(color: accent),
                                const SizedBox(height: 16),
                                Text(
                                  'Scanning all verified portals in parallel…',
                                  style: TextStyle(
                                    color: inkSoft,
                                    fontSize: 14,
                                  ),
                                ),
                              ] else ...[
                                Icon(
                                  Icons.tv_off_rounded,
                                  color: inkFaint,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No alive streams discovered yet.',
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Tap "Scan More Portals" to discover fresh feeds.',
                                  style: TextStyle(
                                    color: inkFaint,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : (filteredResults.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      color: inkFaint,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No feeds match "$_searchQuery"',
                                      style: TextStyle(
                                        color: ink,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                      child: Text(
                                        'Clear Search',
                                        style: TextStyle(
                                          color: accentText,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 6,
                              ),
                              physics: const BouncingScrollPhysics(),
                              itemCount: filteredResults.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final hit = filteredResults[index];
                                final isFav = _ctrl.isFavoriteHit(ch.id, hit);
                                final isSelected = _selectedUrls.contains(
                                  hit.streamUrl,
                                );

                                return MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () => _isSelecting
                                        ? _toggleSelection(hit.streamUrl)
                                        : _playHit(hit),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? accent.withValues(
                                                alpha: isLight ? 0.10 : 0.15,
                                              )
                                            : panel,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isSelected
                                              ? accent
                                              : (isFav
                                                    ? accent.withValues(
                                                        alpha: 0.6,
                                                      )
                                                    : clayBorder),
                                          width: isSelected || isFav
                                              ? 1.6
                                              : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          // Selection checkbox or Play icon
                                          if (_isSelecting)
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? accent
                                                    : (isLight
                                                          ? PrismLight
                                                                .raisedBottom
                                                          : Colors.white
                                                                .withValues(
                                                                  alpha: 0.06,
                                                                )),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? accent
                                                      : inkFaint,
                                                  width: 2,
                                                ),
                                              ),
                                              child: isSelected
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color:
                                                          PrismAccent.onAccent,
                                                      size: 18,
                                                    )
                                                  : null,
                                            )
                                          else
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: accent.withValues(
                                                  alpha: isLight ? 0.12 : 0.2,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.play_arrow_rounded,
                                                color: accentText,
                                                size: 22,
                                              ),
                                            ),

                                          const SizedBox(width: 14),

                                          // Stream Info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 7,
                                                      height: 7,
                                                      decoration:
                                                          const BoxDecoration(
                                                            color: PrismAccent
                                                                .success,
                                                            shape:
                                                                BoxShape.circle,
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color:
                                                                    PrismAccent
                                                                        .success,
                                                                blurRadius: 4,
                                                              ),
                                                            ],
                                                          ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        hit.stream.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: ink,
                                                          fontSize: 14.5,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 13,
                                                      ),
                                                  child: Text(
                                                    hit
                                                            .portal
                                                            .portal
                                                            .username
                                                            .isNotEmpty
                                                        ? hit
                                                              .portal
                                                              .portal
                                                              .username
                                                        : (hit
                                                                  .portal
                                                                  .name
                                                                  .isNotEmpty
                                                              ? hit.portal.name
                                                              : 'Server ${index + 1}'),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: inkSoft,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Format Tag
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isLight
                                                  ? PrismLight.raisedBottom
                                                  : Colors.white.withValues(
                                                      alpha: 0.10,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              hit.stream.containerExt
                                                  .toUpperCase(),
                                              style: TextStyle(
                                                color: inkSoft,
                                                fontSize: PrismType.micro,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),

                                          const SizedBox(width: 8),

                                          // Favorite Pin
                                          IconButton(
                                            icon: Icon(
                                              isFav
                                                  ? Icons.star_rounded
                                                  : Icons.star_outline_rounded,
                                              color: isFav
                                                  ? starColor
                                                  : inkFaint,
                                              size: 22,
                                            ),
                                            tooltip: isFav
                                                ? 'Unpin favourite'
                                                : 'Pin favourite',
                                            onPressed: () =>
                                                _ctrl.toggleFavoriteHit(hit),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )),
              ),

              // Bottom Action Bar
              Container(
                padding: EdgeInsets.fromLTRB(
                  22,
                  12,
                  22,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: clayBorder)),
                ),
                child: Row(
                  children: [
                    // Quick Play Best
                    if (results.isNotEmpty)
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: PrismAccent.onAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(
                            Icons.play_arrow_rounded,
                            color: PrismAccent.onAccent,
                          ),
                          label: const Text(
                            'Watch Live',
                            style: TextStyle(
                              color: PrismAccent.onAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: filteredResults.isNotEmpty
                              ? () => _playHit(filteredResults.first)
                              : () => _playHit(results.first),
                        ),
                      ),

                    if (results.isNotEmpty) const SizedBox(width: 12),

                    // Scan More
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ink,
                        side: BorderSide(
                          color: isLight
                              ? PrismLight.borderSubtle
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'Scan More',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: isScanning
                          ? null
                          : () => _ctrl.getMoreChannels(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
