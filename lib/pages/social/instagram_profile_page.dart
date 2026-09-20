import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_card.dart';
import 'package:dizzy/services/social/dizzy_identity_service.dart';
import 'package:dizzy/services/social/dizzy_social_service.dart';
import 'package:dizzy/services/device/device_id_service.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final code = await DeviceIdService.initialize();
    if (mounted) {
      setState(() {
        _deviceCode = code;
        _username = DizzySocialService.currentUsername.value ?? 'user_${code.toLowerCase()}';
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
            const Text(
              'Sync your Watchlist, history, and friends across phone and PC effortlessly.',
              style: TextStyle(color: DizzyVoid.ash, fontSize: 13),
            ),
            const SizedBox(height: DizzySpace.lg),
            DizzyTactileButton(
              onTap: () {
                Navigator.pop(ctx);
                DizzyNotify.show(context, 'Phone verification challenge sent.',
                    tone: NotifyTone.info);
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
                DizzyNotify.show(context, 'Email login link sent.',
                    tone: NotifyTone.info);
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
                      // Binge Stats Row (3 Columns)
                      const Row(
                        children: [
                          Expanded(
                            child: DizzyTactileCard(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  Text(
                                    '142h',
                                    style: TextStyle(
                                      color: DizzyGlow.beam,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Watched',
                                    style: TextStyle(color: DizzyVoid.ash, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: DizzySpace.xs),
                          Expanded(
                            child: DizzyTactileCard(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              glowColor: DizzyGlow.gold,
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('🔥 ', style: TextStyle(fontSize: 16)),
                                      Text(
                                        '14d',
                                        style: TextStyle(
                                          color: DizzyGlow.gold,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Streak',
                                    style: TextStyle(color: DizzyVoid.ash, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: DizzySpace.xs),
                          Expanded(
                            child: DizzyTactileCard(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  Text(
                                    '86',
                                    style: TextStyle(
                                      color: DizzyGlow.violet,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
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
                              child: Text(
                                DizzyIdentityService.isLinked
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
              _buildGridPlaceholder('No videos in Continue Watching'),
              _buildGridPlaceholder('Your Watchlist is empty'),
              _buildGridPlaceholder('No Manga history yet'),
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
