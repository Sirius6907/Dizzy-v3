part of 'watch_screen.dart';

// setState is @protected: the analyzer wants it only inside State
// subclasses, but these methods are a mechanical move out of
// _WatchScreenState (Dart has no partial classes). Same library, same
// instance, identical runtime behaviour — file-scoped ignore only.
// ignore_for_file: invalid_use_of_protected_member

extension _WatchScreenStateSheetsAndStates on _WatchScreenState {
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
