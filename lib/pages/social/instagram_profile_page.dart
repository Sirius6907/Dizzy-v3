import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_card.dart';
import 'package:dizzy/services/social/dizzy_identity_service.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
import 'package:dizzy/services/device/device_id_service.dart';
import 'package:dizzy/models/continue_watching/continue_watching_item.dart';
import 'package:dizzy/services/continue_watching/continue_watching_service.dart';
import 'package:dizzy/services/manga/manga_service.dart';
import 'package:dizzy/models/manga/manga.dart';
import 'package:dizzy/models/manga/manga_chapter.dart';
import 'package:dizzy/pages/manga/manga_reader_page.dart';
import 'package:dizzy/services/my_list/my_list_service.dart';
import 'package:dizzy/models/my_list/my_list_item.dart';
import 'package:dizzy/models/movie/movie.dart';
import 'package:dizzy/pages/details/details_page.dart';
import 'package:dizzy/services/stats/watch_stats.dart';
import 'package:dizzy/widgets/common/dizzy_image.dart';
import 'friends_page.dart';
import '../../widgets/common/notify.dart';

/// Instagram-Grade Tactile Neo-Skeuomorphic Profile & Binge Hub.
/// 60-120 FPS performance, pure OLED true blacks, zero runtime shader cost.
class InstagramProfilePage extends StatefulWidget {
  const InstagramProfilePage({super.key});

  @override
  State<InstagramProfilePage> createState() => _InstagramProfilePageState();
}

class _InstagramProfilePageState extends State<InstagramProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _deviceCode = '...';
  String _username = 'binge_master';
  WatchStats _stats = WatchStats.empty;
  int _chaptersRead = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final code = await DeviceIdService.initialize();
    // Real stats: watch time + streak from Continue Watching, chapters
    // from manga reading history. Fail-soft — zeros on any error.
    var stats = WatchStats.empty;
    var chapters = 0;
    try {
      final items = List<ContinueWatchingItem>.from(
          ContinueWatchingService.activeItems.value);
      stats = WatchStats.aggregate(items);
    } catch (_) {}
    try {
      final history = await MangaService().getReadingHistory();
      chapters = history.length;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _deviceCode = code;
        _username = DizzySocialService.currentUsername.value ?? 'user_${code.toLowerCase()}';
        _stats = stats;
        _chaptersRead = chapters;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showClaimUsernameDialog() {
    final controller = TextEditingController(text: _username);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DizzyVoid.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: DizzyEdge.hairline,
        ),
        title: const Text(
          'Choose Username',
          style: TextStyle(
            color: DizzyVoid.bone,
            fontSize: DizzyType.title,
            fontWeight: DizzyType.wBold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your unique @username lets friends find and invite you.',
              style: TextStyle(color: DizzyVoid.ash, fontSize: 13),
            ),
            const SizedBox(height: DizzySpace.sm),
            TextField(
              controller: controller,
              style: const TextStyle(color: DizzyVoid.bone),
              decoration: InputDecoration(
                prefixText: '@ ',
                prefixStyle: const TextStyle(color: DizzyGlow.beam, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: DizzyVoid.surface1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: DizzyEdge.hairline,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: DizzyVoid.ash)),
          ),
          DizzyTactileButton(
            height: 38,
            onTap: () async {
              final val = controller.text.trim();
              if (val.isEmpty) return;
              Navigator.pop(ctx);
              final res = await DizzySocialService.claimUsername(val);
              if (res['success'] == true) {
                setState(() => _username = res['username']);
                if (mounted) {
                  DizzyNotify.show(context, 'Username updated to @$_username',
                      tone: NotifyTone.success);
                }
              } else {
                if (mounted) {
                  DizzyNotify.show(context, res['error'] ?? 'Could not claim username',
                      tone: NotifyTone.warn);
                }
              }
            },
            child: const Text(
              'Save',
              style: TextStyle(color: DizzyVoid.bone, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showLinkAccountSheet() {
    final linkedKind = DizzyIdentityService.linkedKind.value;
    showModalBottomSheet(
      context: context,
      backgroundColor: DizzyVoid.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(DizzySpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Link Phone or Email',
              style: TextStyle(
                color: DizzyVoid.bone,
                fontSize: DizzyType.title,
                fontWeight: DizzyType.wBold,
              ),
            ),
            const SizedBox(height: DizzySpace.xs),
            Text(
              linkedKind != null
                  ? 'Linked with ${linkedKind == 'phone' ? 'phone' : 'email'} (${DizzyIdentityService.linkedIdentifier.value ?? ''}). One link is enough — everything stays in sync.'
                  : 'Sync your Watchlist, history, and friends across phone and PC effortlessly.',
              style: const TextStyle(color: DizzyVoid.ash, fontSize: 13),
            ),
            const SizedBox(height: DizzySpace.lg),
            DizzyTactileButton(
              onTap: () {
                Navigator.pop(ctx);
                _startPhoneLink();
              },
              gradient: DizzyGradients.beamButton,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_iphone_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Link Phone Number',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DizzySpace.sm),
            DizzyTactileButton(
              onTap: () {
                Navigator.pop(ctx);
                _startEmailLink();
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.email_outlined, color: DizzyVoid.bone, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Link Google / Email',
                    style: TextStyle(color: DizzyVoid.bone, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Phone link: number → OTP → verify + merge into one account.
  /// Fail-soft everywhere, Easy English only.
  Future<void> _startPhoneLink() async {
    final controller = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DizzyVoid.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: DizzyEdge.hairline,
        ),
        title: const Text('Link Phone Number',
            style: TextStyle(
                color: DizzyVoid.bone,
                fontSize: DizzyType.title,
                fontWeight: DizzyType.wBold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('We will text you a 6-digit code. Nothing else changes.',
                style: TextStyle(color: DizzyVoid.ash, fontSize: 13)),
            const SizedBox(height: DizzySpace.sm),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: DizzyVoid.bone),
              decoration: InputDecoration(
                hintText: '+91 98765 43210',
                hintStyle: const TextStyle(color: DizzyVoid.ash),
                filled: true,
                fillColor: DizzyVoid.surface1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: DizzyEdge.hairline,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: DizzyVoid.ash)),
          ),
          DizzyTactileButton(
            height: 38,
            onTap: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Send Code',
                style: TextStyle(
                    color: DizzyVoid.bone, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (phone == null || phone.isEmpty || !mounted) return;
    DizzyNotify.show(context, 'Sending code...', tone: NotifyTone.info);
    final ok = await DizzyIdentityService.requestPhoneOtp(phone);
    if (!mounted) return;
    if (!ok) {
      DizzyNotify.show(
          context, "Couldn't send code — check net, or link Email instead.",
          tone: NotifyTone.warn);
      return;
    }
    _showOtpDialog(phone: phone);
  }

  /// Email link (works with Gmail too): address → OTP → verify + merge.
  Future<void> _startEmailLink() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DizzyVoid.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: DizzyEdge.hairline,
        ),
        title: const Text('Link Google / Email',
            style: TextStyle(
                color: DizzyVoid.bone,
                fontSize: DizzyType.title,
                fontWeight: DizzyType.wBold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Any email works — Gmail included. We mail you a code.',
                style: TextStyle(color: DizzyVoid.ash, fontSize: 13)),
            const SizedBox(height: DizzySpace.sm),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: DizzyVoid.bone),
              decoration: InputDecoration(
                hintText: 'you@gmail.com',
                hintStyle: const TextStyle(color: DizzyVoid.ash),
                filled: true,
                fillColor: DizzyVoid.surface1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: DizzyEdge.hairline,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: DizzyVoid.ash)),
          ),
          DizzyTactileButton(
            height: 38,
            onTap: () {
              final v = controller.text.trim();
              if (v.isEmpty || !v.contains('@')) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Send Code',
                style: TextStyle(
                    color: DizzyVoid.bone, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    DizzyNotify.show(context, 'Sending code...', tone: NotifyTone.info);
    final ok = await DizzyIdentityService.requestEmailOtp(email);
    if (!mounted) return;
    if (!ok) {
      DizzyNotify.show(context, "Couldn't send code — check net, then try again.",
          tone: NotifyTone.warn);
      return;
    }
    _showOtpDialog(email: email);
  }

  /// 6-digit OTP entry → verify + atomic merge of old anonymous data.
  void _showOtpDialog({String? phone, String? email}) {
    final controller = TextEditingController();
    var busy = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: DizzyVoid.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: DizzyEdge.hairline,
          ),
          title: const Text('Enter Code',
              style: TextStyle(
                  color: DizzyVoid.bone,
                  fontSize: DizzyType.title,
                  fontWeight: DizzyType.wBold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Code sent to ${phone ?? email}. It expires soon.',
                  style: const TextStyle(color: DizzyVoid.ash, fontSize: 13)),
              const SizedBox(height: DizzySpace.sm),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(
                    color: DizzyVoid.bone,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6),
                decoration: InputDecoration(
                  hintText: '••••••',
                  hintStyle: const TextStyle(color: DizzyVoid.ash),
                  filled: true,
                  fillColor: DizzyVoid.surface1,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: DizzyEdge.hairline,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: DizzyVoid.ash)),
            ),
            DizzyTactileButton(
              height: 38,
              onTap: busy
                  ? null
                  : () async {
                      final code = controller.text.trim();
                      if (code.length < 4) return;
                      setD(() => busy = true);
                      final ok =
                          await DizzyIdentityService.verifyOtpAndMerge(
                        token: code,
                        phone: phone,
                        email: email,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      if (ok) {
                        setState(() {});
                        DizzyNotify.show(
                            context, 'Account linked! Sync is on everywhere.',
                            tone: NotifyTone.success);
                      } else {
                        DizzyNotify.show(context,
                            'Wrong or expired code — ask for a fresh one.',
                            tone: NotifyTone.warn);
                      }
                    },
              child: Text(busy ? 'Checking...' : 'Verify',
                  style: const TextStyle(
                      color: DizzyVoid.bone, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DizzyVoid.voidA,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DizzySpace.md),
                  child: Column(
                    children: [
                      const SizedBox(height: DizzySpace.md),
                      // Top Header: Avatar + Meta
                      Row(
                        children: [
                          // 88px Tactile Avatar
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3A1C71), Color(0xFFD76D77)],
                              ),
                              border: Border.all(color: DizzyGlow.gold, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: DizzyGlow.gold.withValues(alpha: 0.30),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text('🍿', style: TextStyle(fontSize: 38)),
                            ),
                          ),
                          const SizedBox(width: DizzySpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '@$_username',
                                      style: const TextStyle(
                                        color: DizzyVoid.bone,
                                        fontSize: DizzyType.title,
                                        fontWeight: DizzyType.wBold,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: _showClaimUsernameDialog,
                                      child: const Icon(
                                        Icons.edit_rounded,
                                        size: 16,
                                        color: DizzyVoid.ash,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    color: DizzyVoid.surface2,
                                    border: Border.fromBorderSide(DizzyEdge.hairline),
                                  ),
                                  child: Text(
                                    'DEVICE: $_deviceCode',
                                    style: const TextStyle(
                                      color: DizzyGlow.beam,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DizzySpace.lg),
                      // Binge Stats Row (3 Columns) — live from WatchStats + manga history
                      Row(
                        children: [
                          Expanded(
                            child: DizzyTactileCard(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  Text(
                                    _stats.hoursLabel,
                                    style: const TextStyle(
                                      color: DizzyGlow.beam,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Watched',
                                    style: TextStyle(color: DizzyVoid.ash, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: DizzySpace.xs),
                          Expanded(
                            child: DizzyTactileCard(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              glowColor: DizzyGlow.gold,
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text('🔥 ', style: TextStyle(fontSize: 16)),
                                      Text(
                                        '${_stats.currentStreakDays}d',
                                        style: const TextStyle(
                                          color: DizzyGlow.gold,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Streak',
                                    style: TextStyle(color: DizzyVoid.ash, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: DizzySpace.xs),
                          Expanded(
                            child: DizzyTactileCard(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  Text(
                                    '$_chaptersRead',
                                    style: const TextStyle(
                                      color: DizzyGlow.violet,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Chapters',
                                    style: TextStyle(color: DizzyVoid.ash, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DizzySpace.md),
                      // Action Row
                      Row(
                        children: [
                          Expanded(
                            child: DizzyTactileButton(
                              onTap: _showLinkAccountSheet,
                              height: 42,
                              gradient: DizzyIdentityService.isLinked
                                  ? null
                                  : DizzyGradients.emberButton,
                              child: ValueListenableBuilder<String?>(
                                valueListenable:
                                    DizzyIdentityService.linkedKind,
                                builder: (c, kind, _) => Text(
                                  kind != null
                                      ? 'Account Linked ✓'
                                      : 'Link Phone / Gmail',
                                  style: const TextStyle(
                                    color: DizzyVoid.bone,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: DizzySpace.xs),
                          DizzyTactileButton(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const FriendsPage(),
                                ),
                              );
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_rounded,
                                    size: 18, color: DizzyVoid.bone),
                                SizedBox(width: 6),
                                Text('Friends',
                                    style: TextStyle(
                                        color: DizzyVoid.bone,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                          const SizedBox(width: DizzySpace.xs),
                          DizzyTactileButton(
                            width: 44,
                            height: 42,
                            padding: EdgeInsets.zero,
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: 'dizzy://user/$_username'));
                              DizzyNotify.show(context, 'Profile link copied!',
                                  tone: NotifyTone.success);
                            },
                            child: const Icon(Icons.share_rounded, size: 18, color: DizzyVoid.bone),
                          ),
                        ],
                      ),
                      const SizedBox(height: DizzySpace.md),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    indicatorColor: DizzyGlow.red,
                    indicatorWeight: 3,
                    labelColor: DizzyVoid.bone,
                    unselectedLabelColor: DizzyVoid.ash,
                    tabs: const [
                      Tab(icon: Icon(Icons.play_circle_outline_rounded), text: 'Watching'),
                      Tab(icon: Icon(Icons.bookmark_border_rounded), text: 'Saved'),
                      Tab(icon: Icon(Icons.menu_book_rounded), text: 'Read'),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildWatchingTab(),
              _buildSavedTab(),
              _buildReadTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridPlaceholder(String text) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(color: DizzyVoid.ash, fontSize: 13),
      ),
    );
  }

  /// Tab 1 — Watching: live Continue Watching (tap = resume, ✕ = remove).
  Widget _buildWatchingTab() {
    return ValueListenableBuilder<List<ContinueWatchingItem>>(
      valueListenable: ContinueWatchingService.activeItems,
      builder: (context, items, _) {
        if (items.isEmpty) {
          return _buildGridPlaceholder(
              'Nothing playing yet — start a movie, it shows up here.');
        }
        return _posterGrid(
          count: items.length,
          imageUrl: (i) => items[i].posterUrl ?? items[i].backdropUrl ?? '',
          label: (i) => items[i].title,
          sub: (i) {
            final it = items[i];
            final pct = (it.progressPercent * 100).round();
            if (it.season != null && it.episode != null) {
              return 'S${it.season} E${it.episode} • $pct%';
            }
            return '$pct% watched';
          },
          progress: (i) => items[i].progressPercent,
          onTap: (i) =>
              ContinueWatchingService.resumePlayback(context, items[i]),
          onRemove: (i) => ContinueWatchingService.removeItem(items[i]),
        );
      },
    );
  }

  /// Tab 2 — Saved: My List watchlist (tap = details, ✕ = remove).
  Widget _buildSavedTab() {
    return ValueListenableBuilder<List<MyListItem>>(
      valueListenable: MyListService.items,
      builder: (context, items, _) {
        if (items.isEmpty) {
          return _buildGridPlaceholder(
              'Your Watchlist is empty — save anything to find it here.');
        }
        return _posterGrid(
          count: items.length,
          imageUrl: (i) => items[i].poster ?? '',
          label: (i) => items[i].title,
          sub: (i) => items[i].year?.toString() ?? items[i].type,
          onTap: (i) {
            final it = items[i];
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DetailsPage(
                  movie: Movie(
                    id: it.imdbId ??
                        (it.tmdbId?.toString() ?? it.uniqueKey),
                    name: it.title,
                    poster: it.poster,
                    year: it.year?.toString(),
                    type: it.type,
                    addonBaseUrl: '',
                  ),
                ),
              ),
            );
          },
          onRemove: (i) => MyListService.remove(items[i]),
        );
      },
    );
  }

  /// Tab 3 — Read: manga reading history (tap = resume chapter).
  Widget _buildReadTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: MangaService().getReadingHistory(),
      builder: (context, snap) {
        // Live-refresh when history changes elsewhere.
        return ValueListenableBuilder<int>(
          valueListenable: MangaService.readingHistoryRevision,
          builder: (context, _, __) {
            final history = snap.data ?? const [];
            if (history.isEmpty) {
              final msg = snap.connectionState == ConnectionState.waiting
                  ? 'Loading your manga...'
                  : 'No manga yet — open one, it shows up here.';
              return _buildGridPlaceholder(msg);
            }
            return _posterGrid(
              count: history.length,
              imageUrl: (i) {
                final m = history[i]['manga'];
                if (m is Map) {
                  final s = m['cover_small']?.toString() ?? '';
                  final n = m['cover_normal']?.toString() ?? '';
                  return s.isNotEmpty ? s : n;
                }
                return '';
              },
              label: (i) {
                final m = history[i]['manga'];
                if (m is Map) return m['title']?.toString() ?? 'Manga';
                return 'Manga';
              },
              sub: (i) {
                final ch = history[i]['chapterIndex'];
                return ch is int ? 'Chapter ${ch + 1}' : 'Reading';
              },
              onTap: (i) => _resumeManga(history[i]),
            );
          },
        );
      },
    );
  }

  /// Resume a manga history entry in the reader. Fail-soft, Easy English.
  void _resumeManga(Map<String, dynamic> entry) {
    try {
      final mangaJson = entry['manga'];
      if (mangaJson is! Map) return;
      final manga =
          Manga.fromJson(Map<String, dynamic>.from(mangaJson));
      final chaptersRaw = entry['chapters'];
      final chapters = chaptersRaw is List
          ? chaptersRaw
              .whereType<Map>()
              .map((c) =>
                  MangaChapter.fromJson(Map<String, dynamic>.from(c)))
              .toList()
          : <MangaChapter>[];
      final chapterIndex = entry['chapterIndex'] is int
          ? entry['chapterIndex'] as int
          : 0;
      final pageIndex =
          entry['pageIndex'] is int ? entry['pageIndex'] as int : 0;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MangaReaderPage(
            manga: manga,
            chapters: chapters,
            currentChapterIndex: chapterIndex,
            resumePageIndex: pageIndex,
          ),
        ),
      );
    } catch (_) {
      DizzyNotify.show(context, "Couldn't open that manga right now.",
          tone: NotifyTone.warn);
    }
  }

  /// Shared 3-column poster grid with tap (+ optional long-press remove).
  /// Covers are capped via DizzyImage (no RAM blowups), one ✕ per card.
  Widget _posterGrid({
    required int count,
    required String Function(int) imageUrl,
    required String Function(int) label,
    required String Function(int) sub,
    double Function(int)? progress,
    required void Function(int) onTap,
    void Function(int)? onRemove,
  }) {
    return GridView.builder(
      padding: const EdgeInsets.all(DizzySpace.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: DizzySpace.sm,
        crossAxisSpacing: DizzySpace.sm,
        childAspectRatio: 0.52,
      ),
      itemCount: count,
      itemBuilder: (context, i) {
        final url = imageUrl(i);
        final pct = progress?.call(i);
        return GestureDetector(
          onTap: () => onTap(i),
          onLongPress: onRemove == null ? null : () => onRemove(i),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: url.isNotEmpty
                          ? DizzyImage(
                              imageUrl: url,
                              kind: DizzyImageKind.card,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : Container(
                              color: DizzyVoid.surface2,
                              child: const Center(
                                child: Text('🎬',
                                    style: TextStyle(fontSize: 28)),
                              ),
                            ),
                    ),
                    if (onRemove != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => onRemove(i),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: const Icon(Icons.close_rounded,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    if (pct != null && pct > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(10)),
                          child: LinearProgressIndicator(
                            value: pct.clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: Colors.black54,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                DizzyGlow.red),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label(i),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: DizzyVoid.bone,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                sub(i),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: DizzyVoid.ash, fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: DizzyVoid.voidA,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
