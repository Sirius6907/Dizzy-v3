/// F1 — language tags decide which audio track plays first.
///
/// The dub gate has two halves. `filterByDubMode` (services/stream) keeps
/// non-Hindi *sources* out of the race when Hindi mode is on. This is the
/// other half: one source usually carries several audio tracks, and the
/// player's default pick is whatever the container happened to list first —
/// which is regularly the English track even in Hindi mode.
///
/// Pure policy (no mpv, no BuildContext) so it unit-tests in milliseconds.
/// Null means "keep the player's own pick", which is always safe: this
/// never forces a wrong-language track onto someone.
library;

/// One selectable audio track, flattened from whatever the player reports.
class AudioTrackOption {
  /// mpv track id (the same value PlayerAudioMenu shows as `index`).
  final int index;

  /// ISO-ish language tag when the container carries one ('hin', 'eng').
  final String? language;

  /// Human label — plenty of containers only tag the title, not `language`.
  final String? title;

  const AudioTrackOption({
    required this.index,
    this.language,
    this.title,
  });
}

abstract final class AudioTrackPreference {
  /// ISO 639 codes plus the spelled-out names addons actually ship.
  static const Set<String> _hindiTags = {'hin', 'hi', 'hindi'};
  static const Set<String> _englishTags = {'eng', 'en', 'english'};

  /// Pick the track to auto-select, or null to keep the player's own choice.
  ///
  /// Signal order (strongest first):
  ///   1. an explicit language tag on the track;
  ///   2. the language named in the track label;
  ///   3. English mode only — an entirely unlabelled track, which in
  ///      practice is the original audio rather than a dub.
  static int? pick({
    required List<AudioTrackOption> tracks,
    required bool hindi,
  }) {
    if (tracks.isEmpty) return null;

    // 1. Explicit language tag wins — no guessing.
    final wanted = hindi ? _hindiTags : _englishTags;
    for (final t in tracks) {
      final tag = _normalize(t.language);
      if (tag != null && wanted.contains(tag)) return t.index;
    }

    // 2. Fall back to the label when the container carries no tag.
    for (final t in tracks) {
      final label = (t.title ?? '').toLowerCase();
      if (label.isEmpty) continue;
      final hit = hindi
          ? label.contains('hindi')
          : (label.contains('english') || _hasEnglishToken(label));
      if (hit) return t.index;
    }

    // 3. Untagged + unlabelled track in English mode is the safest default
    //    (the original audio). Hindi mode stays hands-off here: an untagged
    //    track is exactly the case where guessing wrong is most likely.
    if (!hindi) {
      for (final t in tracks) {
        final untagged = (t.language ?? '').isEmpty && (t.title ?? '').isEmpty;
        if (untagged) return t.index;
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

  /// Bare 'en' token, but not 'end credits' / 'enhanced'.
  static bool _hasEnglishToken(String label) =>
      RegExp(r'\ben\b').hasMatch(label);
}
