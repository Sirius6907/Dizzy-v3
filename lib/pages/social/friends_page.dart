import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
import 'package:dizzy/services/social/dizzy_friend_service.dart';
import 'package:dizzy/models/social/friendship.dart';
import 'direct_message_page.dart';
import '../../widgets/common/notify.dart';

/// Friends — find by @username, send requests, accept/reject, chat.
/// Three tabs: Search / Requests (badge) / Friends. Fail-soft, Easy English.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<DizzyUserMatch> _results = [];
  bool _searching = false;
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    DizzyFriendService.loadFriendships();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().length < 2) {
      if (mounted) setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final res = await DizzySocialService.searchUsers(q);
    if (!mounted) return;
    setState(() {
      _results = res;
      _searching = false;
    });
  }

  Future<void> _send(String uid, String name) async {
    setState(() => _busyIds.add(uid));
    final ok = await DizzyFriendService.sendRequest(uid);
    if (!mounted) return;
    setState(() => _busyIds.remove(uid));
    DizzyNotify.show(
        context,
        ok
            ? 'Request sent to @$name!'
            : "Couldn't send — check net, then try again.",
        tone: ok ? NotifyTone.success : NotifyTone.warn);
  }

  Future<void> _accept(String uid) async {
    setState(() => _busyIds.add(uid));
    final ok = await DizzyFriendService.acceptRequest(uid);
    if (!mounted) return;
    setState(() => _busyIds.remove(uid));
    DizzyNotify.show(context,
        ok ? 'You are now friends! Say hi 👋' : "Couldn't accept right now.",
        tone: ok ? NotifyTone.success : NotifyTone.warn);
  }

  Future<void> _reject(String uid) async {
    setState(() => _busyIds.add(uid));
    await DizzyFriendService.rejectRequest(uid);
    if (!mounted) return;
    setState(() => _busyIds.remove(uid));
  }

  void _chat(String uid, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DirectMessagePage(recipientUid: uid, recipientUsername: name),
      ),
    );
  }

  /// Username lookup for a uid: search cache → pending list → short id.
  /// (No direct profiles read — RLS is owner-only; search_users is the
  /// public path. Friend rows carry only uids, so we show a short id
  /// until the friend search index covers them.)
  String _labelFor(String uid) {
    for (final m in _results) {
      if (m.userId == uid) return m.username;
    }
    return 'friend_${uid.length > 6 ? uid.substring(0, 6) : uid}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DizzyVoid.voidA,
      appBar: AppBar(
        backgroundColor: DizzyVoid.voidB,
        surfaceTintColor: Colors.transparent,
        title: const Text('Friends',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: DizzyGlow.red,
          indicatorWeight: 3,
          labelColor: DizzyVoid.bone,
          unselectedLabelColor: DizzyVoid.ash,
          tabs: [
            const Tab(icon: Icon(Icons.search_rounded), text: 'Search'),
            Tab(
              icon: ValueListenableBuilder<List<Friendship>>(
                valueListenable: DizzyFriendService.friendships,
                builder: (c, list, _) {
                  final uid = DizzyFriendService.myUid;
                  final n = uid == null
                      ? 0
                      : list
                          .where((f) =>
                              f.status == FriendStatus.pending &&
                              f.addresseeId == uid)
                          .length;
                  return Badge(
                    isLabelVisible: n > 0,
                    label: Text('$n'),
                    child: const Icon(Icons.person_add_rounded),
                  );
                },
              ),
              text: 'Requests',
            ),
            const Tab(icon: Icon(Icons.people_rounded), text: 'Friends'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _searchTab(),
          _requestsTab(),
          _friendsTab(),
        ],
      ),
    );
  }

  Widget _searchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(DizzySpace.md),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: DizzyVoid.bone),
            decoration: InputDecoration(
              hintText: 'Type @username... (min 2 letters)',
              hintStyle: const TextStyle(color: DizzyVoid.ash, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: DizzyVoid.ash),
              filled: true,
              fillColor: DizzyVoid.surface1,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: DizzyEdge.hairline,
              ),
            ),
          ),
        ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.all(DizzySpace.md),
            child: CircularProgressIndicator(color: DizzyGlow.red),
          ),
        Expanded(
          child: _results.isEmpty && !_searching
              ? const Center(
                  child: Text('Search any @username to add friends.',
                      style: TextStyle(color: DizzyVoid.ash, fontSize: 13)))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (c, i) {
                    final m = _results[i];
                    final status =
                        DizzyFriendService.getStatus(m.userId);
                    final busy = _busyIds.contains(m.userId);
                    return _userRow(
                      name: m.username,
                      sub: m.displayName.isNotEmpty ? m.displayName : null,
                      trailing: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: DizzyGlow.red))
                          : status == FriendStatus.accepted
                              ? _miniBtn('Chat',
                                  () => _chat(m.userId, m.username))
                              : status == FriendStatus.pending
                                  ? const Text('Sent ✓',
                                      style: TextStyle(
                                          color: DizzyVoid.ash, fontSize: 12))
                                  : _miniBtn('Add', () => _send(m.userId, m.username)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _requestsTab() {
    return ValueListenableBuilder<List<Friendship>>(
      valueListenable: DizzyFriendService.friendships,
      builder: (c, list, _) {
        final uid = DizzyFriendService.myUid;
        final incoming = uid == null
            ? <Friendship>[]
            : list
                .where((f) =>
                    f.status == FriendStatus.pending && f.addresseeId == uid)
                .toList();
        if (incoming.isEmpty) {
          return const Center(
              child: Text('No requests right now.',
                  style: TextStyle(color: DizzyVoid.ash, fontSize: 13)));
        }
        return ListView.builder(
          itemCount: incoming.length,
          itemBuilder: (c, i) {
            final f = incoming[i];
            final busy = _busyIds.contains(f.requesterId);
            return _userRow(
              name: _labelFor(f.requesterId),
              sub: 'wants to be your friend',
              trailing: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: DizzyGlow.red))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _miniBtn('Accept', () => _accept(f.requesterId)),
                        const SizedBox(width: 8),
                        _miniBtn('Skip', () => _reject(f.requesterId),
                            ghost: true),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _friendsTab() {
    return ValueListenableBuilder<List<Friendship>>(
      valueListenable: DizzyFriendService.friendships,
      builder: (c, _, __) {
        final ids = DizzyFriendService.getFriends();
        if (ids.isEmpty) {
          return const Center(
              child: Text('No friends yet — search above to add some!',
                  style: TextStyle(color: DizzyVoid.ash, fontSize: 13)));
        }
        return ListView.builder(
          itemCount: ids.length,
          itemBuilder: (c, i) {
            final uid = ids[i];
            return _userRow(
              name: _labelFor(uid),
              sub: 'Online • Ready to sync',
              trailing: _miniBtn('Chat', () => _chat(uid, _labelFor(uid))),
            );
          },
        );
      },
    );
  }

  Widget _userRow({required String name, String? sub, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DizzySpace.md, vertical: DizzySpace.xs),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: DizzyVoid.surface2,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: DizzyVoid.bone, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: DizzySpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@$name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: DizzyVoid.bone,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                if (sub != null)
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: DizzyVoid.ash, fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onTap, {bool ghost = false}) {
    return DizzyTactileButton(
      height: 34,
      onTap: onTap,
      gradient: ghost ? null : DizzyGradients.emberButton,
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}
