import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_mood_filter.dart';
import 'music_settings.dart';

/// Music style chips picked in the onboarding wizard (Part B, 2026-11-12).
///
/// Styles map onto the existing `MusicMood` system where it fits — the vibe
/// engine (Part C) converts style selections into `MusicMoodFilter` mood
/// weights. Devotional is the one style the mood enum cannot express, so it
/// carries its own live search phrase instead.
///
/// [vibeTitle] seeds human Made For You mix titles ("Lo-fi Evenings") —
/// never artist-name mashups.
enum MusicStyle {
  lofi('Lofi', '🎧', 'Lo-fi Evenings', MusicMood.night, 'lofi chill beats'),
  romantic(
    'Romantic',
    '💗',
    'Romantic Golden Hour',
    MusicMood.romance,
    'romantic love songs',
  ),
  energetic(
    'Energetic',
    '⚡',
    'High Energy Hour',
    MusicMood.energetic,
    'high energy hits',
  ),
  party(
    'Party',
    '🎉',
    'Party Starters',
    MusicMood.energetic,
    'party dance hits',
  ),
  focus(
    'Focus',
    '🎯',
    'Deep Focus',
    MusicMood.focus,
    'focus instrumental study',
  ),
  devotional(
    'Devotional',
    '🪔',
    'Devotional Mornings',
    MusicMood.any,
    'devotional bhajan mantra peaceful',
  );

  final String label;
  final String emoji;

  /// Human mix title derived from the vibe/style itself.
  final String vibeTitle;

  /// Nearest existing mood for `MusicMoodFilter` scoring. `any` means the
  /// style has no mood-keyword scoring (content is pulled live instead).
  final MusicMood mood;

  /// Live search phrase (mood adjectives — queries, never fixed tracks).
  final String searchQuery;

  const MusicStyle(
    this.label,
    this.emoji,
    this.vibeTitle,
    this.mood,
    this.searchQuery,
  );

  static MusicStyle? fromName(String name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Onboarding state for the music tab (Part B, 2026-11-12).
///
/// SharedPreferences-backed following the `MusicSettings` pattern: read
/// once in [initialize], exposed through ValueNotifiers, written through
/// explicit setters. The single `music_onboarding_done` flag gates the
/// 3-step wizard — once set (by completing OR skipping), the wizard never
/// re-shows on open; Music Settings edits preferences without touching it.
abstract final class MusicOnboardingService {
  static const String _keyDone = 'music_onboarding_done';
  static const String _keyFavorites = 'music_onboarding_favorites';
  static const String _keyStyles = 'music_onboarding_styles';
  static const String _keyDefaultMood = 'music_onboarding_default_mood';

  /// Storage key surfaced for tests and for the settings reset.
  static String get doneKey => _keyDone;

  static final ValueNotifier<bool> isDone = ValueNotifier<bool>(false);
  static final ValueNotifier<List<String>> favoriteArtists =
      ValueNotifier<List<String>>(const []);
  static final ValueNotifier<List<MusicStyle>> selectedStyles =
      ValueNotifier<List<MusicStyle>>(const []);
  static final ValueNotifier<MusicMood> defaultMood = ValueNotifier<MusicMood>(
    MusicMood.any,
  );

  /// Fired on every preference change so the vibe engine can refresh.
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  static bool _initialized = false;

  /// Pure read of a stored favorites list (unit-testable).
  static List<String> sanitizeArtists(List<String> raw) => raw
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty && a.length <= 64)
      .toSet()
      .take(30)
      .toList();

  static List<MusicStyle> sanitizeStyles(List<String> raw) {
    final out = <MusicStyle>[];
    for (final name in raw) {
      final s = MusicStyle.fromName(name);
      if (s != null && !out.contains(s)) out.add(s);
    }
    return out;
  }

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    isDone.value = prefs.getBool(_keyDone) ?? false;
    favoriteArtists.value = sanitizeArtists(
      prefs.getStringList(_keyFavorites) ?? const [],
    );
    selectedStyles.value = sanitizeStyles(
      prefs.getStringList(_keyStyles) ?? const [],
    );
    final moodStr = prefs.getString(_keyDefaultMood);
    defaultMood.value = MusicMood.values.firstWhere(
      (m) => m.name == moodStr,
      orElse: () => MusicMood.any,
    );
    // The wizard promises the default mood is "the mood Music opens with":
    // honor it on every start unless the listener picked a chip manually.
    await MusicSettings.applyDefaultMood(defaultMood.value);
    _initialized = true;
  }

  /// Test hook: forget cached state so initialize() re-reads storage.
  static void resetForTest() {
    _initialized = false;
    isDone.value = false;
    favoriteArtists.value = const [];
    selectedStyles.value = const [];
    defaultMood.value = MusicMood.any;
  }

  /// Wizard completed with the user's picks. Everything may be empty —
  /// skipping individual steps is allowed — but completion still sets the
  /// done flag so the wizard never re-shows.
  static Future<void> complete({
    List<String> artists = const [],
    List<MusicStyle> styles = const [],
    MusicMood mood = MusicMood.any,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    favoriteArtists.value = sanitizeArtists(artists);
    selectedStyles.value = sanitizeStyles(styles.map((s) => s.name).toList());
    defaultMood.value = mood;
    isDone.value = true;

    await prefs.setStringList(_keyFavorites, favoriteArtists.value);
    await prefs.setStringList(
      _keyStyles,
      selectedStyles.value.map((s) => s.name).toList(),
    );
    await prefs.setString(_keyDefaultMood, mood.name);
    await prefs.setBool(_keyDone, true);
    // The listener just chose a default mood — open the home on it.
    await MusicSettings.applyDefaultMood(mood, force: true);
    _notify();
  }

  /// Wizard skipped: mark done, keep any previously saved preferences.
  static Future<void> skip() async {
    final prefs = await SharedPreferences.getInstance();
    isDone.value = true;
    await prefs.setBool(_keyDone, true);
    _notify();
  }

  /// Music Settings edit entry — updates preferences without ever
  /// un-setting the done flag (the wizard must not come back).
  static Future<void> updatePreferences({
    List<String>? artists,
    List<MusicStyle>? styles,
    MusicMood? mood,
  }) async {
    if (!_initialized) await initialize();
    final prefs = await SharedPreferences.getInstance();

    if (artists != null) {
      favoriteArtists.value = sanitizeArtists(artists);
      await prefs.setStringList(_keyFavorites, favoriteArtists.value);
    }
    if (styles != null) {
      selectedStyles.value = sanitizeStyles(styles.map((s) => s.name).toList());
      await prefs.setStringList(
        _keyStyles,
        selectedStyles.value.map((s) => s.name).toList(),
      );
    }
    if (mood != null) {
      defaultMood.value = mood;
      await prefs.setString(_keyDefaultMood, mood.name);
      // Saving the wizard IS the listener's intent — move the home chip.
      await MusicSettings.applyDefaultMood(mood, force: true);
    }
    _notify();
  }

  /// Convenience for the vibe engine: true when any onboarding signal exists.
  static bool get hasSignal =>
      favoriteArtists.value.isNotEmpty ||
      selectedStyles.value.isNotEmpty ||
      defaultMood.value != MusicMood.any;

  static void _notify() {
    changeNotifier.value++;
  }
}
