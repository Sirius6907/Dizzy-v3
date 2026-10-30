import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/prism_tokens.dart';

import '../../../services/cloud/cloud_client.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/cloud/watch_party_service.dart';
import '../../../services/watchparty/party_chat_service.dart';
import '../../../services/watchparty/party_voice_service.dart';

/// WP-P4: live room panel — chat, members, host controls.
/// Shown in the lobby once a room is joined. Chat is ephemeral
/// (room close wipes it); display names are device codes, never uuids.
class PartyRoomPanel extends StatefulWidget {
  final WatchPartyRoom room;
  final bool isHost;
  final VoidCallback onExit;

  const PartyRoomPanel({
    super.key,
    required this.room,
    required this.isHost,
    required this.onExit,
  });

  @override
  State<PartyRoomPanel> createState() => _PartyRoomPanelState();
}

class _PartyRoomPanelState extends State<PartyRoomPanel> {
  final _input = TextEditingController();
  bool _sending = false;
  bool _locked = false;
  int _memberTick = 0;
  // P11: message being replied to (null = fresh message).
  PartyChatMessage? _replyTo;
  // Perf: memoized members query — rebuilds (e.g. voice bar updates in the
  // parent) must NOT refire Supabase. Refresh button resets it.
  Future<List<PartyMember>>? _membersFuture;
  int _membersKey = -1;

  String get _roomId => widget.room.roomId;
  String? get _myUid =>
      CloudClient.isReady ? CloudClient.db.auth.currentUser?.id : null;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
    final panel = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DizzyGlow.violet.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '🏠 ${widget.room.title} • $_roomId',
                  style: TextStyle(
                    color: ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_locked)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.lock_rounded,
                    color: Colors.amber,
                    size: 18,
                  ),
                ),
              IconButton(
                tooltip: 'Refresh members',
                onPressed: _refreshMembers,
                icon: Icon(Icons.refresh_rounded, color: inkSoft, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _members(),
          Divider(color: hairline, height: 24),
          _chat(),
          const SizedBox(height: 10),
          _controls(),
        ],
      ),
    );
  }

  Future<List<PartyMember>> _membersQuery() {
    if (_membersFuture == null || _membersKey != _memberTick) {
      _membersKey = _memberTick;
      _membersFuture = PartyChatService.listMembers(_roomId);
    }
    return _membersFuture!;
  }

  void _refreshMembers() {
    _membersFuture = null;
    // ignore: unawaited_futures
    WatchPartyService.touchMembership(_roomId);
    setState(() => _memberTick++);
  }

  Widget _members() => FutureBuilder<List<PartyMember>>(
    // ignore: discarded_futures
    future: _membersQuery(),
    builder: (c, snap) {
      final isLight = AppThemeService.currentPalette.value.isLight;
      final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
      final members = snap.data ?? const [];
      if (members.isEmpty) {
        return Text(
          'Members loading…',
          style: TextStyle(color: inkSoft, fontSize: 12),
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final m in members) _memberChip(m)],
      );
    },
  );

  Widget _memberChip(PartyMember m) {
    final mine = m.userId == _myUid;
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PartyVoiceService.speakingIds,
      builder: (c, ids, _) {
        final isLight = AppThemeService.currentPalette.value.isLight;
        final ink = isLight ? PrismLight.ink : Colors.white;
        final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
        final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
        final hairline = isLight
            ? PrismLight.borderSubtle
            : Colors.white.withValues(alpha: 0.12);
        final live = ids.contains(m.userId);
        return GestureDetector(
          onLongPress: widget.isHost && !mine ? () => _confirmKick(m) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: well,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: live ? Colors.greenAccent : hairline,
                width: live ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // P12: green speaking dot from the LIVE voice feed.
                if (live) ...[
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                Text(
                  m.displayName,
                  style: TextStyle(
                    color: ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (m.isHost)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      'HOST',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                if (mine)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '(you)',
                      style: TextStyle(color: inkSoft, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chat() {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
    final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.10);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pinnedBanner(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: StreamBuilder<List<PartyChatMessage>>(
            stream: PartyChatService.watchMessages(_roomId),
            builder: (c, snap) {
              final msgs = snap.data ?? const [];
              if (msgs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No messages yet. Say hi — or stay quiet, lurking is allowed 🤫',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                itemCount: msgs.length,
                itemBuilder: (c, i) => _bubble(msgs[i]),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        if (_replyTo != null) _replyStrip(),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                maxLength: 500,
                style: TextStyle(color: ink, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: well,
                  hintText: 'Chat… (introverts welcome)',
                  hintStyle: TextStyle(color: inkSoft, fontSize: 12),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.primaryColor),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Send',
              onPressed: _sending ? null : _send,
              icon: Icon(Icons.send_rounded, color: inkSoft),
            ),
          ],
        ),
      ],
    );
  }

  /// P11: host's pinned note ("interval in 5 min"). Host can unpin.
  Widget _pinnedBanner() => StreamBuilder<String?>(
    stream: PartyChatService.watchPinned(_roomId),
    builder: (c, snap) {
      final isLight = AppThemeService.currentPalette.value.isLight;
      final ink = isLight ? PrismLight.ink : Colors.white;
      final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
      final text = snap.data;
      if (text == null || text.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Text('📌', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: ink, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.isHost)
              GestureDetector(
                onTap: () async {
                  await PartyChatService.setPinned(_roomId, null);
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.close_rounded, color: inkSoft, size: 16),
                ),
              ),
          ],
        ),
      );
    },
  );

  /// P11: "replying to X" strip above the composer.
  Widget _replyStrip() {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white70;
    final inkFaint = isLight ? PrismLight.inkFaint : Colors.white54;
    final r = _replyTo!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: DizzyGlow.violet.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '↩ ${r.displayName}: ${r.body}',
              style: TextStyle(color: inkSoft, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _replyTo = null),
            child: Icon(Icons.close_rounded, color: inkFaint, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _bubble(PartyChatMessage m) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
    final inkFaint = isLight ? PrismLight.inkFaint : Colors.white38;
    final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final quoteBg = isLight
        ? PrismLight.raisedTop
        : Colors.white.withValues(alpha: 0.06);
    final reactionBg = isLight
        ? PrismLight.raisedTop
        : Colors.white.withValues(alpha: 0.08);
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);
    final mine = m.senderId == _myUid;
    return GestureDetector(
      onLongPress: () => _messageActions(m),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            color: mine ? DizzyGlow.violet.withValues(alpha: 0.35) : well,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.displayName,
                    style: TextStyle(color: inkSoft, fontSize: 11),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: inkFaint, fontSize: 11),
                  ),
                ],
              ),
              // P11: quoted parent (server-filled preview, no fetch).
              if (m.replyPreview != null && m.replyPreview!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: quoteBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(
                        color: DizzyGlow.violet.withValues(alpha: 0.7),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    '↩ ${m.replyName}: ${m.replyPreview}',
                    style: TextStyle(color: inkSoft, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(m.body, style: TextStyle(color: ink, fontSize: 13)),
              ),
              // P11: reaction chips (tap = toggle mine).
              if (m.reactions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final e in m.reactions.entries)
                        GestureDetector(
                          onTap: () =>
                              PartyChatService.toggleReaction(m.id, e.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: reactionBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${e.key} ${e.value}',
                              style: const TextStyle(fontSize: 11),
                            ),
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

  /// P11: long-press → reply / react / pin (host).
  Future<void> _messageActions(PartyChatMessage m) async {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white70;
    final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.cardBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.body,
                style: TextStyle(color: inkSoft, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: [
                  for (final e in PartyChatService.allowedEmoji)
                    GestureDetector(
                      onTap: () => Navigator.pop(c, 'react:$e'),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: well,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(c, 'reply'),
                      icon: const Icon(Icons.reply_rounded, size: 16),
                      label: const Text('Reply'),
                    ),
                  ),
                  if (widget.isHost) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(c, 'pin'),
                        icon: const Icon(Icons.push_pin_rounded, size: 16),
                        label: const Text('Pin'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reply') {
      setState(() => _replyTo = m);
    } else if (action == 'pin') {
      final ok = await PartyChatService.setPinned(_roomId, m.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Pinned for everyone. 📌' : 'Pin failed.')),
      );
    } else if (action.startsWith('react:')) {
      await PartyChatService.toggleReaction(m.id, action.substring(6));
    }
  }

  Widget _controls() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (widget.isHost)
        OutlinedButton.icon(
          onPressed: _toggleLock,
          icon: Icon(
            _locked ? Icons.lock_open_rounded : Icons.lock_rounded,
            size: 16,
          ),
          label: Text(_locked ? 'Unlock' : 'Lock'),
        ),
      if (widget.isHost)
        OutlinedButton.icon(
          onPressed: _endRoom,
          icon: const Icon(Icons.stop_rounded, size: 16),
          label: const Text('End for all'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
        ),
      OutlinedButton.icon(
        onPressed: _leave,
        icon: const Icon(Icons.logout_rounded, size: 16),
        label: const Text('Leave'),
      ),
    ],
  );

  Future<void> _send() async {
    final text = _input.text;
    if (!PartyChatService.validBody(text) || _sending) return;
    setState(() => _sending = true);
    final ok = await PartyChatService.sendMessage(
      _roomId,
      text,
      replyToId: _replyTo?.id,
    );
    if (mounted) setState(() => _sending = false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not sent — slow down (1 msg / 2s) or rejoin.'),
        ),
      );
      return;
    }
    _input.clear();
    if (mounted) setState(() => _replyTo = null);
  }

  Future<void> _toggleLock() async {
    final ok = await PartyChatService.setLocked(_roomId, !_locked);
    if (!mounted) return;
    if (ok) {
      setState(() => _locked = !_locked);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lock toggle failed.')));
    }
  }

  Future<void> _confirmKick(PartyMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Kick ${m.displayName}?'),
        content: const Text(
          'They leave voice + room immediately. They can rejoin unless locked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Kick'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final done = await PartyChatService.kickMember(_roomId, m.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(done ? 'Kicked.' : 'Kick failed.')),
      );
      if (done) setState(() => _memberTick++);
    }
  }

  Future<void> _endRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('End room for everyone?'),
        content: const Text('Chat is wiped and members are disconnected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('End room'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await WatchPartyService.closeRoom(_roomId);
    await PartyVoiceService.leave();
    widget.onExit();
  }

  Future<void> _leave() async {
    await WatchPartyService.leaveRoom(_roomId);
    await PartyVoiceService.leave();
    widget.onExit();
  }
}
