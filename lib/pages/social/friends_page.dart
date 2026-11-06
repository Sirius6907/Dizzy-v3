import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
import 'package:dizzy/services/social/dizzy_friend_service.dart';
import 'package:dizzy/models/social/friendship.dart';
import '../../services/theme/app_theme_service.dart';
import 'direct_message_page.dart';
import '../../widgets/common/notify.dart';

typedef UserLookup = Future<List<DizzyUserMatch>> Function(String query);

/// Friends — find by @username, send requests, accept/reject, chat.
/// Three tabs: Search / Requests (badge) / Friends. Fail-soft, Easy English.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, this.lookup});

  /// Override for tests and alternative identity backends.
  final UserLookup? lookup;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage>
    with SingleTickerProviderStateMixin {
  static const _debounceDelay = Duration(milliseconds: 400);
  static const _lookupTimeout = Duration(seconds: 8);

  late TabController _tabs;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<DizzyUserMatch> _results = [];
  bool _searching = false;
  bool _searchFailed = false;
  bool _hasSearched = false;
  int _generation = 0;
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    DizzyFriendService.loadFriendships();
  }

  @override
  void dispose() {
    _generation++;
    _tabs.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Handles an @handle the same as its bare form.
  static String _normalize(String raw) =>
      raw.trim().replaceFirst(RegExp(r'^@'), '').trim();

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    // Every edit invalidates the in-flight answer before the new debounce
    // even fires, so a slow old lookup can never repaint this screen.
    _generation++;
    setState(() {
      _searching = false;
      _searchFailed = false;
      _hasSearched = false;
      _results = [];
    });
    if (_normalize(q).length < 2) return;
    _debounce = Timer(_debounceDelay, () => _runSearch(q));
  }

  Future<void> _runSearch(String raw) async {
    _debounce?.cancel();
    _debounce = null;
    final query = _normalize(raw);
    final generation = ++_generation;
    if (query.length < 2) {
      if (mounted) {
        setState(() {
          _searching = false;
          _searchFailed = false;
          _hasSearched = false;
          _results = [];
        });
      }
      return;
    }
    setState(() {
      _searching = true;
      _searchFailed = false;
    });
    try {
      final res = await Future.sync(
        () => (widget.lookup ?? DizzySocialService.searchUsers)(query),
      ).timeout(_lookupTimeout);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = res;
        _searching = false;
        _searchFailed = false;
        _hasSearched = true;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = [];
        _searching = false;
        _searchFailed = true;
        _hasSearched = false;
      });
    }
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
      tone: ok ? NotifyTone.success : NotifyTone.warn,
    );
  }

  Future<void> _accept(String uid) async {
    setState(() => _busyIds.add(uid));
    final ok = await DizzyFriendService.acceptRequest(uid);
    if (!mounted) return;
    setState(() => _busyIds.remove(uid));
    DizzyNotify.show(
      context,
      ok ? 'You are now friends! Say hi 👋' : "Couldn't accept right now.",
      tone: ok ? NotifyTone.success : NotifyTone.warn,
    );
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
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Friends',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: DizzyGlow.red,
          indicatorWeight: 3,
          labelColor: ink,
          unselectedLabelColor: inkSoft,
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
                            .where(
                              (f) =>
                                  f.status == FriendStatus.pending &&
                                  f.addresseeId == uid,
                            )
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
        children: [_searchTab(), _requestsTab(), _friendsTab()],
      ),
    );
  }

  Widget _searchTab() {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final well = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(DizzySpace.md),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            style: TextStyle(color: ink),
            decoration: InputDecoration(
              hintText: 'Search a name or @username',
              hintStyle: TextStyle(color: inkSoft, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded, color: inkSoft),
              filled: true,
              fillColor: well,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: hairline),
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
          child: _searchFailed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Couldn't search right now.",
                        style: TextStyle(color: inkSoft, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => _runSearch(_search.text),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : !_searching && _results.isEmpty
              ? Center(
                  child: Text(
                    _hasSearched
                        ? 'No users found.'
                        : 'Search any @username to add friends.',
                    style: TextStyle(color: inkSoft, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (c, i) {
                    final m = _results[i];
                    final status = DizzyFriendService.getStatus(m.userId);
                    final busy = _busyIds.contains(m.userId);
                    return _userRow(
                      name: m.username,
                      sub: m.displayName.isNotEmpty ? m.displayName : null,
                      trailing: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: DizzyGlow.red,
                              ),
                            )
                          : status == FriendStatus.accepted
                          ? _miniBtn('Chat', () => _chat(m.userId, m.username))
                          : status == FriendStatus.pending
                          ? Text(
                              'Sent ✓',
                              style: TextStyle(color: inkSoft, fontSize: 12),
                            )
                          : _miniBtn('Add', () => _send(m.userId, m.username)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _requestsTab() {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    return ValueListenableBuilder<List<Friendship>>(
      valueListenable: DizzyFriendService.friendships,
      builder: (c, list, _) {
        final uid = DizzyFriendService.myUid;
        final incoming = uid == null
            ? <Friendship>[]
            : list
                  .where(
                    (f) =>
                        f.status == FriendStatus.pending &&
                        f.addresseeId == uid,
                  )
                  .toList();
        if (incoming.isEmpty) {
          return Center(
            child: Text(
              'No requests right now.',
              style: TextStyle(color: inkSoft, fontSize: 13),
            ),
          );
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
                        strokeWidth: 2,
                        color: DizzyGlow.red,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _miniBtn('Accept', () => _accept(f.requesterId)),
                        const SizedBox(width: 8),
                        _miniBtn(
                          'Skip',
                          () => _reject(f.requesterId),
                          ghost: true,
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _friendsTab() {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    return ValueListenableBuilder<List<Friendship>>(
      valueListenable: DizzyFriendService.friendships,
      builder: (c, _, __) {
        final ids = DizzyFriendService.getFriends();
        if (ids.isEmpty) {
          return Center(
            child: Text(
              'No friends yet — search above to add some!',
              style: TextStyle(color: inkSoft, fontSize: 13),
            ),
          );
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
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final panel = isLight ? PrismLight.raisedTop : PrismDark.raised;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DizzySpace.md,
        vertical: DizzySpace.xs,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: panel,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: ink, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: DizzySpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@$name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onTap, {bool ghost = false}) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final labelColor = ghost && isLight ? PrismLight.ink : Colors.white;
    return DizzyTactileButton(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      onTap: onTap,
      gradient: ghost ? null : DizzyGradients.emberButton,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: labelColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          height: 1.2,
        ),
      ),
    );
  }
}
