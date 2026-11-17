import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/services/social/dizzy_group_service.dart';
import 'package:dizzy/widgets/prism/prism_card.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';

import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/notify.dart';
import 'group_chat_page.dart';

/// Groups hub — list of my groups, create one, or join with a code.
///
/// Mirrors [FriendsPage]'s fail-soft discipline: every network path settles,
/// the empty state is never a dead end, and Easy English copy throughout.
class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  /// Single-flight guard for the create/join dialogs.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(DizzyGroupService.refreshMyGroups());
  }

  // ── Create / join ────────────────────────────────────────────────

  Future<void> _create() async {
    if (_busy) return;
    final name = await _askText(
      title: 'New group',
      hint: 'Group name',
      action: 'Create',
      helper: 'Give it a name you will recognise.',
    );
    if (name == null || name.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final groupId = await DizzyGroupService.createGroup(name);
    if (!mounted) return;
    setState(() => _busy = false);

    if (groupId == null) {
      DizzyNotify.show(
        context,
        "Couldn't create the group — check net, then try again.",
        tone: NotifyTone.warn,
      );
      return;
    }
    await _showCode(groupId);
  }

  Future<void> _join() async {
    if (_busy) return;
    final code = await _askText(
      title: 'Join a group',
      hint: 'Group code',
      action: 'Join',
      helper: 'Ask the group owner for the code.',
    );
    if (code == null || code.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final name = await DizzyGroupService.joinGroup(code);
    if (!mounted) return;
    setState(() => _busy = false);

    if (name == null) {
      DizzyNotify.show(
        context,
        "Couldn't join — check the code and your net.",
        tone: NotifyTone.warn,
      );
      return;
    }
    DizzyNotify.show(
      context,
      'Joined $name 🎉',
      tone: NotifyTone.success,
    );
  }

  /// Text prompt dialog. Returns trimmed text, or null when cancelled.
  Future<String?> _askText({
    required String title,
    required String hint,
    required String action,
    String? helper,
  }) async {
    final controller = TextEditingController();
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeService.currentPalette.value
            .scaffoldBackgroundColor,
        title: Text(
          title,
          style: TextStyle(color: ink, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (helper != null) ...[
              Text(
                helper,
                style: TextStyle(color: inkSoft, fontSize: 12),
              ),
              const SizedBox(height: DizzySpace.sm),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              style: TextStyle(color: ink, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: inkSoft, fontSize: 13),
                counterText: '',
                filled: true,
                fillColor: well,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DizzyRadius.md),
                  borderSide: BorderSide(color: hairline),
                ),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: inkSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(
              action,
              style: const TextStyle(
                color: DizzyGlow.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  /// Shows the join code after creating a group, with one-tap copy.
  Future<void> _showCode(String groupId) async {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeService.currentPalette.value
            .scaffoldBackgroundColor,
        title: Text(
          'Group created',
          style: TextStyle(color: ink, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share this code so friends can join:',
              style: TextStyle(color: inkSoft, fontSize: 12),
            ),
            const SizedBox(height: DizzySpace.sm),
            SelectableText(
              groupId,
              style: TextStyle(
                color: ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: groupId));
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                DizzyNotify.show(
                  context,
                  'Code copied!',
                  tone: NotifyTone.success,
                );
              }
            },
            child: const Text(
              'Copy code',
              style: TextStyle(
                color: DizzyGlow.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Done', style: TextStyle(color: inkSoft)),
          ),
        ],
      ),
    );
  }

  // ── Navigation ───────────────────────────────────────────────────

  Future<void> _open(DizzyGroup group) async {
    final isOwner =
        DizzyGroupService.myRoles.value[group.groupId] == 'owner';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          groupId: group.groupId,
          groupName: group.name,
          memberCount: group.memberCount,
          isOwner: isOwner,
        ),
      ),
    );
    // Roster or last-message may have changed while away.
    await DizzyGroupService.refreshMyGroups();
  }

  // ── UI ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;

    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Groups',
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w800,
            fontSize: 19,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Join with a code',
            onPressed: _busy ? null : _join,
            icon: Icon(Icons.key_rounded, color: ink),
          ),
          IconButton(
            tooltip: 'New group',
            onPressed: _busy ? null : _create,
            icon: Icon(Icons.add_rounded, color: ink),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<DizzyGroup>>(
        valueListenable: DizzyGroupService.myGroups,
        builder: (context, groups, _) {
          if (groups.isEmpty) return _emptyState();
          return RefreshIndicator(
            color: DizzyGlow.red,
            onRefresh: DizzyGroupService.refreshMyGroups,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: DizzySpace.xs),
              itemCount: groups.length,
              itemBuilder: (c, i) => _groupRow(groups[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DizzySpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DizzyGlow.violet.withValues(alpha: 0.14),
                border: Border.all(
                  color: DizzyGlow.violet.withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(
                Icons.groups_rounded,
                size: 34,
                color: DizzyGlow.violet,
              ),
            ),
            const SizedBox(height: DizzySpace.md),
            Text(
              'No groups yet',
              style: TextStyle(
                color: ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: DizzySpace.xxs),
            Text(
              'Create one, or join with a code from a friend.',
              textAlign: TextAlign.center,
              style: TextStyle(color: inkSoft, fontSize: 13),
            ),
            const SizedBox(height: DizzySpace.lg),
            DizzyTactileButton(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              gradient: DizzyGradients.emberButton,
              glowColor: DizzyGlow.red,
              onTap: _busy ? null : _create,
              child: const Text(
                'Create a group',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: DizzySpace.xs),
            TextButton(
              onPressed: _busy ? null : _join,
              child: Text(
                'Join with a code',
                style: TextStyle(color: inkSoft, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupRow(DizzyGroup group) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;

    final preview = (group.lastMessage ?? '').trim();
    final subtitle = preview.isEmpty
        ? 'No messages yet'
        : (group.lastKind == 'media_card' ? '🎬 Watch Together card' : preview);

    return PrismCard(
      margin: const EdgeInsets.symmetric(
        horizontal: DizzySpace.md,
        vertical: DizzySpace.xxs,
      ),
      padding: const EdgeInsets.all(DizzySpace.sm),
      onTap: () => _open(group),
      borderRadius: BorderRadius.circular(DizzyRadius.lg),
      child: Row(
        children: [
          _GroupAvatar(name: group.name, size: 44),
          const SizedBox(width: DizzySpace.sm),
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
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      size: 12,
                      color: inkSoft,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      group.memberCount == 1
                          ? '1 member'
                          : '${group.memberCount} members',
                      style: TextStyle(color: inkSoft, fontSize: 11.5),
                    ),
                    if (group.lastMessageAt != null) ...[
                      Text(
                        ' · ',
                        style: TextStyle(color: inkSoft, fontSize: 11.5),
                      ),
                      Text(
                        _ago(group.lastMessageAt!),
                        style: TextStyle(color: inkSoft, fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: inkSoft.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DizzySpace.xs),
          Icon(
            Icons.chevron_right_rounded,
            color: inkSoft,
            size: 20,
          ),
        ],
      ),
    );
  }

  /// Short, human "2h ago" style timestamp.
  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }
}

/// Deterministic gradient avatar keyed off the group name, so a group keeps
/// the same colour between sessions (matches DizzyColors.avatarPairs).
class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.name, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pair = DizzyColors.avatarPairs[
        name.isEmpty ? 0 : name.codeUnitAt(0) % DizzyColors.avatarPairs.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: pair),
      ),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '#',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
