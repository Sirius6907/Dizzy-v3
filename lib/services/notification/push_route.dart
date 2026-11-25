/// v1.4 item 5 — where a notification tap should land.
///
/// Pure and I/O-free so the whole mapping is unit-tested without a platform
/// channel: the FCM data blob goes in, one target comes out. The service layer
/// only turns the result into a `Navigator.push`.
library;

/// The screens a push can open. [none] means "recorded, nothing to open" —
/// the banner still appears, the tap just closes the shade.
enum PushTarget { none, title, dm, group, room, update }

/// One tap destination.
///
/// [threadId] is the id that screen needs: a uid for [PushTarget.dm], a group
/// id for [PushTarget.group], a room code for [PushTarget.room] and an entity
/// id for [PushTarget.title]. [threadKey] is the same thing namespaced, so
/// "is this thread already on screen?" never confuses a uid with a group id.
class PushRoute {
  const PushRoute({
    required this.target,
    this.threadId = '',
    this.label = '',
    this.avatar = '',
    this.poster = '',
  });

  final PushTarget target;
  final String threadId;

  /// Human name for the destination's app bar: sender, group or room name.
  final String label;

  /// Sender avatar url (dm) — shown as the chat header chip.
  final String avatar;

  /// Poster url (title) — carried so the banner image and details agree.
  final String poster;

  bool get opens => target != PushTarget.none;

  bool get isSocial =>
      target == PushTarget.dm ||
      target == PushTarget.group ||
      target == PushTarget.room;

  /// Stable identity for "already open" suppression.
  String get threadKey => switch (target) {
    PushTarget.dm => threadId,
    PushTarget.group => 'group:$threadId',
    PushTarget.room => 'room:$threadId',
    PushTarget.title => 'title:$threadId',
    PushTarget.update => 'update',
    PushTarget.none => '',
  };

  /// Semantic name, useful in logs and tests (`route:dm`, `route:group`, …).
  String get routeName => switch (target) {
    PushTarget.dm => 'route:dm',
    PushTarget.group => 'route:group',
    PushTarget.room => 'route:room',
    PushTarget.title => 'route:title',
    PushTarget.update => 'route:update',
    PushTarget.none => 'route:none',
  };

  /// The one mapping every caller shares.
  ///
  /// Priority is deliberately "most specific first": a chat push that also
  /// carries a title id must open the chat, not the title, because the person
  /// tapped a message. Room invites outrank title links for the same reason.
  ///
  /// `kind=updates` (the update campaign) outranks a bare title id but not a
  /// chat: v1.3.7 shipped "Update available" pushes with no destination at
  /// all, so tapping one only foregrounded Dizzy. It now opens the Updates
  /// screen, which is the one place that can start the download.
  static PushRoute resolve({
    Object? senderUid,
    Object? senderName,
    Object? avatar,
    Object? groupId,
    Object? groupName,
    Object? roomCode,
    Object? entityId,
    Object? poster,
    Object? kind,
  }) {
    final uid = _trim(senderUid, 64);
    final gid = _trim(groupId, 64);
    final code = _trim(roomCode, 16).toUpperCase();
    final entity = _trim(entityId, 64);
    final name = _trim(senderName, 80);
    final group = _trim(groupName, 80);
    if (uid.isNotEmpty) {
      return PushRoute(
        target: PushTarget.dm,
        threadId: uid,
        label: name,
        avatar: _trim(avatar, 500),
      );
    }
    if (gid.isNotEmpty) {
      return PushRoute(
        target: PushTarget.group,
        threadId: gid,
        label: group.isEmpty ? name : group,
        avatar: _trim(avatar, 500),
      );
    }
    if (code.isNotEmpty) {
      return PushRoute(
        target: PushTarget.room,
        threadId: code,
        label: group.isEmpty ? name : group,
      );
    }
    final k = _trim(kind, 24).toLowerCase();
    if (k == 'updates' || k == 'update') {
      return const PushRoute(target: PushTarget.update);
    }
    if (entity.isNotEmpty) {
      return PushRoute(
        target: PushTarget.title,
        threadId: entity,
        label: name,
        poster: _trim(poster, 500),
      );
    }
    return const PushRoute(target: PushTarget.none);
  }

  /// Decode from a raw FCM data blob, a local-banner payload or a stored inbox
  /// item. Accepts `null` and unknown keys without throwing.
  factory PushRoute.fromData(Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return PushRoute.resolve(
      senderUid: d['sender_uid'],
      senderName: d['sender_name'],
      avatar: d['avatar'],
      groupId: d['group_id'],
      groupName: d['group_name'],
      roomCode: d['room_code'],
      entityId: d['entity_id'],
      poster: d['poster'],
      kind: d['kind'],
    );
  }

  /// Same wire keys [fromData] reads — what [PushRoute] itself would send.
  Map<String, String> toData() {
    final out = <String, String>{};
    switch (target) {
      case PushTarget.dm:
        out['sender_uid'] = threadId;
        if (label.isNotEmpty) out['sender_name'] = label;
        if (avatar.isNotEmpty) out['avatar'] = avatar;
      case PushTarget.group:
        out['group_id'] = threadId;
        if (label.isNotEmpty) out['group_name'] = label;
      case PushTarget.room:
        out['room_code'] = threadId;
        if (label.isNotEmpty) out['group_name'] = label;
      case PushTarget.title:
        out['entity_id'] = threadId;
        if (poster.isNotEmpty) out['poster'] = poster;
      case PushTarget.update:
        out['kind'] = 'updates';
      case PushTarget.none:
        break;
    }
    return out;
  }

  @override
  String toString() => 'PushRoute($routeName, $threadId)';

  static String _trim(Object? raw, int max) {
    if (raw == null) return '';
    final s = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length <= max ? s : s.substring(0, max).trimRight();
  }
}
