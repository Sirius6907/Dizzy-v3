/// F4 — the room queue: "what do we watch next?"
///
/// Two people, one TV, and no arguing. Everyone can throw a title in and
/// everyone gets one vote; the most-wanted title plays next.
///
/// The queue is an **op-log**, not a snapshot, because four people tapping
/// at once must not clobber each other. Each tap is one op; applying the
/// same ops in the same order always lands on the same queue. That makes
/// the whole thing testable without a network and makes a dropped or
/// duplicated op harmless — a duplicate [add] is a no-op by id.
///
/// Pure: no Flutter, no storage, no timers. The widget asks, it does not
/// decide.
library;

/// What a single tap asked for.
enum QueueOpType { add, move, remove }

/// One tap, as it travels between phones.
class QueueOp {
  final QueueOpType type;
  final String itemId;

  /// Where the item should sit. Only read for [QueueOpType.move].
  final int index;

  /// Who tapped. Used only to keep one vote per person.
  final String voterId;

  /// Monotonic per room, so ops can be ordered even if two arrive at once.
  final int seq;

  const QueueOp({
    required this.type,
    required this.itemId,
    required this.voterId,
    required this.seq,
    this.index = 0,
  });

  /// A vote is only counted once per person, so a double tap cannot make
  /// one person's taste outweigh three other people's.
  bool get valid {
    if (itemId.isEmpty || voterId.isEmpty) return false;
    if (seq < 0) return false;
    if (type == QueueOpType.move && index < 0) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'itemId': itemId,
        'index': index,
        'voterId': voterId,
        'seq': seq,
      };

  /// A row we cannot read is dropped by the caller rather than applied
  /// half-way — a corrupt op must not shuffle somebody's queue.
  static QueueOp? fromJson(Map<String, dynamic> json) {
    final type = switch (json['type']?.toString()) {
      'add' => QueueOpType.add,
      'move' => QueueOpType.move,
      'remove' => QueueOpType.remove,
      _ => null,
    };
    if (type == null) return null;
    final itemId = json['itemId']?.toString() ?? '';
    final voterId = json['voterId']?.toString() ?? '';
    final index = json['index'];
    final seq = json['seq'];
    if (itemId.isEmpty || voterId.isEmpty) return null;
    return QueueOp(
      type: type,
      itemId: itemId,
      voterId: voterId,
      seq: seq is int ? seq : int.tryParse(seq?.toString() ?? '') ?? -1,
      index: index is int ? index : int.tryParse(index?.toString() ?? '') ?? 0,
    );
  }
}

/// One row of the queue.
class QueueEntry {
  final String itemId;
  final String title;
  final String addedBy;

  /// Who has voted for it. A `Set` so one person is counted once.
  final Set<String> voters;

  /// The [QueueOp.seq] of the add that put this title in. Ties are broken
  /// by this, so a title suggested earlier plays first — the fair answer,
  /// and a stable one: two phones showing the same room always agree.
  final int addedSeq;

  const QueueEntry({
    required this.itemId,
    required this.title,
    required this.addedBy,
    this.voters = const {},
    this.addedSeq = 0,
  });

  /// One vote per person.
  int get votes => voters.length;

  /// Most votes first; then the earliest suggestion; then the id, purely
  /// so the order is total and can never flicker between two phones.
  int compareTo(QueueEntry other) {
    if (votes != other.votes) return other.votes.compareTo(votes);
    final byAge = addedSeq.compareTo(other.addedSeq);
    return byAge != 0 ? byAge : itemId.compareTo(other.itemId);
  }

  QueueEntry copyWith({Set<String>? voters}) => QueueEntry(
        itemId: itemId,
        title: title,
        addedBy: addedBy,
        voters: voters ?? this.voters,
        addedSeq: addedSeq,
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'title': title,
        'addedBy': addedBy,
        'voters': voters.toList(),
        'addedSeq': addedSeq,
      };

  static QueueEntry? fromJson(Map<String, dynamic> json) {
    final itemId = json['itemId']?.toString() ?? '';
    if (itemId.isEmpty) return null;
    final raw = json['voters'];
    final seq = json['addedSeq'];
    return QueueEntry(
      itemId: itemId,
      title: json['title']?.toString() ?? '',
      addedBy: json['addedBy']?.toString() ?? '',
      voters: raw is List
          ? {
              for (final v in raw)
                if ((v?.toString() ?? '').isNotEmpty) v.toString()
            }
          : <String>{},
      addedSeq: seq is int ? seq : int.tryParse(seq?.toString() ?? '') ?? 0,
    );
  }
}

/// The queue rules.
abstract final class QueueVotePolicy {
  /// Titles one room can hold. Past this, the room is a planning meeting.
  static const int maxItems = 50;

  /// Apply one op to [entries]. Returns the new list.
  ///
  /// - [QueueOpType.add] adds the title and counts the tapper's vote. A
  ///   title that is already queued is not duplicated — the tap just adds
  ///   a vote.
  /// - [QueueOpType.move] lifts a title to [QueueOp.index]. Out-of-range
  ///   targets clamp to the ends, never throw.
  /// - [QueueOpType.remove] drops the title. Removing something that is not
  ///   there changes nothing.
  ///
  /// An invalid op returns the list unchanged.
  static List<QueueEntry> apply(List<QueueEntry> entries, QueueOp op) {
    if (!op.valid) return entries;

    switch (op.type) {
      case QueueOpType.add:
        final at = entries.indexWhere((e) => e.itemId == op.itemId);
        if (at != -1) {
          // Already queued: this tap is a vote, not a duplicate row.
          final next = List<QueueEntry>.from(entries);
          next[at] = next[at].copyWith(
            voters: {...next[at].voters, op.voterId},
          );
          return _sorted(next);
        }
        if (entries.length >= maxItems) return entries;
        return _sorted([
          ...entries,
          QueueEntry(
            itemId: op.itemId,
            title: op.itemId,
            addedBy: op.voterId,
            voters: {op.voterId},
            addedSeq: op.seq,
          ),
        ]);

      case QueueOpType.move:
        final at = entries.indexWhere((e) => e.itemId == op.itemId);
        if (at == -1) return entries;
        final next = List<QueueEntry>.from(entries)..removeAt(at);
        final target = op.index.clamp(0, next.length);
        next.insert(target, entries[at]);
        return next;

      case QueueOpType.remove:
        return entries.where((e) => e.itemId != op.itemId).toList();
    }
  }

  /// Apply a whole op-log in order. Ops are sorted by [QueueOp.seq] first
  /// so two phones that received the same taps in a different order still
  /// end up with the same queue.
  static List<QueueEntry> applyAll(List<QueueEntry> entries, List<QueueOp> ops) {
    final ordered = List<QueueOp>.from(ops)
      ..sort((a, b) {
        final bySeq = a.seq.compareTo(b.seq);
        return bySeq != 0 ? bySeq : a.itemId.compareTo(b.itemId);
      });
    var out = entries;
    for (final op in ordered) {
      out = apply(out, op);
    }
    return out;
  }

  static List<QueueEntry> _sorted(List<QueueEntry> entries) =>
      entries.toList()..sort((a, b) => a.compareTo(b));

  /// The title that plays next, or `null` when nobody has queued anything.
  ///
  /// Ties are broken by [QueueEntry.compareTo], never by wall-clock time,
  /// so two phones do not disagree about what is on next.
  static QueueEntry? next(List<QueueEntry> entries) =>
      entries.isEmpty ? null : _sorted(entries).first;

  /// Everyone's votes rolled into one count.
  static Map<String, int> tally(List<QueueEntry> entries) =>
      {for (final e in entries) e.itemId: e.votes};

  /// True when [voterId] has already voted for [itemId].
  static bool hasVoted(List<QueueEntry> entries, String itemId, String voterId) =>
      entries.any((e) => e.itemId == itemId && e.voters.contains(voterId));

  /// The line under the queue. Easy English, real numbers only.
  static String summaryLine(List<QueueEntry> entries) {
    if (entries.isEmpty) return 'Nobody picked anything yet.';
    final n = entries.length;
    final titles = n == 1 ? '1 title is' : '$n titles are';
    return '$titles waiting. Most wanted plays next.';
  }

  /// Round-trip a queue through JSON, dropping unreadable rows.
  static List<QueueEntry> decodeList(dynamic raw) {
    if (raw is! List) return [];
    final out = <QueueEntry>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final entry = QueueEntry.fromJson(Map<String, dynamic>.from(e));
      if (entry != null) out.add(entry);
    }
    return out;
  }
}
