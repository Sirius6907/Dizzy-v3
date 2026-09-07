import '../../models/stream/stream_model.dart';

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
