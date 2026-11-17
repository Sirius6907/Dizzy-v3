import '../../models/stream/stream_model.dart';

/// The owner's anime rule (2026-11-15): anime is watched either with the
/// ORIGINAL audio plus ENGLISH subtitles, or in the ENGLISH dub. A Hindi
/// dub is not an anime option, so those sources are never offered.
enum AnimeAudioBucket {
  /// original audio (English subtitles may or may not be listed)
  originalWithEnglishSubs,

  /// English dub
  englishDub,

  /// Hindi dub - never offered for anime
  hindiDub,

  /// something else (unknown audio)
  other,
}

/// Classify one anime source into its audio bucket.
///
/// [mediaTitle] is passed through to [StreamSource.hasAudioLanguage] so a
/// title that contains a language word ("Hindi Medium") cannot tag every
/// source of that show.
AnimeAudioBucket animeAudioBucket(StreamSource source, {String? mediaTitle}) {
  final text = '${source.name ?? ''} ${source.description ?? ''}'.toLowerCase();
  final isHindi = source.hasAudioLanguage('hindi', mediaTitle: mediaTitle);
  final isEnglish = source.hasAudioLanguage('english', mediaTitle: mediaTitle);
  final mentionsDub = text.contains('dub');
  if (mentionsDub) {
    if (isHindi) return AnimeAudioBucket.hindiDub;
    if (isEnglish) return AnimeAudioBucket.englishDub;
    // A release that only says "DUB" with no language is treated as the
    // English dub - that is the dub the anime sheet offers.
    return AnimeAudioBucket.englishDub;
  }
  if (isHindi) return AnimeAudioBucket.hindiDub;
  return AnimeAudioBucket.originalWithEnglishSubs;
}

/// Filters sources by the global dub mode BEFORE probing, so health
/// checks only run on Hindi-dub sources when Hindi mode is on.
///
/// [mediaTitle] is passed through to [StreamSource.hasAudioLanguage] so
/// the media title (e.g. a movie literally named "Hindi Medium") is
/// stripped from detection text and cannot tag every source as hindi.
///
/// English mode (`hindi: false`) returns the input list untouched.
List<StreamSource> filterByDubMode(
  List<StreamSource> sources, {
  required bool hindi,
  required String? mediaTitle,
}) {
  if (!hindi) return sources;
  return sources
      .where((s) => s.hasAudioLanguage('hindi', mediaTitle: mediaTitle))
      .toList();
}
