import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/social/dizzy_friend_service.dart';
import 'package:dizzy/services/social/dizzy_group_service.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
import 'package:dizzy/services/social/social_hub_service.dart';
import 'package:dizzy/widgets/prism/prism_card.dart';

import '../../services/theme/app_theme_service.dart';
import '../../widgets/social/social_hub_sheet.dart';
import '../settings/watch_party_page.dart';
import 'direct_message_page.dart';
import 'friends_page.dart';
import 'group_chat_page.dart';
import 'groups_page.dart';

/// Social Hub v2 — the single front door for everything social.
///
/// One inbox for DMs, plus one-tap routes to Friends, Groups, Watch Party
/// and Listen Together. Unread badges come from the local per-thread
/// `last_read` cursor in [SocialHubService].
class SocialHubPage extends StatefulWidget {
  const SocialHubPage({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SocialHubPage()),
    );
  }

  @override
  State<SocialHubPage> createState() => _SocialHubPageState();
}

class _SocialHubPageState extends State<SocialHubPage> {
  List<SocialInboxItem> _items = const [];
  List<SocialGroupItem> _groups = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    DizzySocialService.resolvedNames.addListener(_repaint);
    SocialHubService.totalUnread.addListener(_repaint);
    unawaited(_load());
    unawaited(DizzyFriendService.loadFriendships());
    unawaited(DizzyGroupService.refreshMyGroups());
  }

  @override
  void dispose() {
    DizzySocialService.resolvedNames.removeListener(_repaint);
    SocialHubService.totalUnread.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (_items.isEmpty) setState(() => _loading = true);
    final results = await Future.wait([
      SocialHubService.loadInbox(),
      SocialHubService.loadGroupInbox(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<SocialInboxItem>;
      _groups = results[1] as List<SocialGroupItem>;
      _loading = false;
      // An offline empty inbox is quiet, not broken — say so plainly.
      _failed = !CloudClient.isReady;
    });
  }

  Future<void> _openThread(SocialInboxItem item) async {
    await SocialHubService.markRead(item.threadId, through: item.lastAt);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DirectMessagePage(
          recipientUid: item.peerUid,
          recipientUsername: DizzySocialService.displayNameFor(item.peerUid),
        ),
      ),
    );
    await _load();
  }

  Future<void> _openGroup(SocialGroupItem group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          groupId: group.groupId,
          groupName: group.name,
          memberCount: group.memberCount,
          isOwner: DizzyGroupService.myRoles.value[group.groupId] == 'owner',
        ),
      ),
    );
    // The chat page advances the cursor as it opens; a reload here also
    // catches messages that arrived while this screen was behind it.
    await _load();
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _load();
  }

  String _preview(SocialInboxItem item) {
    if (item.lastAt == null) return 'Say hi 👋';
    if (item.lastKind == 'media_card') return 'Shared a Watch Together card';
    if (item.lastKind == 'action') return 'Sent a room invite';
    final body = (item.lastBody ?? '').trim();
    if (body.isEmpty) return 'New message';
    return body.length > 64 ? '${body.substring(0, 64)}…' : body;
  }

  String _groupPreview(SocialGroupItem group) {
    if (group.lastAt == null) return 'No messages yet — say hi 👋';
    if (group.lastKind == 'media_card') return 'Shared a Watch Together card';
    final body = (group.lastBody ?? '').trim();
    if (body.isEmpty) return 'New message';
    return body.length > 64 ? '${body.substring(0, 64)}…' : body;
  }

  String _when(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${at.day}/${at.month}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final unread = SocialHubService.totalUnread.value;

    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Social Hub',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
        actions: [
          IconButton(
            tooltip: 'Find friends',
            onPressed: () => _open(const FriendsPage()),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
          children: [
            _HeroCard(unread: unread, ink: ink, inkSoft: inkSoft),
            const SizedBox(height: 22),
            Row(
              children: [
                Text(
                  'Messages',
                  style: TextStyle(
                    color: ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  unread > 0 ? '$unread new' : 'All caught up',
                  style: TextStyle(
                    color: unread > 0 ? palette.primaryColor : inkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              )
            else if (_items.isEmpty)
              _EmptyInbox(
                failed: _failed,
                ink: ink,
                inkSoft: inkSoft,
                onFind: () => _open(const FriendsPage()),
              )
            else
              PrismCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: isLight
                              ? PrismLight.borderSubtle
                              : Colors.white.withValues(alpha: 0.07),
                        ),
                      _InboxRow(
                        item: _items[i],
                        name: DizzySocialService.displayNameFor(
                          _items[i].peerUid,
                        ),
                        preview: _preview(_items[i]),
                        when: _when(_items[i].lastAt),
                        ink: ink,
                        inkSoft: inkSoft,
                        accent: palette.primaryColor,
                        onTap: () => _openThread(_items[i]),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 26),
            Row(
              children: [
                Text(
                  'Groups',
                  style: TextStyle(
                    color: ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _open(const GroupsPage()),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'See all',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_groups.isEmpty)
              _CircleTile(
                icon: Icons.group_add_rounded,
                title: 'Start a group',
                subtitle: 'Chat and share with a whole group',
                accent: const Color(0xFF8B5CF6),
                onTap: () => _open(const GroupsPage()),
              )
            else
              PrismCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _groups.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: isLight
                              ? PrismLight.borderSubtle
                              : Colors.white.withValues(alpha: 0.07),
                        ),
                      _GroupRow(
                        group: _groups[i],
                        preview: _groupPreview(_groups[i]),
                        when: _when(_groups[i].lastAt),
                        ink: ink,
                        inkSoft: inkSoft,
                        accent: const Color(0xFF8B5CF6),
                        onTap: () => _openGroup(_groups[i]),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 26),
            Text(
              'Your circles',
              style: TextStyle(
                color: ink,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _CircleTile(
              icon: Icons.people_rounded,
              title: 'Friends',
              subtitle: 'Find people and send a request',
              accent: palette.primaryColor,
              onTap: () => _open(const FriendsPage()),
            ),
            const SizedBox(height: 10),
            _CircleTile(
              icon: Icons.forum_rounded,
              title: 'Groups',
              subtitle: 'Chat and share with a whole group',
              accent: const Color(0xFF8B5CF6),
              onTap: () => _open(const GroupsPage()),
            ),
            const SizedBox(height: 10),
            _CircleTile(
              icon: Icons.movie_filter_rounded,
              title: 'Watch Party',
              subtitle: 'One screen for everyone — room ID join',
              accent: const Color(0xFFEF4444),
              onTap: () => _open(const WatchPartyPage()),
            ),
            const SizedBox(height: 10),
            _CircleTile(
              icon: Icons.headphones_rounded,
              title: 'Listen Together',
              subtitle: 'Start or join a jam room',
              accent: const Color(0xFF10B981),
              onTap: () => SocialHubSheet.show(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.unread,
    required this.ink,
    required this.inkSoft,
  });

  final int unread;
  final Color ink;
  final Color inkSoft;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.primaryColor.withValues(alpha: 0.20),
            palette.primaryColor.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.primaryColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.primaryColor.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              unread > 0 ? Icons.mark_unread_chat_alt_rounded : Icons.hub_rounded,
              color: palette.primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unread > 0 ? 'You have $unread new' : 'Everyone, one place',
                  style: TextStyle(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  unread > 0
                      ? 'Open a chat to clear it.'
                      : 'Messages, friends, groups and rooms — all here.',
                  style: TextStyle(color: inkSoft, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({
    required this.item,
    required this.name,
    required this.preview,
    required this.when,
    required this.ink,
    required this.inkSoft,
    required this.accent,
    required this.onTap,
  });

  final SocialInboxItem item;
  final String name;
  final String preview;
  final String when;
  final Color ink;
  final Color inkSoft;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final unread = item.unreadCount;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: unread > 0 ? 0.24 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Text(
                initial,
                style: TextStyle(
                  color: accent,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 14.5,
                      fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unread > 0 ? ink : inkSoft,
                      fontSize: 12.5,
                      fontWeight: unread > 0
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(when, style: TextStyle(color: inkSoft, fontSize: 11)),
                const SizedBox(height: 5),
                if (unread > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.preview,
    required this.when,
    required this.ink,
    required this.inkSoft,
    required this.accent,
    required this.onTap,
  });

  final SocialGroupItem group;
  final String preview;
  final String when;
  final Color ink;
  final Color inkSoft;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = group.unreadCount;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: unread > 0 ? 0.24 : 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.forum_rounded, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 14.5,
                      fontWeight: unread > 0
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unread > 0 ? ink : inkSoft,
                      fontSize: 12.5,
                      fontWeight: unread > 0
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(when, style: TextStyle(color: inkSoft, fontSize: 11)),
                const SizedBox(height: 4),
                if (unread > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  Text(
                    '${group.memberCount}',
                    style: TextStyle(color: inkSoft, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({
    required this.failed,
    required this.ink,
    required this.inkSoft,
    required this.onFind,
  });

  final bool failed;
  final Color ink;
  final Color inkSoft;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return PrismCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Column(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              color: inkSoft,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              failed ? 'Messages need a connection' : 'No chats yet',
              style: TextStyle(
                color: ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              failed
                  ? 'Check your net, then pull down to retry.'
                  : 'Add a friend, then say hi. It shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: inkSoft, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onFind,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Find friends'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleTile extends StatelessWidget {
  const _CircleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final ink = palette.isLight ? PrismLight.ink : Colors.white;
    final inkSoft = palette.isLight ? PrismLight.inkSoft : Colors.white60;
    return PrismCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: inkSoft, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: inkSoft, size: 20),
        ],
      ),
    );
  }
}
