/// F1 — language tags decide which audio track plays first.
///
/// The dub gate has two halves. `filterByDubMode` (services/stream) keeps
/// non-Hindi *sources* out of the race when Hindi mode is on. This is the
/// other half: one source usually carries several audio tracks, and the
/// player's default pick is whatever the container happened to list first —
/// which is regularly the English track even in Hindi mode.
///
/// Pure policy (no mpv, no BuildContext) so it unit-tests in milliseconds.
/// Hindi preference selects explicit Hindi first, then explicit English.
/// Null means "keep the player's own pick", not proof of its language.
library;

/// One selectable audio track, flattened from whatever the player reports.
class AudioTrackOption {
  /// mpv track id (the same value PlayerAudioMenu shows as `index`).
  final int index;

  /// ISO-ish language tag when the container carries one ('hin', 'eng').
  final String? language;

  /// Human label — plenty of containers only tag the title, not `language`.
  final String? title;

  const AudioTrackOption({required this.index, this.language, this.title});
}

abstract final class AudioTrackPreference {
  /// ISO 639 codes plus the spelled-out names addons actually ship.
  static const Set<String> _hindiTags = {'hin', 'hi', 'hindi'};
  static const Set<String> _englishTags = {'eng', 'en', 'english'};

  static final RegExp _hindiLabel = RegExp(
    r'\b(?:hi|hin|hindi)\b',
    caseSensitive: false,
  );
  static final RegExp _englishLabel = RegExp(
    r'\b(?:en|eng|english)\b',
    caseSensitive: false,
  );

  /// Pick explicit Hindi first (when preferred), then explicit English.
  /// Within each language, tags outrank labels. A conflicting language tag
  /// blocks label inference; unknown/original/multi alone never prove English.
  /// Returns null when neither language is evidenced.
  static int? pick({
    required List<AudioTrackOption> tracks,
    required bool hindi,
  }) {
    for (final wanted in [if (hindi) _hindiTags, _englishTags]) {
      for (final t in tracks) {
        if (wanted.contains(_normalize(t.language))) return t.index;
      }

      final pattern = wanted == _hindiTags ? _hindiLabel : _englishLabel;
      for (final t in tracks) {
        // Only absent or unspecified tags permit a label-based inference.
        final tag = _normalize(t.language);
        if (tag != null && tag != 'und' && tag != 'unknown' && tag != 'mul') {
          continue;
        }
        if (pattern.hasMatch(t.title ?? '')) return t.index;
      }
    }

    return null;
  }

  /// mpv reports 'hin', 'hin_IN', 'HIN' — compare on the base subtag.
  static String? _normalize(String? raw) {
    final v = raw?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return null;
    final base = v.split(RegExp('[_-]')).first;
    return base.isEmpty ? null : base;
  }
}
