import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';
import 'package:dizzy/widgets/prism/prism_card.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
import 'package:dizzy/services/social/dizzy_friend_service.dart';
import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/cloud/watch_party_service.dart';
import 'package:dizzy/services/cloud/remote_config_service.dart';
import 'package:dizzy/services/messaging/dm_outbox.dart';
import '../../services/theme/app_theme_service.dart';
import '../settings/watch_party_page.dart';
import '../../widgets/common/notify.dart';

/// In-App Direct Message & Media Card Experience.
/// Pure OLED true-black, zero-lag 120 FPS message lists with one-tap Co-Experience join.
class DirectMessagePage extends StatefulWidget {
  final String recipientUid;
  final String recipientUsername;
  final String? recipientAvatar;

  const DirectMessagePage({
    super.key,
    required this.recipientUid,
    required this.recipientUsername,
    this.recipientAvatar,
  });

  @override
  State<DirectMessagePage> createState() => _DirectMessagePageState();
}

class _DirectMessagePageState extends State<DirectMessagePage> {
  final TextEditingController _textController = TextEditingController();
  final List<DizzyDirectMessage> _messages = [];
  /// Message identity dedupe — history load and realtime inserts can
  /// overlap, and the outbox retry path can re-deliver the same row.
  final Set<String> _knownIds = {};
  bool _isSending = false;
  bool _partyBusy = false;

  String? _myUid;
  String _threadId = '';
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _myUid = DizzyFriendService.myUid;
    _threadId = (_myUid != null && widget.recipientUid.isNotEmpty)
        ? DizzySocialService.getThreadId(_myUid!, widget.recipientUid)
        : '';
    unawaited(_loadHistory());
    // Phase E2: admin feature flag — DMs paused → Easy English line.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!RemoteConfigService.featureEnabled('dm')) {
        DizzyNotify.show(
          context,
          'Messages are paused for fixes right now. Back soon!',
          tone: NotifyTone.warn,
        );
      }
    });
  }

  /// Loads the real conversation from the server. The page previously
  /// showed only a hardcoded sample card — sends went to the DB but
  /// neither side ever saw them.
  Future<void> _loadHistory() async {
    if (_threadId.isEmpty) return;
    final history = await DizzySocialService.loadThreadMessages(_threadId);
    if (!mounted || history.isEmpty) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(history);
      for (final m in _messages) {
        _remember(m);
      }
    });
    _subscribe();
  }

  /// Live thread updates. Sends and receives now share one source of
  /// truth; dedupe keeps history + realtime + retries from doubling rows.
  void _subscribe() {
    if (_channel != null || _threadId.isEmpty || !CloudClient.isReady) return;
    _channel = DizzySocialService.subscribeToThread(
      _threadId,
      onMessage: (m) {
        if (_isDuplicate(m) || !mounted) return;
        _remember(m);
        setState(() => _messages.add(m));
      },
    );
  }

  void _remember(DizzyDirectMessage m) {
    if (m.id.isNotEmpty) _knownIds.add('id:${m.id}');
    if (m.clientMsgId.isNotEmpty) _knownIds.add('cmid:${m.clientMsgId}');
  }

  bool _isDuplicate(DizzyDirectMessage m) =>
      (m.id.isNotEmpty && _knownIds.contains('id:${m.id}')) ||
      (m.clientMsgId.isNotEmpty &&
          _knownIds.contains('cmid:${m.clientMsgId}'));

  @override
  void dispose() {
    final channel = _channel;
    _channel = null;
    if (channel != null && CloudClient.isReady) {
      unawaited(CloudClient.db.removeChannel(channel));
    }
    _textController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    // Phase E2: admin feature flag — never queue into a dead channel.
    if (!RemoteConfigService.featureEnabled('dm')) {
      if (mounted) {
        DizzyNotify.show(
          context,
          'Messages are paused for fixes right now. Back soon!',
          tone: NotifyTone.warn,
        );
      }
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _textController.clear();

    // Phase K4: written to disk BEFORE the network attempt, so a process
    // kill mid-send leaves a record the next launch retries instead of a
    // message that silently disappears.
    final entry = await DmOutbox.enqueue(
      recipientUid: widget.recipientUid,
      recipientUsername: widget.recipientUsername,
      body: text,
    );

    final success = await DizzySocialService.sendDirectMessage(
      recipientUid: widget.recipientUid,
      body: text,
    );

    if (success) {
      await DmOutbox.markSent(entry.id);
      if (mounted) setState(() => _isSending = false);
      // Server is the source of truth — realtime delivers the real row.
      // (Optimistic echo removed: a fail-soft add here used to show a
      // message that was never sent, with no way to retry it.)
      return;
    }

    // Still queued: the outbox scheduler keeps trying, the pending bar
    // above the composer shows it, and tapping it retries immediately.
    await DmOutbox.recordFailure(entry.id);
    if (!mounted) return;
    setState(() => _isSending = false);
    DizzyNotify.show(
      context,
      "Couldn't send yet — saved, Dizzy will keep trying.",
      tone: NotifyTone.warn,
    );
  }

  /// Phase K4 — the retry surface for messages still in the outbox for
  /// this conversation. Tapping retries right now; otherwise the scheduler
  /// retries on its own.
  Future<void> _retryPending() async {
    await DmOutbox.flush(
      send: (e) => DizzySocialService.sendDirectMessage(
        recipientUid: e.recipientUid,
        body: e.body,
      ),
    );
  }

  Widget _pendingBar() {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final gold = isLight ? PrismAccent.starTextLight : DizzyGlow.gold;
    return ValueListenableBuilder<List<OutboxEntry>>(
      valueListenable: DmOutbox.entries,
      builder: (context, list, _) {
        final mine = DmOutbox.forRecipient(list, widget.recipientUid);
        if (mine.isEmpty) return const SizedBox.shrink();
        return InkWell(
          onTap: _retryPending,
          child: Container(
            margin: const EdgeInsets.fromLTRB(
              DizzySpace.md,
              DizzySpace.xs,
              DizzySpace.md,
              0,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: DizzySpace.sm,
              vertical: DizzySpace.xs,
            ),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DizzyRadius.sm),
              border: Border.all(color: gold.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mine.length == 1
                        ? '1 message not sent yet — tap to retry now'
                        : '${mine.length} messages not sent yet — tap to retry',
                    style: TextStyle(
                      color: gold,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.refresh_rounded, size: 14, color: gold),
              ],
            ),
          ),
        );
      },
    );
  }

  /// DM media card → real Watch Together.
  ///
  /// Room invite (`mediaRef: 'party:CODE'`) → join THAT room — tapping
  /// your friend's invite must take you to their room, not spin up a new
  /// one. Any other card → create a fresh room and send the invite back.
  Future<void> _watchTogetherFromCard(DizzyDirectMessage msg) async {
    if (_partyBusy) return;
    if (!WatchPartyService.isAvailable) {
      if (!mounted) return;
      DizzyNotify.show(
        context,
        'Watch Together needs net + sign-in. Then try again.',
        tone: NotifyTone.warn,
      );
      return;
    }
    setState(() => _partyBusy = true);
    try {
      final ref = (msg.mediaRef != null && msg.mediaRef!.isNotEmpty)
          ? msg.mediaRef!
          : 'dm:${widget.recipientUsername}';

      // Friend's invite: join their live room.
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
        DizzyNotify.show(
          context,
          'Joined room ${room.roomId} 🎬',
          tone: NotifyTone.success,
        );
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WatchPartyPage()));
        return;
      }

      final room = await WatchPartyService.createRoom(
        title: 'Watching with @${widget.recipientUsername}',
        isPrivate: false,
      );
      if (room == null) {
        if (!mounted) return;
        DizzyNotify.show(
          context,
          "Couldn't start the room — check net, then try again.",
          tone: NotifyTone.warn,
        );
        return;
      }
      await WatchPartyService.updateCurrentMedia(
        roomId: room.roomId,
        ref: ref,
        title: msg.body,
      );
      await DizzySocialService.sendDirectMessage(
        recipientUid: widget.recipientUid,
        body: 'Join my Watch Together room: ${room.roomId}',
        kind: 'media_card',
        mediaRef: 'party:${room.roomId}',
      );
      if (!mounted) return;
      DizzyNotify.show(
        context,
        'Room ${room.roomId} is live — invite sent!',
        tone: NotifyTone.success,
      );
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const WatchPartyPage()));
    } finally {
      if (mounted) setState(() => _partyBusy = false);
    }
  }

  Widget _buildMediaCardBubble(DizzyDirectMessage msg, bool isMe) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);
    final ref = msg.mediaRef ?? '';
    final isPartyInvite = ref.startsWith('party:');
    final roomCode = isPartyInvite ? ref.substring('party:'.length).trim() : null;
    final title = isPartyInvite
        ? 'Watch Together'
        : (msg.body.isNotEmpty ? msg.body : 'Media invite');
    final sub = isPartyInvite
        ? 'Room $roomCode — tap to join.'
        : 'Tap to watch together.';
    final buttonLabel = isPartyInvite ? 'Join room' : 'Watch Together';
    return Container(
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
                        style: TextStyle(
                          color: ink,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                    _partyBusy ? 'Working...' : buttonLabel,
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
    );
  }

  Widget _buildTextMessageBubble(DizzyDirectMessage msg, bool isMe) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final panel = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: DizzySpace.xxs),
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
                  : Colors.black.withValues(alpha: isLight ? 0.08 : 0.40),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          msg.body,
          style: TextStyle(color: isMe ? Colors.white : ink, fontSize: 14),
        ),
      ),
    );
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
    final online = isLight ? PrismAccent.successTextLight : DizzyGlow.volt;
    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: panel,
                  child: Text(
                    widget.recipientUsername.isNotEmpty
                        ? widget.recipientUsername[0].toUpperCase()
                        : '?',
                    style: TextStyle(color: ink, fontWeight: FontWeight.bold),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: DizzyGlow.volt,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: DizzySpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '@${widget.recipientUsername}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Online • Ready to sync',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: online, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(DizzySpace.md),
              itemCount: _messages.length,
              itemBuilder: (ctx, index) {
                final msg = _messages[index];
                final isMe =
                    _myUid != null && msg.senderId == _myUid;
                if (msg.kind == 'media_card') {
                  return Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: _buildMediaCardBubble(msg, isMe),
                  );
                }
                return _buildTextMessageBubble(msg, isMe);
              },
            ),
          ),
          _pendingBar(),
          // Bottom Tactile Input Bar
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
                          hintText: 'Message or share title...',
                          hintStyle: TextStyle(color: inkSoft, fontSize: 13),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessage(),
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
                      onTap: _sendMessage,
                      child: const Icon(
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
}
