import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/cloud/watch_party_service.dart';
import 'package:dizzy/services/social/dizzy_friend_service.dart';
import 'package:dizzy/services/social/dizzy_group_service.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
import 'package:dizzy/services/push/active_thread.dart';
import 'package:dizzy/widgets/prism/prism_card.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';

import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/notify.dart';
import '../settings/watch_party_page.dart';

/// Loads a group's history. Injectable for tests.
typedef GroupHistoryLoader =
    Future<List<DizzyGroupMessage>> Function(String groupId);

/// Sends a group message. Injectable for tests.
typedef GroupSender =
    Future<bool> Function({
      required String groupId,
      required String body,
      String kind,
      String? mediaRef,
    });

/// Group chat — text + Watch Together cards, live roster, join code.
///
/// Same discipline as [DirectMessagePage]: history + realtime share one
/// source of truth, ids dedupe, and every failure keeps the screen usable.
class GroupChatPage extends StatefulWidget {
  const GroupChatPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.memberCount = 0,
    this.isOwner = false,
    this.loadHistory,
    this.send,
  });

  final String groupId;
  final String groupName;
  final int memberCount;
  final bool isOwner;

  /// Test seams. Default to the live service.
  final GroupHistoryLoader? loadHistory;
  final GroupSender? send;

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<DizzyGroupMessage> _messages = [];

  /// History, realtime and retries can all deliver the same row.
  final Set<String> _knownIds = {};

  List<DizzyGroupMember> _roster = const [];
  String? _myUid;
  bool _sending = false;
  bool _partyBusy = false;

  RealtimeChannel? _channel;
  RealtimeChannel? _rosterChannel;

  @override
  void initState() {
    super.initState();
    _myUid = DizzyFriendService.myUid;
    ActiveThread.enter('group:${widget.groupId}');
    DizzySocialService.resolvedNames.addListener(_onNamesResolved);
    unawaited(_loadHistory());
    unawaited(_loadRoster());
    _subscribe();
  }

  void _onNamesResolved() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    if (widget.groupId.isEmpty) return;
    final loader = widget.loadHistory ?? DizzyGroupService.loadMessages;
    final history = await loader(widget.groupId);
    if (!mounted || history.isEmpty) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(history);
      for (final m in _messages) {
        _remember(m);
      }
    });
    unawaited(
      DizzyGroupService.resolveNames(history.map((m) => m.senderId)),
    );
    _scrollToEnd();
  }

  Future<void> _loadRoster() async {
    final roster = await DizzyGroupService.loadRoster(widget.groupId);
    if (!mounted) return;
    setState(() => _roster = roster);
    unawaited(
      DizzyGroupService.resolveNames(roster.map((m) => m.userId)),
    );
  }

  void _subscribe() {
    if (_channel != null || widget.groupId.isEmpty) return;
    _channel = DizzyGroupService.subscribeToMessages(
      widget.groupId,
      onMessage: (m) {
        if (!mounted || _isDuplicate(m)) return;
        _remember(m);
        setState(() => _messages.add(m));
        unawaited(DizzyGroupService.resolveNames([m.senderId]));
        _scrollToEnd();
      },
    );
    _rosterChannel = DizzyGroupService.subscribeToRoster(
      widget.groupId,
      onChanged: () => unawaited(_loadRoster()),
    );
  }

  void _remember(DizzyGroupMessage m) {
    if (m.id.isNotEmpty) _knownIds.add('id:${m.id}');
    if (m.clientMsgId.isNotEmpty) _knownIds.add('cmid:${m.clientMsgId}');
  }

  bool _isDuplicate(DizzyGroupMessage m) =>
      (m.id.isNotEmpty && _knownIds.contains('id:${m.id}')) ||
      (m.clientMsgId.isNotEmpty &&
          _knownIds.contains('cmid:${m.clientMsgId}'));

  @override
  void dispose() {
    ActiveThread.leave('group:${widget.groupId}');
    final channel = _channel;
    final roster = _rosterChannel;
    _channel = null;
    _rosterChannel = null;
    DizzySocialService.resolvedNames.removeListener(_onNamesResolved);
    if (CloudClient.isReady) {
      if (channel != null) unawaited(CloudClient.db.removeChannel(channel));
      if (roster != null) unawaited(CloudClient.db.removeChannel(roster));
    }
    _textController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  // ── Sending ──────────────────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;
    final ok = await _sendRaw(body: text);
    if (!mounted) return;
    if (ok) {
      _textController.clear();
    } else {
      DizzyNotify.show(
        context,
        "Couldn't send yet — check net, then try again.",
        tone: NotifyTone.warn,
      );
    }
  }

  /// One send path for text and media cards. Keeps the typed text on failure
  /// so nothing the user wrote is ever silently lost.
  Future<bool> _sendRaw({
    required String body,
    String kind = 'text',
    String? mediaRef,
  }) async {
    if (_sending) return false;
    setState(() => _sending = true);
    final sender = widget.send ?? DizzyGroupService.sendMessage;
    final ok = await sender(
      groupId: widget.groupId,
      body: body,
      kind: kind,
      mediaRef: mediaRef,
    );
    if (mounted) setState(() => _sending = false);
    return ok;
  }

  // ── Watch Together ───────────────────────────────────────────────

  Future<void> _startWatchTogether() async {
    if (_partyBusy) return;
    if (!WatchPartyService.isAvailable) {
      DizzyNotify.show(
        context,
        'Watch Together needs net + sign-in. Then try again.',
        tone: NotifyTone.warn,
      );
      return;
    }
    setState(() => _partyBusy = true);
    try {
      final room = await WatchPartyService.createRoom(
        title: 'Watching with ${widget.groupName}',
        isPrivate: false,
      );
      if (!mounted) return;
      if (room == null) {
        DizzyNotify.show(
          context,
          "Couldn't start the room — check net, then try again.",
          tone: NotifyTone.warn,
        );
        return;
      }
      final sent = await _sendRaw(
        body: 'Join my Watch Together room: ${room.roomId}',
        kind: 'media_card',
        mediaRef: 'party:${room.roomId}',
      );
      if (!mounted) return;
      DizzyNotify.show(
        context,
        sent
            ? 'Room ${room.roomId} is live — invite posted!'
            : 'Room is live — invite could not post, share the code.',
        tone: sent ? NotifyTone.success : NotifyTone.warn,
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WatchPartyPage()),
      );
    } finally {
      if (mounted) setState(() => _partyBusy = false);
    }
  }

  /// Card tap: join the room it names, or spin one up and invite back.
  Future<void> _watchTogetherFromCard(DizzyGroupMessage msg) async {
    if (_partyBusy) return;
    if (!WatchPartyService.isAvailable) {
      DizzyNotify.show(
        context,
        'Watch Together needs net + sign-in. Then try again.',
        tone: NotifyTone.warn,
      );
      return;
    }
    setState(() => _partyBusy = true);
    try {
      final ref = (msg.mediaRef ?? '').trim();
      if (ref.startsWith('party:')) {
        final roomId = ref.substring('party:'.length).trim();
        final room = await WatchPartyService.joinRoom(roomId: roomId);
        if (!mounted) return;
        if (room == null) {
          DizzyNotify.show(
            context,
            "Couldn't join — the room may have ended.",
            tone: NotifyTone.warn,
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WatchPartyPage()),
        );
        return;
      }
      await _startWatchTogether();
    } finally {
      if (mounted) setState(() => _partyBusy = false);
    }
  }

  // ── Roster ───────────────────────────────────────────────────────

  Future<void> _openRoster() async {
    await _loadRoster();
    if (!mounted) return;
    final left = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RosterSheet(
        groupId: widget.groupId,
        groupName: widget.groupName,
        isOwner: widget.isOwner,
        roster: _roster,
        myUid: _myUid,
      ),
    );
    if (!mounted) return;
    if (left == true) {
      Navigator.of(context).pop();
      return;
    }
    unawaited(_loadRoster());
  }

  // ── Bubbles ──────────────────────────────────────────────────────

  Widget _mediaCardBubble(DizzyGroupMessage msg, bool isMe) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    final ref = msg.mediaRef ?? '';
    final isPartyInvite = ref.startsWith('party:');
    final roomCode =
        isPartyInvite ? ref.substring('party:'.length).trim() : null;
    final title = isPartyInvite
        ? 'Watch Together'
        : (msg.body.isNotEmpty ? msg.body : 'Media invite');
    final sub = isPartyInvite
        ? 'Room $roomCode — tap to join.'
        : 'Tap to watch together.';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: DizzySpace.xs),
        child: PrismCard(
          padding: const EdgeInsets.all(DizzySpace.sm),
          glowColor: DizzyGlow.beam,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: well,
                      border: Border.all(color: hairline),
                    ),
                    child: const Center(
                      child: Text('🎬', style: TextStyle(fontSize: 28)),
                    ),
                  ),
                  const SizedBox(width: DizzySpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sub,
                          style: TextStyle(color: inkSoft, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DizzySpace.sm),
              DizzyTactileButton(
                height: 38,
                gradient: DizzyGradients.emberButton,
                glowColor: DizzyGlow.red,
                onTap: _partyBusy ? null : () => _watchTogetherFromCard(msg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _partyBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                    const SizedBox(width: 6),
                    Text(
                      _partyBusy
                          ? 'Working...'
                          : (isPartyInvite ? 'Join room' : 'Watch Together'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textBubble(DizzyGroupMessage msg, bool isMe) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final panel = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);
    final name = DizzyGroupService.memberNameFor(msg.senderId);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: DizzySpace.xxs),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(
                  left: DizzySpace.xs,
                  bottom: 3,
                ),
                child: Text(
                  '@${isMe ? 'you' : name} · ${_clock(msg.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: inkSoft,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DizzySpace.md,
                vertical: DizzySpace.sm,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                gradient: isMe ? DizzyGradients.emberButton : null,
                color: isMe ? null : panel,
                border: isMe ? null : Border.all(color: hairline),
                boxShadow: [
                  BoxShadow(
                    color: isMe
                        ? DizzyGlow.red.withValues(alpha: 0.25)
                        : Colors.black.withValues(
                            alpha: isLight ? 0.08 : 0.40,
                          ),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                msg.body,
                style: TextStyle(
                  color: isMe ? Colors.white : ink,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(DateTime at) {
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m ${at.hour < 12 ? 'am' : 'pm'}';
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final panel = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    final memberCount = _roster.isNotEmpty ? _roster.length : widget.memberCount;

    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: panel,
              child: Text(
                widget.groupName.isNotEmpty
                    ? widget.groupName[0].toUpperCase()
                    : '#',
                style: TextStyle(color: ink, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: DizzySpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    memberCount == 1 ? '1 member' : '$memberCount members',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: inkSoft, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Watch Together',
            onPressed: _partyBusy ? null : _startWatchTogether,
            icon: Icon(Icons.movie_filter_rounded, color: ink),
          ),
          IconButton(
            tooltip: 'Members',
            onPressed: _openRoster,
            icon: Icon(Icons.people_alt_rounded, color: ink),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _emptyChat(ink, inkSoft)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(DizzySpace.md),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, index) {
                      final msg = _messages[index];
                      final isMe =
                          _myUid != null && msg.senderId == _myUid;
                      if (msg.kind == 'media_card') {
                        return _mediaCardBubble(msg, isMe);
                      }
                      return _textBubble(msg, isMe);
                    },
                  ),
          ),
          // Composer
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DizzySpace.sm,
              vertical: DizzySpace.xs,
            ),
            decoration: BoxDecoration(
              color: palette.scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: hairline)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DizzySpace.sm,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: well,
                        border: Border.all(color: hairline),
                      ),
                      child: TextField(
                        controller: _textController,
                        style: TextStyle(color: ink, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Message the group...',
                          hintStyle: TextStyle(color: inkSoft, fontSize: 13),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendText(),
                      ),
                    ),
                  ),
                  const SizedBox(width: DizzySpace.xs),
                  Tooltip(
                    message: 'Send message',
                    child: DizzyTactileButton(
                      width: 48,
                      height: 48,
                      padding: EdgeInsets.zero,
                      gradient: DizzyGradients.emberButton,
                      glowColor: DizzyGlow.red,
                      borderRadius: BorderRadius.circular(24),
                      onTap: _sending ? null : _sendText,
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyChat(Color ink, Color inkSoft) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DizzySpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👋', style: TextStyle(fontSize: 34)),
            const SizedBox(height: DizzySpace.sm),
            Text(
              'Say hi to ${widget.groupName}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: DizzySpace.xxs),
            Text(
              'Messages show up here for everyone in the group.',
              textAlign: TextAlign.center,
              style: TextStyle(color: inkSoft, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Roster + join code + leave/delete, in one sheet.
class _RosterSheet extends StatefulWidget {
  const _RosterSheet({
    required this.groupId,
    required this.groupName,
    required this.isOwner,
    required this.roster,
    required this.myUid,
  });

  final String groupId;
  final String groupName;
  final bool isOwner;
  final List<DizzyGroupMember> roster;
  final String? myUid;

  @override
  State<_RosterSheet> createState() => _RosterSheetState();
}

class _RosterSheetState extends State<_RosterSheet> {
  bool _busy = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.groupId));
    if (!mounted) return;
    DizzyNotify.show(context, 'Code copied!', tone: NotifyTone.success);
  }

  Future<void> _confirmLeave() async {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            AppThemeService.currentPalette.value.scaffoldBackgroundColor,
        title: Text(
          widget.isOwner ? 'Delete group?' : 'Leave group?',
          style: TextStyle(
            color: isLight ? PrismLight.ink : Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          widget.isOwner
              ? 'You own this group. Deleting removes it for everyone.'
              : 'You can rejoin later with the group code.',
          style: TextStyle(color: inkSoft, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: inkSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              widget.isOwner ? 'Delete' : 'Leave',
              style: const TextStyle(
                color: DizzyGlow.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final done = await DizzyGroupService.leaveGroup(widget.groupId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!done) {
      DizzyNotify.show(
        context,
        "Couldn't do that right now — check net, then try again.",
        tone: NotifyTone.warn,
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final panel = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.only(top: DizzySpace.xxl),
      decoration: BoxDecoration(
        color: palette.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DizzyRadius.xl),
        ),
        border: Border.all(color: hairline),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: DizzySpace.xs),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DizzySpace.md,
                DizzySpace.md,
                DizzySpace.md,
                DizzySpace.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.groupName} · members',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.roster.length}',
                    style: TextStyle(
                      color: inkSoft,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // Join code row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DizzySpace.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DizzySpace.sm,
                  vertical: DizzySpace.xs,
                ),
                decoration: BoxDecoration(
                  color: well,
                  borderRadius: BorderRadius.circular(DizzyRadius.md),
                  border: Border.all(color: hairline),
                ),
                child: Row(
                  children: [
                    Icon(Icons.key_rounded, size: 16, color: inkSoft),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        widget.groupId,
                        maxLines: 1,
                        style: TextStyle(
                          color: ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _copyCode,
                      child: const Text(
                        'Copy',
                        style: TextStyle(
                          color: DizzyGlow.red,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: DizzySpace.xs),
            Flexible(
              child: widget.roster.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(DizzySpace.lg),
                      child: Text(
                        'Member list is loading…',
                        style: TextStyle(color: inkSoft, fontSize: 12.5),
                      ),
                    )
                  : ValueListenableBuilder<Map<String, String>>(
                      valueListenable: DizzySocialService.resolvedNames,
                      builder: (c, _, __) {
                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: DizzySpace.md,
                          ),
                          itemCount: widget.roster.length,
                          itemBuilder: (c, i) {
                            final m = widget.roster[i];
                            final me = m.userId == widget.myUid;
                            final name =
                                DizzyGroupService.memberNameFor(m.userId);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: DizzySpace.xs,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: panel,
                                    child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: ink,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: DizzySpace.sm),
                                  Expanded(
                                    child: Text(
                                      me ? '@$name (you)' : '@$name',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: ink,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (m.role == 'owner')
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: DizzyGlow.gold.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          DizzyRadius.pill,
                                        ),
                                      ),
                                      child: const Text(
                                        'Owner',
                                        style: TextStyle(
                                          color: DizzyGlow.gold,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(DizzySpace.md),
              child: DizzyTactileButton(
                height: 44,
                width: double.infinity,
                onTap: _busy ? null : _confirmLeave,
                border: BorderSide(
                  color: DizzyGlow.red.withValues(alpha: 0.5),
                ),
                child: Text(
                  _busy
                      ? 'Working...'
                      : (widget.isOwner ? 'Delete group' : 'Leave group'),
                  style: const TextStyle(
                    color: DizzyGlow.red,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
