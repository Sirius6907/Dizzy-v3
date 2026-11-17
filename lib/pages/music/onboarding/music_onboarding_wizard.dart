import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/prism_tokens.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_onboarding_service.dart';
import '../../../services/music/music_service.dart';
import '../../../services/music/music_mood_filter.dart';
import '../../../services/theme/app_theme_service.dart';

/// Music onboarding wizard (Part B, 2026-11-12).
///
/// Three skippable steps on the first open of the Music tab:
/// 1. favorite artists — live trending + free-text search, min 0, no max,
/// 2. music styles (multi-select chips),
/// 3. default mood preference.
///
/// Completing (or skipping) persists through `MusicOnboardingService` and
/// the wizard never re-shows on open afterwards; Music Settings reopens it
/// in [settingsMode] to edit preferences.
class MusicOnboardingWizard extends StatefulWidget {
  final bool settingsMode;

  const MusicOnboardingWizard({super.key, this.settingsMode = false});

  @override
  State<MusicOnboardingWizard> createState() => _MusicOnboardingWizardState();
}

class _MusicOnboardingWizardState extends State<MusicOnboardingWizard> {
  final PageController _pageController = PageController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  int _step = 0;
  final Set<String> _pickedArtists = <String>{};
  final Set<MusicStyle> _pickedStyles = <MusicStyle>{};
  MusicMood _pickedMood = MusicMood.any;

  List<MusicArtist> _trendingArtists = const [];
  List<MusicArtist> _searchResults = const [];
  bool _loadingTrending = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // Settings mode opens with what the user already picked.
    _pickedArtists.addAll(MusicOnboardingService.favoriteArtists.value);
    _pickedStyles.addAll(MusicOnboardingService.selectedStyles.value);
    _pickedMood = MusicOnboardingService.defaultMood.value;
    _loadTrending();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    try {
      final artists = await MusicService.instance.fetchTrendingArtists();
      if (!mounted) return;
      setState(() {
        _trendingArtists = artists;
        _loadingTrending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTrending = false);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final data = await MusicService.instance.searchFull(q);
      if (!mounted) return;
      setState(() => _searchResults = data.artists);
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchResults = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _toggleArtist(String name) {
    setState(() {
      if (!_pickedArtists.remove(name)) _pickedArtists.add(name);
    });
  }

  void _toggleStyle(MusicStyle style) {
    setState(() {
      if (!_pickedStyles.remove(style)) _pickedStyles.add(style);
    });
  }

  void _goStep(int target) {
    if (target < 0 || target > 2) return;
    setState(() => _step = target);
    _pageController.animateToPage(
      target,
      duration: PrismMotion.standard,
      curve: PrismMotion.curve,
    );
  }

  Future<void> _finish() async {
    if (widget.settingsMode) {
      await MusicOnboardingService.updatePreferences(
        artists: _pickedArtists.toList(),
        styles: _pickedStyles.toList(),
        mood: _pickedMood,
      );
    } else {
      await MusicOnboardingService.complete(
        artists: _pickedArtists.toList(),
        styles: _pickedStyles.toList(),
        mood: _pickedMood,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final panel = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final border = isLight ? PrismLight.borderSubtle : PrismDark.borderSubtle;

    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Text(
          widget.settingsMode ? 'Edit Your Music Vibe' : 'Welcome to Music',
          style: TextStyle(
            color: isLight ? PrismLight.ink : PrismDark.ink,
            fontSize: PrismType.title,
            fontWeight: PrismType.wBold,
          ),
        ),
        actions: [
          if (!widget.settingsMode)
            TextButton(
              onPressed: () async {
                await MusicOnboardingService.skip();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text(
                'Skip',
                style: TextStyle(
                  color: isLight ? PrismLight.inkFaint : PrismDark.inkFaint,
                  fontSize: PrismType.body,
                  fontWeight: PrismType.wMedium,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: PrismSpace.md),
          _ProgressDots(
            step: _step,
            count: 3,
            accent: palette.primaryColor,
            track: isLight ? PrismLight.neuDark : PrismDark.neuLight,
          ),
          const SizedBox(height: PrismSpace.md),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildArtistStep(panel, border, isLight),
                _buildStyleStep(panel, border, isLight),
                _buildMoodStep(panel, border, isLight),
              ],
            ),
          ),
          _buildNavRow(palette, panel, border, isLight),
        ],
      ),
    );
  }

  // --- Step 1: favorite artists -------------------------------------------

  Widget _buildArtistStep(Color panel, Color border, bool isLight) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: PrismSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick your favorite singers',
            style: TextStyle(
              color: isLight ? PrismLight.ink : PrismDark.ink,
              fontSize: PrismType.headline,
              fontWeight: PrismType.wBold,
            ),
          ),
          const SizedBox(height: PrismSpace.xs),
          Text(
            'Optional — your vibe engine learns from whoever you choose. '
            'Skip ahead if you like to be surprised.',
            style: TextStyle(
              color: isLight ? PrismLight.inkSoft : PrismDark.inkSoft,
              fontSize: PrismType.body,
            ),
          ),
          const SizedBox(height: PrismSpace.md),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search any artist…',
              hintStyle: TextStyle(
                color: isLight ? PrismLight.inkFaint : PrismDark.inkFaint,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: isLight ? PrismLight.inkSoft : PrismDark.inkSoft,
              ),
              filled: true,
              fillColor: panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PrismRadius.lg),
                borderSide: BorderSide(color: border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PrismRadius.lg),
                borderSide: BorderSide(color: border),
              ),
            ),
          ),
          const SizedBox(height: PrismSpace.md),
          if (_pickedArtists.isNotEmpty) ...[
            Wrap(
              spacing: PrismSpace.xs,
              runSpacing: PrismSpace.xs,
              children: [
                for (final name in _pickedArtists)
                  _SelectedChip(
                    label: name,
                    onRemove: () => _toggleArtist(name),
                    isLight: isLight,
                  ),
              ],
            ),
            const SizedBox(height: PrismSpace.md),
          ],
          _artistChips(
            _searchController.text.trim().isEmpty
                ? _trendingArtists
                : _searchResults,
            panel,
            border,
            isLight,
            loading: _searchController.text.trim().isEmpty
                ? _loadingTrending
                : _searching,
          ),
          const SizedBox(height: PrismSpace.xl),
        ],
      ),
    );
  }

  Widget _artistChips(
    List<MusicArtist> artists,
    Color panel,
    Color border,
    bool isLight, {
    required bool loading,
  }) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(PrismSpace.xl),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (artists.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(PrismSpace.lg),
        child: Text(
          'No artists found — try another name.',
          style: TextStyle(
            color: isLight ? PrismLight.inkFaint : PrismDark.inkFaint,
            fontSize: PrismType.caption,
          ),
        ),
      );
    }
    return Wrap(
      spacing: PrismSpace.sm,
      runSpacing: PrismSpace.sm,
      children: [
        for (final artist in artists)
          _ArtistChip(
            artist: artist,
            selected: _pickedArtists.contains(artist.name),
            onTap: () => _toggleArtist(artist.name),
            panel: panel,
            border: border,
            isLight: isLight,
          ),
      ],
    );
  }

  // --- Step 2: styles ------------------------------------------------------

  Widget _buildStyleStep(Color panel, Color border, bool isLight) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: PrismSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What do you listen to?',
            style: TextStyle(
              color: isLight ? PrismLight.ink : PrismDark.ink,
              fontSize: PrismType.headline,
              fontWeight: PrismType.wBold,
            ),
          ),
          const SizedBox(height: PrismSpace.xs),
          Text(
            'Pick any vibes you love. These shape your Made For You mixes.',
            style: TextStyle(
              color: isLight ? PrismLight.inkSoft : PrismDark.inkSoft,
              fontSize: PrismType.body,
            ),
          ),
          const SizedBox(height: PrismSpace.xl),
          Wrap(
            spacing: PrismSpace.sm,
            runSpacing: PrismSpace.sm,
            children: [
              for (final style in MusicStyle.values)
                _StyleChip(
                  style: style,
                  selected: _pickedStyles.contains(style),
                  onTap: () => _toggleStyle(style),
                  panel: panel,
                  border: border,
                  isLight: isLight,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Step 3: default mood ------------------------------------------------

  Widget _buildMoodStep(Color panel, Color border, bool isLight) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: PrismSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your default mood',
            style: TextStyle(
              color: isLight ? PrismLight.ink : PrismDark.ink,
              fontSize: PrismType.headline,
              fontWeight: PrismType.wBold,
            ),
          ),
          const SizedBox(height: PrismSpace.xs),
          Text(
            'The mood Music opens with. You can switch it any time.',
            style: TextStyle(
              color: isLight ? PrismLight.inkSoft : PrismDark.inkSoft,
              fontSize: PrismType.body,
            ),
          ),
          const SizedBox(height: PrismSpace.xl),
          Wrap(
            spacing: PrismSpace.sm,
            runSpacing: PrismSpace.sm,
            children: [
              for (final mood in MusicMood.values)
                _MoodChip(
                  label: '${mood.emoji.isEmpty ? '' : '${mood.emoji} '}${mood.label}',
                  selected: _pickedMood == mood,
                  onTap: () => setState(() => _pickedMood = mood),
                  panel: panel,
                  border: border,
                  isLight: isLight,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Bottom nav ----------------------------------------------------------

  Widget _buildNavRow(
    AppThemePalette palette,
    Color panel,
    Color border,
    bool isLight,
  ) {
    final isLast = _step == 2;
    return Container(
      decoration: BoxDecoration(
        color: panel,
        border: Border(top: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PrismSpace.lg,
        vertical: PrismSpace.md,
      ),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(
              onPressed: () => _goStep(_step - 1),
              child: Text(
                'Back',
                style: TextStyle(
                  color: isLight ? PrismLight.inkSoft : PrismDark.inkSoft,
                  fontSize: PrismType.body,
                  fontWeight: PrismType.wMedium,
                ),
              ),
            ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.primaryColor,
              foregroundColor: PrismAccent.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: PrismSpace.xl),
            ),
            onPressed: isLast ? _finish : () => _goStep(_step + 1),
            child: Text(
              isLast
                  ? (widget.settingsMode ? 'Save' : 'Start listening')
                  : 'Next',
              style: const TextStyle(
                fontSize: PrismType.body,
                fontWeight: PrismType.wSemiBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int step;
  final int count;
  final Color accent;
  final Color track;

  const _ProgressDots({
    required this.step,
    required this.count,
    required this.accent,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: PrismMotion.standard,
            curve: PrismMotion.curve,
            margin: const EdgeInsets.symmetric(horizontal: PrismSpace.xxs),
            width: i == step ? PrismSpace.xxl : PrismSpace.sm,
            height: PrismSpace.xxs + 2,
            decoration: BoxDecoration(
              color: i == step ? accent : track,
              borderRadius: BorderRadius.circular(PrismRadius.pill),
            ),
          ),
      ],
    );
  }
}

class _ArtistChip extends StatelessWidget {
  final MusicArtist artist;
  final bool selected;
  final VoidCallback onTap;
  final Color panel;
  final Color border;
  final bool isLight;

  const _ArtistChip({
    required this.artist,
    required this.selected,
    required this.onTap,
    required this.panel,
    required this.border,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PrismRadius.pill),
        child: AnimatedContainer(
          duration: PrismMotion.micro,
          curve: PrismMotion.curve,
          padding: const EdgeInsets.symmetric(
            horizontal: PrismSpace.sm,
            vertical: PrismSpace.xs + 2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppThemeService.currentPalette.value.primaryColor
                : panel,
            borderRadius: BorderRadius.circular(PrismRadius.pill),
            border: Border.all(
              color: selected ? Colors.transparent : border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: PrismSpace.sm + 2,
                backgroundColor: isLight ? PrismLight.neuDark : PrismDark.sunken,
                backgroundImage: artist.pictureUrl.isEmpty
                    ? null
                    : NetworkImage(artist.pictureUrl),
                child: artist.pictureUrl.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        size: PrismSpace.md,
                        color: isLight ? PrismLight.inkFaint : PrismDark.inkFaint,
                      )
                    : null,
              ),
              const SizedBox(width: PrismSpace.xs),
              Text(
                artist.name,
                style: TextStyle(
                  color: selected
                      ? PrismAccent.onAccent
                      : (isLight ? PrismLight.ink : PrismDark.ink),
                  fontSize: PrismType.body,
                  fontWeight: PrismType.wMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  final MusicStyle style;
  final bool selected;
  final VoidCallback onTap;
  final Color panel;
  final Color border;
  final bool isLight;

  const _StyleChip({
    required this.style,
    required this.selected,
    required this.onTap,
    required this.panel,
    required this.border,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PrismRadius.pill),
        child: AnimatedContainer(
          duration: PrismMotion.micro,
          curve: PrismMotion.curve,
          padding: const EdgeInsets.symmetric(
            horizontal: PrismSpace.md,
            vertical: PrismSpace.sm + 2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppThemeService.currentPalette.value.primaryColor
                : panel,
            borderRadius: BorderRadius.circular(PrismRadius.pill),
            border: Border.all(
              color: selected ? Colors.transparent : border,
            ),
          ),
          child: Text(
            '${style.emoji} ${style.label}',
            style: TextStyle(
              color: selected
                  ? PrismAccent.onAccent
                  : (isLight ? PrismLight.ink : PrismDark.ink),
              fontSize: PrismType.subtitle,
              fontWeight: PrismType.wSemiBold,
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color panel;
  final Color border;
  final bool isLight;

  const _MoodChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.panel,
    required this.border,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PrismRadius.pill),
        child: AnimatedContainer(
          duration: PrismMotion.micro,
          curve: PrismMotion.curve,
          padding: const EdgeInsets.symmetric(
            horizontal: PrismSpace.md,
            vertical: PrismSpace.sm + 2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppThemeService.currentPalette.value.primaryColor
                : panel,
            borderRadius: BorderRadius.circular(PrismRadius.pill),
            border: Border.all(
              color: selected ? Colors.transparent : border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? PrismAccent.onAccent
                  : (isLight ? PrismLight.ink : PrismDark.ink),
              fontSize: PrismType.subtitle,
              fontWeight: PrismType.wSemiBold,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  final bool isLight;

  const _SelectedChip({
    required this.label,
    required this.onRemove,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PrismSpace.sm,
        vertical: PrismSpace.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: isLight ? PrismLight.neuLight : PrismDark.raisedTop,
        borderRadius: BorderRadius.circular(PrismRadius.pill),
        border: Border.all(
          color: isLight ? PrismLight.borderSubtle : PrismDark.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isLight ? PrismLight.inkSoft : PrismDark.inkSoft,
              fontSize: PrismType.caption,
              fontWeight: PrismType.wMedium,
            ),
          ),
          const SizedBox(width: PrismSpace.xxs),
          InkWell(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: PrismSpace.md + 2,
              color: isLight ? PrismLight.inkFaint : PrismDark.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
