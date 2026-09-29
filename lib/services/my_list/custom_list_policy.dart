/// F3 — the rules for a hand-made list ("Best of 2026", "With Mum").
///
/// Pure on purpose: name rules, ordering, caps, and the per-profile
/// isolation key all live here so they can be tested without a screen.
/// The service in `custom_list_service.dart` only stores.
library;

/// One hand-made list. Items are the [MyListItem.uniqueKey] strings, so a
/// list never holds a copy of a title — it holds a pointer.
class CustomList {
  final String id;
  final String name;

  /// Item keys, newest first.
  final List<String> itemKeys;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomList({
    required this.id,
    required this.name,
    this.itemKeys = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  int get length => itemKeys.length;

  bool contains(String itemKey) => itemKeys.contains(itemKey);

  CustomList copyWith({
    String? name,
    List<String>? itemKeys,
    DateTime? updatedAt,
  }) =>
      CustomList(
        id: id,
        name: name ?? this.name,
        itemKeys: itemKeys ?? this.itemKeys,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'itemKeys': itemKeys,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// A row we cannot read is dropped rather than thrown on — one bad list
  /// must never hide the other lists of the same profile.
  static CustomList? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final raw = json['itemKeys'];
    final keys = <String>[];
    if (raw is List) {
      for (final k in raw) {
        final s = k?.toString() ?? '';
        // A blank key is junk: it can never be matched back to a title.
        if (s.isNotEmpty) keys.add(s);
      }
    }
    final created = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updated = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    return CustomList(
      id: id,
      name: name,
      itemKeys: keys,
      createdAt: created ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updated ?? created ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// The list rules, in one pure place.
abstract final class CustomListPolicy {
  /// Longest name we accept. Anything past this is a wall of text in a
  /// chip, so we cut it instead of letting the row wrap.
  static const int maxNameLength = 40;

  /// Lists per person. Enough to stay useful, small enough that the picker
  /// never becomes a second home screen.
  static const int maxLists = 20;

  /// Titles per list.
  static const int maxItemsPerList = 200;

  /// Clean a typed name: collapse spaces, cut at [maxNameLength].
  /// Returns `''` when nothing usable is left, so the caller can refuse.
  static String cleanName(String raw) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return '';
    return collapsed.length <= maxNameLength
        ? collapsed
        : collapsed.substring(0, maxNameLength).trim();
  }

  /// Two names are "the same" when they differ only by case or spacing —
  /// "Best Of 2026" and "best of 2026" are one list, not two.
  static bool sameName(String a, String b) =>
      cleanName(a).toLowerCase() == cleanName(b).toLowerCase();

  /// May this person create another list right now?
  static bool canCreate(List<CustomList> existing) =>
      existing.length < maxLists;

  /// A new list, inserted first, with a clean name. `null` when the name
  /// is unusable or the cap is reached — the caller shows an Easy English
  /// line and stops.
  static List<CustomList>? create(
    List<CustomList> existing, {
    required String id,
    required String name,
    DateTime? now,
  }) {
    final clean = cleanName(name);
    if (clean.isEmpty) return null;
    if (!canCreate(existing)) return null;
    if (existing.any((l) => sameName(l.name, clean))) return null;
    final at = now ?? DateTime.now();
    return [
      CustomList(id: id, name: clean, itemKeys: const [], createdAt: at, updatedAt: at),
      ...existing,
    ];
  }

  /// Rename in place, keeping the position and the items. `null` when the
  /// new name is unusable or it would collide with another list.
  static List<CustomList>? rename(
    List<CustomList> lists, {
    required String id,
    required String name,
    DateTime? now,
  }) {
    final clean = cleanName(name);
    if (clean.isEmpty) return null;
    final target = lists.where((l) => l.id == id).firstOrNull;
    if (target == null) return null;
    if (lists.any((l) => l.id != id && sameName(l.name, clean))) return null;
    final at = now ?? DateTime.now();
    return [
      for (final l in lists)
        if (l.id == id)
          l.copyWith(name: clean, updatedAt: at)
        else
          l,
    ];
  }

  /// Delete one list by id.
  static List<CustomList> delete(List<CustomList> lists, String id) =>
      lists.where((l) => l.id != id).toList();

  /// Add a title. Adding the same title twice is a no-op, so a double tap
  /// cannot create a ghost entry.
  static List<CustomList>? addItem(
    List<CustomList> lists, {
    required String listId,
    required String itemKey,
    DateTime? now,
  }) {
    final target = lists.where((l) => l.id == listId).firstOrNull;
    if (target == null) return null;
    if (itemKey.isEmpty || target.contains(itemKey)) return null;
    if (target.length >= maxItemsPerList) return null;
    final at = now ?? DateTime.now();
    return [
      for (final l in lists)
        if (l.id == listId)
          l.copyWith(itemKeys: [itemKey, ...l.itemKeys], updatedAt: at)
        else
          l,
    ];
  }

  /// Remove a title from one list. Removing something that is not there
  /// returns the same list, so a stale tap is harmless.
  static List<CustomList> removeItem(
    List<CustomList> lists, {
    required String listId,
    required String itemKey,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return [
      for (final l in lists)
        if (l.id == listId && l.itemKeys.contains(itemKey))
          l.copyWith(
            itemKeys: l.itemKeys.where((k) => k != itemKey).toList(),
            updatedAt: at,
          )
        else
          l,
    ];
  }

  /// The keys this profile added — a title can live in many lists at once.
  static Set<String> keysIn(List<CustomList> lists, String listId) =>
      lists.where((l) => l.id == listId).firstOrNull?.itemKeys.toSet() ?? const {};
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
