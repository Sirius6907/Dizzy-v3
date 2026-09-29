/// Pure queue math for the music player — no player, no audio, no I/O.
///
/// The queue drawer only ever sees the *upcoming* slice of the playlist
/// (everything after the current track), but `ReorderableListView` hands
/// back indices relative to that slice. These helpers own the
/// upcoming → absolute mapping so the contract is unit-testable without
/// booting the media backend.
class MusicQueueOps {
  MusicQueueOps._();

  /// Tracks after the current one, in play order.
  static List<T> upcoming<T>(List<T> playlist, int currentIndex) {
    if (playlist.isEmpty || currentIndex >= playlist.length - 1) return const [];
    return playlist.sublist(currentIndex + 1);
  }

  /// Tracks before the current one, in play order.
  static List<T> history<T>(List<T> playlist, int currentIndex) {
    if (currentIndex <= 0 || playlist.isEmpty) return const [];
    return playlist.sublist(0, currentIndex);
  }

  /// Moves one upcoming item to another position.
  ///
  /// [oldIndex] and [newIndex] are indices inside the upcoming slice, using
  /// the same convention as `ReorderableListView.onReorder` — `newIndex` is
  /// the insertion slot *before* the drag is removed, so a downward move is
  /// decremented by one. The current track and everything before it are never
  /// touched, and out-of-range drags are ignored instead of throwing.
  static List<T> reorderUpcoming<T>(
    List<T> playlist,
    int currentIndex, {
    required int oldIndex,
    required int newIndex,
  }) {
    final next = List<T>.from(playlist);
    if (currentIndex < 0 || currentIndex >= next.length - 1) return next;

    final upcomingStart = currentIndex + 1;
    final actualOld = upcomingStart + oldIndex;
    if (actualOld < upcomingStart || actualOld >= next.length) return next;

    var actualNew = upcomingStart + newIndex;
    if (actualOld < actualNew) actualNew -= 1;
    actualNew = actualNew.clamp(upcomingStart, next.length);

    final item = next.removeAt(actualOld);
    next.insert(actualNew, item);
    return next;
  }
}
