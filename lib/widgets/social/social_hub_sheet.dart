import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/music/music_listen_together_service.dart';
import '../../services/theme/app_theme_service.dart';

/// UX8 — Unified Social Hub: Watch Together + Listen Together in ONE sheet.
///
/// Shows live room status, member count, 1-tap invite copy.
/// Easy English only. No tech words.
class SocialHubSheet extends StatefulWidget {
  const SocialHubSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SocialHubSheet(),
    );
  }

  @override
  State<SocialHubSheet> createState() => _SocialHubSheetState();
}

class _SocialHubSheetState extends State<SocialHubSheet> {
  final _svc = MusicListenTogetherService.instance;
  final TextEditingController _joinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _svc.isConnected.addListener(_refresh);
    _svc.activeRoomCode.addListener(_refresh);
    _svc.memberCount.addListener(_refresh);
  }

  @override
  void dispose() {
    _svc.isConnected.removeListener(_refresh);
    _svc.activeRoomCode.removeListener(_refresh);
    _svc.memberCount.removeListener(_refresh);
    _joinController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _copyInvite() async {
    final code = _svc.activeRoomCode.value;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite code copied. Send it to friends! 🎉'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final connected = _svc.isConnected.value;
    final code = _svc.activeRoomCode.value;
    final members = _svc.memberCount.value;
    final isHost = _svc.isHost.value;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F121C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: palette.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.group_rounded,
                    color: palette.primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Watch & Listen Together',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'One room. Everyone in sync.',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (connected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$members here',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (!connected) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.primaryColor,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  await _svc.createRoom();
                  _refresh();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Start a room',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _joinController,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Friend’s code (like DIZ-1234)',
                        hintStyle: const TextStyle(
                            color: Colors.white30, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF161A26),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () async {
                      final ok = await _svc
                          .joinRoom(_joinController.text);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? 'Joined! Enjoy together 🎶'
                              : 'That code did not work. Check again.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      _refresh();
                    },
                    child: const Text('Join'),
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161A26),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        palette.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      isHost ? 'Friends join with:' : 'You joined:',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      code ?? '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                palette.primaryColor,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _copyInvite,
                          icon: const Icon(Icons.copy_rounded,
                              size: 18),
                          label: const Text('Copy invite'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () {
                            _svc.leaveRoom();
                            _refresh();
                          },
                          child: const Text('Leave'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'Host plays. All screens follow. Mute anytime. 🎙️',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
