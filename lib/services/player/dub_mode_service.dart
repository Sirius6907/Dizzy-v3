import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global audio-dub preference for Movies & Series (home section only).
/// Anime sections intentionally NOT affected — separate scrapers/flows.
enum AudioDubMode { english, hindi }

/// Holds the app-wide dub mode (English default / Hindi Dub).
///
/// Pattern mirrors [PlayerSettings]: static ValueNotifier + async persist.
/// Watch screen, NextEpisodeEngine and PlayerScreen episode-switch all
/// read [isHindi] before offering sources to the probe race, so health
/// probes only ever run on sources matching the selected language.
class DubModeService {
  static const String _prefsKey = 'audio_dub_mode';

  static final ValueNotifier<AudioDubMode> mode =
      ValueNotifier<AudioDubMode>(AudioDubMode.english);
  static bool _initialized = false;

  /// Whether Hindi Dub mode is active (source filtering enabled).
  static bool get isHindi => mode.value == AudioDubMode.hindi;

  /// Call once from main() alongside the other settings initializers.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefsKey) == 'hindi') {
        mode.value = AudioDubMode.hindi;
      }
    } catch (_) {
      // Prefs unavailable — keep default english mode.
    }
    _initialized = true;
  }

  /// Sets the mode, persists it, and notifies listeners (home toggle).
  static Future<void> setMode(AudioDubMode m) async {
    mode.value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, m.name);
    } catch (_) {}
  }

  /// Tests only: reset static state between cases.
  @visibleForTesting
  static void resetForTest() {
    mode.value = AudioDubMode.english;
    _initialized = false;
  }
}
