import 'package:flutter/material.dart';

import '../../services/cloud/cloud_auth_service.dart';
import '../../services/cloud/watch_party_service.dart';
import '../../services/device/device_id_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/watchparty/party_voice_service.dart';
import 'widgets/party_room_panel.dart';

/// S3C (v1.1.9): Watch Party lobby. Playback screen wiring follows after
/// room create/join is stable; this owns room creation and secure joining.
class WatchPartyPage extends StatefulWidget {
  const WatchPartyPage({super.key});

  @override
  State<WatchPartyPage> createState() => _WatchPartyPageState();
}

class _WatchPartyPageState extends State<WatchPartyPage> {
  bool _busy = false;
  WatchPartyRoom? _activeRoom;
  bool _activeIsHost = false;

  @override
  void initState() {
    super.initState();
    // ignore: unawaited_futures
    WatchPartyService.loadPrefs();
  }

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
                _deviceChip(),
                const SizedBox(height: 12),
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
                const SizedBox(height: 20),
                _pubLobby(palette),
                const SizedBox(height: 12),
                _voiceBar(),
                if (_activeRoom != null) ...[
                  const SizedBox(height: 12),
                  PartyRoomPanel(
                    room: _activeRoom!,
                    isHost: _activeIsHost,
                    onExit: () => setState(() {
                      _activeRoom = null;
                      _activeIsHost = false;
                    }),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceChip() => ValueListenableBuilder<String?>(
        valueListenable: DeviceIdService.deviceCode,
        builder: (c, code, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF11141B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              const Icon(Icons.badge_outlined, color: Colors.white54, size: 20),
              const SizedBox(width: 10),
              const Text('My Device ID',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
              const Spacer(),
              Text(
                code == null ? '…' : DeviceIdService.displayCode(code),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2),
              ),
            ],
          ),
        ),
      );

  Widget _pubLobby(dynamic palette) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔴 Live public rooms',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white54, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!WatchPartyService.isKidsProfile) _adultGate(),
          if (!WatchPartyService.isKidsProfile) const SizedBox(height: 8),
          FutureBuilder<List<WatchPartyRoom>>(
            future: WatchPartyService.listPublicRooms(
              showAdult: WatchPartyService.adultUnlocked.value,
            ),
            builder: (c, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final rooms = snap.data ?? const [];
              if (rooms.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF11141B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: const Text(
                    'No public rooms live right now. Create one and it shows up here for everyone.',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                );
              }
              return Column(
                children: [
                  for (final r in rooms)
                    _pubTile(palette, r),
                ],
              );
            },
          ),
        ],
      );

  Widget _adultGate() => ValueListenableBuilder<bool>(
        valueListenable: WatchPartyService.adultUnlocked,
        builder: (c, unlocked, _) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show 18+ rooms',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Age-gated. Kids profiles never see this.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          value: unlocked,
          onChanged: (v) => v ? _confirmAdult() : WatchPartyService.setAdultUnlocked(false).then((_) => setState(() {})),
        ),
      );

  Future<void> _confirmAdult() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm age'),
        content: const Text('I confirm I am 18 or older and want to see 18+ public rooms.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('I am 18+')),
        ],
      ),
    );
    if (ok == true) {
      await WatchPartyService.setAdultUnlocked(true);
      if (mounted) setState(() {});
    }
  }

  Widget _pubTile(dynamic palette, WatchPartyRoom r) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF11141B),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ListTile(
          leading: Icon(Icons.live_tv_rounded,
              color: palette.primaryColor, size: 28),
          title: Text(r.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          subtitle: Text(
              WatchPartyService.isFull(r.memberCount)
                  ? '${r.roomId} • FULL (${r.memberCount}/${WatchPartyService.maxMembers})'
                  : '${r.roomId} • ${r.memberCount} watching • ${r.status}',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.isAdult)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Text('18+',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
              IconButton(
                tooltip: 'Report room',
                onPressed: () => _reportRoom(r),
                icon: const Icon(Icons.flag_outlined,
                    color: Colors.white38, size: 20),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white54),
            ],
          ),
          onTap: _busy
              ? null
              : () {
                  if (WatchPartyService.isFull(r.memberCount)) {
                    _snack(
                        'Room is full (${WatchPartyService.maxMembers} max).');
                    return;
                  }
                  _joinPublic(r);
                },
        ),
      );

  Widget _voiceBar() => ValueListenableBuilder<bool>(
        valueListenable: PartyVoiceService.connected,
        builder: (c, connected, _) {
          if (!connected) return const SizedBox.shrink();
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0E2A1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.greenAccent.withValues(alpha: 0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: PartyVoiceService.memberCount,
                      builder: (c, n, _) => Text(
                        '🔊 Voice • $n in channel',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(),
                    ValueListenableBuilder<bool>(
                      valueListenable: PartyVoiceService.micOn,
                      builder: (c, on, _) => IconButton(
                        tooltip: on ? 'Mute mic' : 'Unmute mic',
                        onPressed: PartyVoiceService.toggleMic,
                        icon: Icon(
                          on ? Icons.mic_rounded : Icons.mic_off_rounded,
                          color: on ? Colors.greenAccent : Colors.white54,
                        ),
                      ),
                    ),
                    if (PartyVoiceService.amHost)
                      IconButton(
                        tooltip: 'Mute everyone',
                        onPressed: () async {
                          final ok =
                              await PartyVoiceService.muteAll();
                          _snack(ok
                              ? 'Everyone muted.'
                              : 'Mute-all failed.');
                        },
                        icon: const Icon(Icons.volume_off_rounded,
                            color: Colors.white54),
                      ),
                    IconButton(
                      tooltip: 'Leave voice',
                      onPressed: () => PartyVoiceService.leave(),
                      icon: const Icon(Icons.call_end_rounded,
                          color: Colors.redAccent),
                    ),
                  ],
                ),
                ValueListenableBuilder<Set<String>>(
                  valueListenable: PartyVoiceService.speakingIds,
                  builder: (c, ids, _) => ids.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '🗣️ ${ids.length} speaking…',
                            style: const TextStyle(
                                color: Colors.greenAccent, fontSize: 12),
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      );

  Future<void> _autoVoice(WatchPartyRoom room, bool asHost) async {
    // WP-P5: voice needs the explicit watch-party consent (mic = PII-adjacent).
    if (!CloudAuthService.consentWatchParty.value) {
      _snack('Enable Watch Party voice in Settings → Privacy first.');
      return;
    }
    final ok = await PartyVoiceService.join(
        roomCode: room.roomId, asHost: asHost);
    _snack(ok
        ? 'Voice joined (muted). Tap the mic to speak.'
        : 'Voice unavailable — check LiveKit setup. Party still works.');
    if (mounted) setState(() {});
  }

  Future<void> _joinPublic(WatchPartyRoom r) async {
    setState(() => _busy = true);
    final room = await WatchPartyService.joinRoom(roomId: r.roomId);
    if (mounted) setState(() => _busy = false);
    if (room == null) {
      _snack('Could not join ${r.roomId}. It may have just closed.');
      return;
    }
    _showRoomReady(room);
    if (mounted) {
      setState(() {
        _activeRoom = room;
        _activeIsHost = false;
      });
    }
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
    final media = TextEditingController();
    final pass = TextEditingController();
    var private = false;
    var adult = false;
    final values = await showDialog<Map<String, String>?>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Create Watch Party'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Room title')),
              TextField(
                controller: media,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  labelText: 'Media ref (TMDB/IMDB id) *',
                  hintText: 'e.g. tmdb:movie:550',
                ),
              ),
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
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('This is 18+ content'),
                subtitle: const Text('Required. Wrong marking + 3 reports hides the room.'),
                value: adult,
                onChanged: (v) => setState(() => adult = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(c, {
                'title': title.text,
                'media': media.text,
                'private': '$private',
                'pass': pass.text,
                'adult': '$adult',
              }),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (values == null) return;
    if ((values['media'] ?? '').trim().isEmpty) {
      _snack('Attach what you are playing first — media ref is required to host.');
      return;
    }
    if (values['private'] == 'true' && !WatchPartyService.validPass(values['pass']!)) {
      _snack('Private rooms need exactly 6 digits.');
      return;
    }
    setState(() => _busy = true);
    final room = await WatchPartyService.createRoom(
      title: values['title']!,
      mediaRef: values['media']!.trim(),
      isPrivate: values['private'] == 'true',
      pass: values['pass'],
      isAdult: values['adult'] == 'true',
    );
    if (mounted) setState(() => _busy = false);
    if (room == null) {
      _snack('Could not create room. Check your sign-in and connection.');
      return;
    }
    _showRoomReady(room, asHost: true);
    if (mounted) {
      setState(() {
        _activeRoom = room;
        _activeIsHost = true;
      });
    }
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
    if (mounted) {
      setState(() {
        _activeRoom = room;
        _activeIsHost = false;
      });
    }
  }

  Future<void> _reportRoom(WatchPartyRoom r) async {
    final ok = await WatchPartyService.reportRoom(r.roomId);
    _snack(ok
        ? 'Reported. 3+ reports hides this room for everyone.'
        : 'Could not report. Try again.');
    if (ok && mounted) setState(() {});
  }

  void _showRoomReady(WatchPartyRoom room, {bool asHost = false}) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Room ready 🎉'),
        content: Text('Room ID: ${room.roomId}\n\nShare this ID. ${room.isPrivate ? 'Also share the private 6-digit pass separately.' : 'This is a public room — no pass needed.'}${room.isAdult ? '\n\n⚠️ 18+ room — viewer discretion advised.' : ''}\n\nPlayback sync controls will activate when a title is launched into this room.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              // ignore: unawaited_futures
              _autoVoice(room, asHost);
            },
            child: const Text('Done — join voice (muted)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Skip voice'),
          ),
        ],
      ),
    );
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
