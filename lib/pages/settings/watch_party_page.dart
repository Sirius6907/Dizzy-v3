import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/cloud/watch_party_service.dart';
import '../../services/device/device_id_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/watchparty/party_session.dart';
import '../../services/watchparty/party_voice_service.dart';
import '../../services/watchparty/guest_auto_open.dart';
import '../../services/watchparty/watch_sync_engine.dart';
import '../../services/guide/guide_service.dart';
import '../../widgets/guide/guide_card.dart';
import '../../widgets/party/voice_consent_sheet.dart';
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
  // Perf: memoized lobby query — parent rebuilds must NOT refire Supabase.
  Future<List<WatchPartyRoom>>? _lobbyFuture;
  bool _lobbyAdult = false;

  /// Returns the cached lobby future, refetching only when the 18+ filter
  /// flips or [invalidateLobby] was called (refresh button / room changes).
  Future<List<WatchPartyRoom>> _lobbyQuery() {
    final adult = WatchPartyService.adultUnlocked.value;
    if (_lobbyFuture == null || adult != _lobbyAdult) {
      _lobbyAdult = adult;
      _lobbyFuture = WatchPartyService.listPublicRooms(showAdult: adult);
    }
    return _lobbyFuture!;
  }

  void _invalidateLobby() {
    _lobbyFuture = null;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // ignore: unawaited_futures
    WatchPartyService.loadPrefs();
    // P13: old 'watch_party' seen-flag migrates to 'party_v2' (no re-nag),
    // then the new 3-card flow shows for fresh users (skipable, never nags).
    // ignore: unawaited_futures
    GuideService.migrateLegacyPartyKey();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GuideCard.maybeShow(context, 'party_v2', AppGuides.partyV2);
    });
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
          // P12: pull-to-refresh the lobby (sweep dead rooms + reload).
          child: RefreshIndicator(
            color: const Color(0xFF8B5CF6),
            backgroundColor: const Color(0xFF11141B),
            onRefresh: () async {
              try {
                await WatchPartyService.sweepStale();
              } catch (_) {}
              _invalidateLobby();
              if (!mounted) return;
              setState(() {});
              try {
                await _lobbyQuery().timeout(const Duration(seconds: 10));
              } catch (_) {}
            },
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
                    onExit: () {
                      _lobbyFuture = null;
                      // v1.2.0-P3: leaving ends the session (stops follow + sync).
                      PartySession.instance.end();
                      setState(() {
                        _activeRoom = null;
                        _activeIsHost = false;
                      });
                    },
                  ),
                ],
              ],
            ],
            ),
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
                onPressed: () {
                  // ignore: unawaited_futures
                  WatchPartyService.sweepStale();
                  _invalidateLobby();
                },
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white54, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!WatchPartyService.isKidsProfile) _adultGate(),
          if (!WatchPartyService.isKidsProfile) const SizedBox(height: 8),
          FutureBuilder<List<WatchPartyRoom>>(
            future: _lobbyQuery(),
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
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rooms.length,
                itemBuilder: (c, i) => _pubTile(palette, rooms[i]),
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
          // P12: red pulse while something plays, dim TV while picking.
          leading: Icon(
              r.isLiveNow
                  ? Icons.radio_button_checked_rounded
                  : Icons.live_tv_rounded,
              color: r.isLiveNow
                  ? Colors.redAccent
                  : palette.primaryColor.withValues(alpha: 0.55),
              size: 28),
          title: Text(r.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          // P12: LIVE watching title + headcount, or the picking state.
          subtitle: Text(
              WatchPartyService.isFull(r.memberCount)
                  ? '${r.roomId} • FULL (${r.memberCount}/${WatchPartyService.maxMembers})'
                  : r.isLiveNow
                      ? '🔴 ${r.watchingLabel} • 👥 ${r.memberCount} watching'
                      : '💭 Choosing… • 👥 ${r.memberCount} in room',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

  /// v1.2.0-P4: host per-user mute sheet (Easy English, no tech words).
  void _showVoiceMembers(BuildContext context) {
    final ids = PartyVoiceService.remoteIds;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141A26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'People in voice',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap mute to silence one person. They can unmute and speak again.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (ids.isEmpty)
                const Text('Nobody else here yet.',
                    style: TextStyle(color: Colors.white60, fontSize: 13)),
              for (final id in ids)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF1E2A3D),
                    child: Icon(Icons.person_rounded,
                        color: Colors.white70, size: 20),
                  ),
                  title: Text(
                    'Friend ${id.length > 6 ? id.substring(id.length - 6) : id}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  trailing: IconButton(
                    tooltip: 'Mute this person',
                    icon: const Icon(Icons.mic_off_rounded,
                        color: Colors.orangeAccent),
                    onPressed: () async {
                      final ok = await PartyVoiceService.muteUser(id);
                      if (c.mounted) Navigator.pop(c);
                      _snack(ok ? 'Muted.' : 'Could not mute. Try again.');
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

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
                    // v1.2.0-P4: deafen — hear nobody, mic locked off.
                    ValueListenableBuilder<bool>(
                      valueListenable: PartyVoiceService.deafened,
                      builder: (c, deaf, _) => IconButton(
                        tooltip: deaf ? 'Undeafen' : 'Deafen (mute all sound)',
                        onPressed: PartyVoiceService.toggleDeafen,
                        icon: Icon(
                          deaf
                              ? Icons.hearing_disabled_rounded
                              : Icons.hearing_rounded,
                          color: deaf ? Colors.orangeAccent : Colors.white54,
                        ),
                      ),
                    ),
                    if (PartyVoiceService.amHost) ...[
                      IconButton(
                        tooltip: 'Mute one person',
                        onPressed: () => _showVoiceMembers(c),
                        icon: const Icon(Icons.manage_accounts_rounded,
                            color: Colors.white54),
                      ),
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
                    ],
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
    // v1.2.0-T2.8: one-tap voice sheet (consent + join together, join-muted).
    // No Settings maze. Denied/failed → party still works (soft).
    if (!mounted) return;
    await VoiceConsentSheet.maybeAsk(
      context: context,
      roomCode: room.roomId,
      asHost: asHost,
    );
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
      _lobbyFuture = null; // joined rooms change member counts
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
              const SizedBox(height: 4),
              // v1.2.0-P1: no media needed — play anything after creating,
              // everyone in the room follows you automatically.
              const Text(
                'No movie needed now. Play anything after — friends follow you.',
                style: TextStyle(fontSize: 12),
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
    if (values['private'] == 'true' && !WatchPartyService.validPass(values['pass']!)) {
      _snack('Private rooms need exactly 6 digits.');
      return;
    }
    setState(() => _busy = true);
    final room = await WatchPartyService.createRoom(
      title: values['title']!,
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
    // v1.2.0-P1: lobby-created host also owns the session (media comes later).
    PartySession.instance.startAsHost(room: room);
    if (mounted) {
      _lobbyFuture = null; // new room must appear in lobby
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
            TextField(
              controller: id,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Room code',
                hintText: 'ABC123',
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.paste_rounded),
                  onPressed: () async {
                    final data =
                        await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text ?? '';
                    if (text.trim().isNotEmpty) {
                      id.text = PartySession.normalizeCode(text);
                    }
                  },
                ),
              ),
              onChanged: (v) {
                final norm = PartySession.normalizeCode(v);
                if (norm != v) {
                  id.value = id.value.copyWith(
                    text: norm,
                    selection:
                        TextSelection.collapsed(offset: norm.length),
                  );
                }
              },
            ),
            TextField(controller: pass, maxLength: 6, keyboardType: TextInputType.number, obscureText: true, decoration: const InputDecoration(labelText: 'Private pass (only if needed)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, {'id': PartySession.normalizeCode(id.text), 'pass': pass.text}), child: const Text('Join')),
        ],
      ),
    );
    if (values == null) return;
    setState(() => _busy = true);
    final room = await WatchPartyService.joinRoom(roomId: values['id']!, pass: values['pass']);
    if (mounted) setState(() => _busy = false);
    if (room == null) {
      // v1.2.0-P5: full rooms get their own easy message (20 max).
      final n = await WatchPartyService.roomMemberCount(values['id']!);
      _snack((n != null && n >= 20)
          ? 'Room is full (20 max). Ask host for a new room.'
          : "Couldn't find this room. Check the code, ask host to resend.");
      return;
    }
    PartySession.instance.startAsGuest(room: room);
    // v1.2.0-P1: guest picks up "now watching" from the row (auto-open lands in P3).
    final nowRef = room.nowWatchingRef;
    if (nowRef != null && nowRef.isNotEmpty) {
      // v1.2.0-P3: mid-title join → same auto-open path as live switches.
      // handle() FIRST (its same-title early-return must see pre-join state),
      // display state right after (handle sets it again on success).
      // ignore: unawaited_futures
      GuestAutoOpen.handle(WatchSyncMessage(
        mediaRef: nowRef,
        mediaTitle: room.currentTitle,
        positionMs: 0,
        playing: true,
        hostSentAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      PartySession.instance.setGuestMedia(
        mediaRef: nowRef,
        mediaTitle: room.currentTitle,
      );
    }
    _showRoomReady(room);
    if (mounted) {
      _lobbyFuture = null; // membership changed
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
    if (ok && mounted) {
      _lobbyFuture = null; // enough reports hide the room
      setState(() {});
    }
  }

  void _showRoomReady(WatchPartyRoom room, {bool asHost = false}) {
    // v1.2.0-T2.8: big code card + Copy/Invite (dead-easy sharing).
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF141A26),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Room ready 🎉',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                room.roomId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              room.isPrivate
                  ? 'Private room — share the 6-digit pass too.'
                  : 'Public room — code is enough, no pass.',
              style: const TextStyle(
                  color: Colors.white60, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
            if (room.isAdult)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('⚠️ 18+ room — viewer discretion advised.',
                    style: TextStyle(
                        color: Colors.orangeAccent, fontSize: 12)),
              ),
            const SizedBox(height: 4),
            const Text(
              'Play a title and all screens follow together.',
              style: TextStyle(color: Colors.white60, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: room.roomId));
              ScaffoldMessenger.of(c).showSnackBar(
                const SnackBar(content: Text('Code copied.')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text:
                    'Join my Watch Together: ${room.roomId} — ${room.title}',
              ));
              ScaffoldMessenger.of(c).showSnackBar(
                const SnackBar(
                  content:
                      Text('Invite copied. Paste it on WhatsApp.'),
                ),
              );
            },
            child: const Text('Invite'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              // ignore: unawaited_futures
              _autoVoice(room, asHost);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
