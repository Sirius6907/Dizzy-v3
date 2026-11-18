import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/prism_tokens.dart';
import '../../models/movie/movie_section.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/adult/adult_directory.dart';
import '../../services/adult/adult_section_gate.dart';
import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/offline_aware_scaffold.dart';
import '../../widgets/movie/movie_slider_section.dart';

/// 18+ Heaven — the adult-only browse page.
///
/// Renders ONLY when [AdultSectionGate.visible] is true (triple lock:
/// local 18+ confirm × admin allow × not-kids). Otherwise shows a locked
/// notice — never a glimpse of content.
///
/// Everything here is section-scoped: rows come from the adult addons via
/// `adultOnly` fan-outs and the search box below also searches only those
/// addons, so a query typed here can never surface normal content and,
/// conversely, nothing adult appears in the normal home/search.
///
/// Chips are built from what the installed addons actually publish: content
/// type plus their catalog genres. Upstream manifests carry no separate
/// language/region field — when an addon lists one as a genre (e.g. "Hindi")
/// it shows up as a chip too, and never invents a category that would
/// return an empty rail.
class AdultHeavenPage extends StatefulWidget {
  const AdultHeavenPage({super.key});

  @override
  State<AdultHeavenPage> createState() => _AdultHeavenPageState();
}

class _AdultHeavenPageState extends State<AdultHeavenPage> {
  final _manager = AddonManager.instance;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  bool _loading = true;
  List<MovieSection> _sections = [];
  String? _error;

  /// Active category chip ('All' shows everything).
  String _chip = 'All';

  /// Non-null while a section-scoped search is showing its results.
  String? _activeQuery;
  List<MovieSection>? _searchResults;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    AdultSectionGate.ensureLoaded();
    AdultSectionGate.visible.addListener(_onGateChanged);
    _load();
  }

  @override
  void dispose() {
    AdultSectionGate.visible.removeListener(_onGateChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onGateChanged() {
    if (!mounted) return;
    if (!AdultSectionGate.visible.value) {
      // Admin blocked mid-browse → drop content immediately.
      setState(() {
        _sections = [];
        _searchResults = null;
        _activeQuery = null;
        _error = 'locked';
      });
      return;
    }
    _load();
  }

  Future<void> _load() async {
    if (!AdultSectionGate.visible.value) {
      setState(() {
        _loading = false;
        _error = 'locked';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // One gated fan-out: only adult addons answer, and only while the
      // gate is open. Grouped into rails below, in addon order.
      final sections = await _manager
          .fetchAllHomeSections(adultOnly: true)
          .timeout(const Duration(seconds: 45));
      final order = <String, int>{};
      for (final addon in _manager.addons) {
        if (!AddonManager.isAdultAddon(addon)) continue;
        order.putIfAbsent(addon.baseUrl, () => order.length);
      }
      final out = List<MovieSection>.from(sections)
        ..sort((a, b) {
          final ai = order[a.addonBaseUrl] ?? order.length;
          final bi = order[b.addonBaseUrl] ?? order.length;
          return ai.compareTo(bi);
        });
      if (mounted) {
        setState(() {
          _sections = out;
          _loading = false;
          _error = out.isEmpty ? 'empty' : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'load';
        });
      }
    }
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) {
      _clearSearch();
      return;
    }
    _searchFocus.unfocus();
    setState(() {
      _searching = true;
      _activeQuery = q;
      _searchResults = null;
    });
    List<MovieSection> results;
    try {
      results = await _manager
          .searchAll(q, adultOnly: true)
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      results = const [];
    }
    if (!mounted || _activeQuery != q) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _activeQuery = null;
      _searchResults = null;
      _searching = false;
    });
  }

  Future<void> _install(AdultDirectoryEntry entry) async {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Adding ${entry.name}...')));
    try {
      await _manager.addAddon(entry.manifestUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${entry.name} added ✓')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add: $e')));
    }
  }

  // ── Category chips ───────────────────────────────────────────────────

  /// Type chips first, then the genres the installed addons advertise,
  /// most common first. No chip exists for a category with no rows.
  List<String> _chips() {
    final counts = <String, int>{};
    for (final s in _sections) {
      for (final raw in s.catalog.genres) {
        final g = raw.trim();
        if (g.isEmpty) continue;
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return <String>[
      'All',
      'Movies',
      'Series',
      ...top.take(12).map((e) => e.key),
    ];
  }

  List<MovieSection> _filtered() {
    if (_chip == 'All') return _sections;
    if (_chip == 'Movies') {
      return _sections.where((s) => s.contentType != 'series').toList();
    }
    if (_chip == 'Series') {
      return _sections.where((s) => s.contentType == 'series').toList();
    }
    final needle = _chip.toLowerCase();
    return _sections.where((s) {
      final genres = s.catalog.genres;
      return genres.any((g) => g.trim().toLowerCase() == needle);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    return OfflineAwareScaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '🔞 18+ Heaven',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: AdultSectionGate.visible,
        builder: (context, open, _) {
          if (!open) return _locked();
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error == 'empty') return _emptyState();
          if (_error != null && _error != 'locked') {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load right now.',
                    style: TextStyle(color: ink),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            color: palette.primaryColor,
            backgroundColor: palette.cardBackgroundColor,
            onRefresh: _load,
            child: _content(),
          );
        },
      ),
    );
  }

  Widget _content() {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final searching = _activeQuery != null;
    final rails = searching ? (_searchResults ?? const <MovieSection>[])
        : _filtered();
    final missing = searching ? const <AdultDirectoryEntry>[] : _missingInstalls();

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.zero,
      children: [
        _searchField(ink, inkSoft),
        if (!searching && _sections.isNotEmpty) _chipBar(),
        if (searching) _searchHeader(inkSoft),
        if (searching && _searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (rails.isEmpty && searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
            child: Text(
              'Nothing in the 18+ section matches "${_activeQuery!}".',
              style: TextStyle(color: inkSoft, fontSize: 13),
            ),
          ),
        for (final s in rails) MovieSliderSection(section: s),
        for (final e in missing) _installCard(e),
        const SizedBox(height: 8),
        SizedBox(height: PrismLayout.dockClearance(context)),
      ],
    );
  }

  Widget _searchField(Color ink, Color inkSoft) {
    final palette = AppThemeService.currentPalette.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        style: TextStyle(color: ink, fontSize: 14),
        textInputAction: TextInputAction.search,
        onSubmitted: _runSearch,
        decoration: InputDecoration(
          hintText: 'Search only the 18+ section',
          hintStyle: TextStyle(color: inkSoft, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, color: inkSoft, size: 20),
          suffixIcon: IconButton(
            icon: Icon(Icons.close_rounded, color: inkSoft, size: 18),
            tooltip: 'Clear search',
            onPressed: _clearSearch,
          ),
          isDense: true,
          filled: true,
          fillColor: palette.cardBackgroundColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _chipBar() {
    final palette = AppThemeService.currentPalette.value;
    final chips = _chips();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final label = chips[i];
          final selected = _chip == label;
          return Center(
            child: ChoiceChip(
              label: Text(label),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => setState(() => _chip = label),
              backgroundColor: palette.cardBackgroundColor,
              selectedColor: palette.primaryColor.withValues(alpha: 0.22),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? palette.primaryColor
                    : (palette.isLight ? PrismLight.ink : Colors.white70),
              ),
              side: BorderSide(
                color: selected
                    ? palette.primaryColor.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }

  Widget _searchHeader(Color inkSoft) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Results in 18+ Heaven only',
              style: TextStyle(
                color: inkSoft,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: _clearSearch,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  /// Directory entries not yet installed → one-tap install cards.
  ///
  /// (2026-10-10 fix: the old check `_installedIds.contains(a.manifest.id)`
  /// was a tautology — _installedIds is BUILT from the installed list, so it
  /// was true for every installed addon, marking every entry "known" and the
  /// install cards NEVER rendered. Now matches the ENTRY id / base URL.)
  List<AdultDirectoryEntry> _missingInstalls() => AdultDirectory.missingEntries(
    _manager.addons
        .map((a) => (id: a.manifest.id, baseUrl: a.baseUrl))
        .toList(),
  );

  Widget _installCard(AdultDirectoryEntry entry) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        color: isLight ? PrismLight.raisedTop : const Color(0xFF1B1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isLight
                ? PrismLight.borderSubtle
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: ListTile(
          leading: const Icon(
            Icons.add_box_rounded,
            color: Color(0xFFE50914),
            size: 32,
          ),
          title: Text(
            entry.name,
            style: TextStyle(
              color: isLight ? PrismLight.ink : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            entry.oneLine,
            style: TextStyle(
              color: isLight ? PrismLight.inkSoft : Colors.white60,
              fontSize: 12,
            ),
          ),
          trailing: FilledButton(
            onPressed: () => _install(entry),
            child: const Text('Install'),
          ),
        ),
      ),
    );
  }

  Widget _locked() {
    final isLight = AppThemeService.currentPalette.value.isLight;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔞', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              '18+ Heaven is locked',
              style: TextStyle(
                color: isLight ? PrismLight.ink : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Confirm you are 18+ in Settings → Privacy. Your admin must also allow this device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isLight ? PrismLight.inkSoft : Colors.white60,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final missing = _missingInstalls();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 12),
        Text(
          'No 18+ sources yet',
          style: TextStyle(
            color: isLight ? PrismLight.ink : Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Install one below — rows appear here category-wise.',
          style: TextStyle(
            color: isLight ? PrismLight.inkSoft : Colors.white60,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        for (final e in missing) _installCard(e),
        SizedBox(height: PrismLayout.dockClearance(context)),
      ],
    );
  }
}
