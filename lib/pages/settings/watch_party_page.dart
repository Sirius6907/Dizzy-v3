import 'package:flutter/material.dart';

import '../../services/cloud/watch_party_service.dart';
import '../../services/theme/app_theme_service.dart';

/// S3C (v1.1.9): Watch Party lobby. Playback screen wiring follows after
/// room create/join is stable; this owns room creation and secure joining.
class WatchPartyPage extends StatefulWidget {
  const WatchPartyPage({super.key});

  @override
  State<WatchPartyPage> createState() => _WatchPartyPageState();
}

class _WatchPartyPageState extends State<WatchPartyPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final available = WatchPartyService.isAvailable;
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        title: const Text('Watch Party',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.primaryColor.withValues(alpha: 0.24),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: palette.primaryColor.withValues(alpha: 0.30)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🍿 Watch together, anywhere',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                    SizedBox(height: 8),
                    Text(
                      'Host a room, share its six-character Room ID, then play, pause and seek in sync. Media streams stay on every viewer’s own device.',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!available)
                _lockedCard(palette)
              else ...[
                _actionCard(
                  palette: palette,
                  icon: Icons.add_circle_outline_rounded,
                  title: 'Create a room',
                  subtitle: 'Public = Room ID only. Private = Room ID + 6-digit pass.',
                  onTap: _busy ? null : _createRoom,
                ),
                const SizedBox(height: 12),
                _actionCard(
                  palette: palette,
                  icon: Icons.login_rounded,
                  title: 'Join a room',
                  subtitle: 'Enter the host’s Room ID. Private rooms also need the pass.',
                  onTap: _busy ? null : _joinRoom,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _lockedCard(dynamic palette) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF11141B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_rounded, color: Colors.white70),
            SizedBox(height: 8),
            Text('Cloud not available',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Watch Party needs a cloud-enabled build. Sync and other features work offline.',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
          ],
        ),
      );

  Widget _actionCard({
    required dynamic palette,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF11141B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(icon, color: palette.primaryColor, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      );

  Future<void> _createRoom() async {
    final title = TextEditingController(text: 'Dizzy Watch Party');
    final pass = TextEditingController();
    var private = false;
    final values = await showDialog<Map<String, String>?>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Create Watch Party'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Room title')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Private room'),
                subtitle: const Text('Requires a custom six-digit pass'),
                value: private,
                onChanged: (v) => setState(() => private = v),
              ),
              if (private)
                TextField(
                  controller: pass,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '6-digit pass'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(c, {
                'title': title.text,
                'private': '$private',
                'pass': pass.text,
              }),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (values == null) return;
    if (values['private'] == 'true' && !WatchPartyService.validPass(values['pass']!)) {
      _snack('Private rooms need exactly 6 digits.');
      return;
    }
    setState(() => _busy = true);
    final room = await WatchPartyService.createRoom(
      title: values['title']!,
      mediaRef: null,
      isPrivate: values['private'] == 'true',
      pass: values['pass'],
    );
    if (mounted) setState(() => _busy = false);
    if (room == null) {
      _snack('Could not create room. Check your sign-in and connection.');
      return;
    }
    _showRoomReady(room);
  }

  Future<void> _joinRoom() async {
    final id = TextEditingController();
    final pass = TextEditingController();
    final values = await showDialog<Map<String, String>?>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Join Watch Party'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: id, maxLength: 6, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Room ID')),
            TextField(controller: pass, maxLength: 6, keyboardType: TextInputType.number, obscureText: true, decoration: const InputDecoration(labelText: 'Private pass (only if needed)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, {'id': id.text, 'pass': pass.text}), child: const Text('Join')),
        ],
      ),
    );
    if (values == null) return;
    setState(() => _busy = true);
    final room = await WatchPartyService.joinRoom(roomId: values['id']!, pass: values['pass']);
    if (mounted) setState(() => _busy = false);
    if (room == null) {
      _snack('Room not found, closed, or the pass is wrong.');
      return;
    }
    _showRoomReady(room);
  }

  void _showRoomReady(WatchPartyRoom room) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Room ready 🎉'),
        content: Text('Room ID: ${room.roomId}\n\nShare this ID. ${room.isPrivate ? 'Also share the private 6-digit pass separately.' : 'This is a public room — no pass needed.'}\n\nPlayback sync controls will activate when a title is launched into this room.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
      ),
    );
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
