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
/// notice — never a glimpse of content. Category-wise rails come from the
/// 7 curated adult addons; missing/dead addons show an Install card.
class AdultHeavenPage extends StatefulWidget {
  const AdultHeavenPage({super.key});

  @override
  State<AdultHeavenPage> createState() => _AdultHeavenPageState();
}

class _AdultHeavenPageState extends State<AdultHeavenPage> {
  final _manager = AddonManager.instance;
  bool _loading = true;
  List<MovieSection> _sections = [];
  String? _error;

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
    super.dispose();
  }

  void _onGateChanged() {
    if (!mounted) return;
    if (!AdultSectionGate.visible.value) {
      // Admin blocked mid-browse → drop content immediately.
      setState(() {
        _sections = [];
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
      final installed = _manager.addons;
      final out = <MovieSection>[];
      // One rail per installed adult addon = category-wise rows.
      for (final addon in installed) {
        if (!AddonManager.isAdultAddon(addon)) continue;
        if (!addon.isCatalogsActive) continue;
        try {
          final sections = await _manager.fetchAllHomeSections().timeout(
            const Duration(seconds: 30),
          );
          for (final s in sections) {
            if (s.addonBaseUrl == addon.baseUrl) out.add(s);
          }
          if (out.length >= 12) break;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _sections = out;
          _loading = false;
          _error = out.isEmpty ? 'empty' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
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
            child: ListView.builder(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: _sections.length + _missingInstalls().length + 1,
              itemBuilder: (context, i) {
                if (i < _sections.length) {
                  return MovieSliderSection(section: _sections[i]);
                }
                final missing = _missingInstalls();
                final mi = i - _sections.length;
                if (mi < missing.length) return _installCard(missing[mi]);
                return SizedBox(height: PrismLayout.dockClearance(context));
              },
            ),
          );
        },
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
      ],
    );
  }
}
