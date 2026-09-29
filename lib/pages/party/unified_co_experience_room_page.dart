import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/services/watchparty/party_session.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_card.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import '../../widgets/common/offline_aware_scaffold.dart';

/// Unified tactile OLED co-experience room for the 3 modes:
/// Mode 1: Watch Together · Mode 2: Listen Together · Mode 3: Read Together.
///
/// High-performance by construction: pure-math tactile surfaces
/// (gradients + static shadows), zero BackdropFilter / shader cost,
/// RepaintBoundary-isolated animated islands, const static content.
enum CoExperienceMode { watch, listen, read }

class UnifiedCoExperienceRoomPage extends StatefulWidget {
  final CoExperienceMode initialMode;

  const UnifiedCoExperienceRoomPage({
    super.key,
    this.initialMode = CoExperienceMode.watch,
  });

  @override
  State<UnifiedCoExperienceRoomPage> createState() =>
      _UnifiedCoExperienceRoomPageState();
}

class _VoicePeer {
  final String name;
  final Color color;
  const _VoicePeer(this.name, this.color);
}

const _voicePeers = <_VoicePeer>[
  _VoicePeer('You', DizzyGlow.beam),
  _VoicePeer('Aria', DizzyGlow.violet),
  _VoicePeer('Kabir', DizzyGlow.gold),
  _VoicePeer('Zoya', DizzyGlow.volt),
];

const _lyricsPreview = <String>[
  'Neon hum on an empty street,',
  'we press play and the night repeats —',
  'every chorus pulling us near,',
  'your voice the only sound I hear.',
];

class _UnifiedCoExperienceRoomPageState
    extends State<UnifiedCoExperienceRoomPage>
    with SingleTickerProviderStateMixin {
  late CoExperienceMode _mode;
  late final AnimationController _spinController;
  late final TextEditingController _queueController;

  final List<String> _queue = <String>[
    'Midnight Static — Neon Coast',
    'Paper Moons — Aria Vale',
    'Low Orbit Lullaby — KAIRO',
  ];
  int _speakingIndex = 0;
  bool _muted = false;
  bool _spinning = true;

  static String _kindFor(CoExperienceMode mode) {
    switch (mode) {
      case CoExperienceMode.watch:
        return 'video';
      case CoExperienceMode.listen:
        return 'audio';
      case CoExperienceMode.read:
        return 'book';
    }
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _queueController = TextEditingController();
    // Seed shared session state once (post-frame: session is a ChangeNotifier).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PartySession.instance.setMediaKind(_kindFor(_mode));
    });
  }

  @override
  void dispose() {
    _spinController.dispose();
    _queueController.dispose();
    super.dispose();
  }

  void _switchMode(CoExperienceMode mode) {
    if (_mode == mode) return;
    HapticFeedback.selectionClick();
    setState(() => _mode = mode);
    PartySession.instance.setMediaKind(_kindFor(mode));
  }

  void _copyRoomCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Room code $code copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // P6 narrow compact: 360px pe long title + room-code pill tight hote hain.
    final narrow = MediaQuery.sizeOf(context).width < 420;
    return OfflineAwareScaffold(
      backgroundColor: DizzyVoid.obsidian,
      appBar: AppBar(
        backgroundColor: DizzyVoid.voidB,
        foregroundColor: DizzyVoid.bone,
        title: Text(
          narrow ? 'Co-Room' : 'Co-Experience Room',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          ListenableBuilder(
            listenable: PartySession.instance,
            builder: (context, _) {
              final room = PartySession.instance.room;
              final code = room == null || room.roomId.isEmpty
                  ? 'LOBBY'
                  : room.roomId.toUpperCase();
              return Padding(
                padding: const EdgeInsets.only(right: DizzySpace.sm),
                child: Center(
                  child: GestureDetector(
                    onTap: () => _copyRoomCode(code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DizzySpace.sm,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(DizzyRadius.md),
                        gradient: DizzyGradients.tactileSurface,
                        border: Border.fromBorderSide(DizzyEdge.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: DizzyGlow.red,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            code,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: DizzyVoid.bone,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.copy_rounded,
                            size: 13,
                            color: DizzyVoid.ash,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ModeSwitcher(mode: _mode, onSelect: _switchMode),
            const _VoiceStripLabel(),
            _VoiceStrip(
              speakingIndex: _speakingIndex,
              muted: _muted,
              onPeerTap: (i) {
                HapticFeedback.selectionClick();
                setState(() => _speakingIndex = i);
              },
              onMuteToggle: () {
                HapticFeedback.lightImpact();
                setState(() => _muted = !_muted);
              },
            ),
            Expanded(
              child: RepaintBoundary(
                child: switch (_mode) {
                  CoExperienceMode.watch => _WatchTogetherBody(
                      onCopyCode: _copyRoomCode,
                    ),
                  CoExperienceMode.listen => _ListenTogetherBody(
                      spinning: _spinning,
                      spin: _spinController,
                      queue: _queue,
                      queueController: _queueController,
                      onToggleSpin: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _spinning = !_spinning;
                          if (_spinning) {
                            _spinController.repeat();
                          } else {
                            _spinController.stop();
                          }
                        });
                      },
                      onAddTrack: _addTrack,
                      onPlayTrack: _playTrack,
                      onRemoveTrack: _removeTrack,
                    ),
                  CoExperienceMode.read => const _ReadTogetherBody(),
                },
              ),
            ),
            const _PresenterBar(),
          ],
        ),
      ),
    );
  }

  void _addTrack() {
    final text = _queueController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _queue.add(text);
      _queueController.clear();
    });
  }

  void _playTrack(int index) {
    HapticFeedback.selectionClick();
    PartySession.instance.setTrackId(_queue[index]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Queued live: ${_queue[index]}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _removeTrack(int index) {
    HapticFeedback.lightImpact();
    setState(() => _queue.removeAt(index));
  }
}

// ─── Mode switcher ───

class _ModeSwitcher extends StatelessWidget {
  final CoExperienceMode mode;
  final ValueChanged<CoExperienceMode> onSelect;

  const _ModeSwitcher({required this.mode, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DizzySpace.md,
        DizzySpace.sm,
        DizzySpace.md,
        DizzySpace.xs,
      ),
      child: Row(
        children: [
          for (final m in CoExperienceMode.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DizzyTactileButton(
                  isSelected: mode == m,
                  onTap: () => onSelect(m),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        switch (m) {
                          CoExperienceMode.watch => Icons.play_circle_rounded,
                          CoExperienceMode.listen => Icons.album_rounded,
                          CoExperienceMode.read => Icons.menu_book_rounded,
                        },
                        size: 16,
                        color: mode == m ? DizzyVoid.bone : DizzyVoid.ash,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        switch (m) {
                          CoExperienceMode.watch => 'Watch',
                          CoExperienceMode.listen => 'Listen',
                          CoExperienceMode.read => 'Read',
                        },
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: mode == m ? DizzyVoid.bone : DizzyVoid.ash,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Shared voice strip ───

class _VoiceStripLabel extends StatelessWidget {
  const _VoiceStripLabel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        DizzySpace.md,
        DizzySpace.xs,
        DizzySpace.md,
        0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'VOICE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
            color: DizzyVoid.ash,
          ),
        ),
      ),
    );
  }
}

class _VoiceStrip extends StatelessWidget {
  final int speakingIndex;
  final bool muted;
  final ValueChanged<int> onPeerTap;
  final VoidCallback onMuteToggle;

  const _VoiceStrip({
    required this.speakingIndex,
    required this.muted,
    required this.onPeerTap,
    required this.onMuteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DizzySpace.md,
          vertical: DizzySpace.xs,
        ),
        itemCount: _voicePeers.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: DizzySpace.sm),
        itemBuilder: (context, i) {
          if (i == _voicePeers.length) {
            return GestureDetector(
              onTap: onMuteToggle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: muted
                          ? DizzyGradients.emberButton
                          : DizzyGradients.tactileSurface,
                      border: Border.fromBorderSide(DizzyEdge.hairline),
                    ),
                    child: Icon(
                      muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      size: 20,
                      color: DizzyVoid.bone,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    muted ? 'Muted' : 'Mute',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: DizzyVoid.ash,
                    ),
                  ),
                ],
              ),
            );
          }
          final peer = _voicePeers[i];
          final speaking = i == speakingIndex && !muted;
          return GestureDetector(
            onTap: () => onPeerTap(i),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: DizzyGradients.tactileSurface,
                    border: Border.fromBorderSide(
                      speaking
                          ? DizzyEdge.neon(DizzyGlow.volt)
                          : DizzyEdge.hairline,
                    ),
                    boxShadow: speaking
                        ? [
                            BoxShadow(
                              color: DizzyGlow.volt.withValues(alpha: 0.35),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    peer.name.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: peer.color,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  peer.name,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: speaking ? DizzyVoid.bone : DizzyVoid.ash,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Mode 1: Watch Together ───

class _WatchTogetherBody extends StatelessWidget {
  final ValueChanged<String> onCopyCode;

  const _WatchTogetherBody({required this.onCopyCode});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PartySession.instance,
      builder: (context, _) {
        final session = PartySession.instance;
        final room = session.room;
        final code = room == null || room.roomId.isEmpty
            ? 'LOBBY'
            : room.roomId.toUpperCase();
        final title = session.mediaTitle ??
            room?.watchingLabel ??
            'Nothing on yet — pick a title';
        return ListView(
          padding: const EdgeInsets.all(DizzySpace.md),
          children: [
            DizzyTactileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: DizzyGlow.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'LIVE ROOM',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                          color: DizzyVoid.ash,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => onCopyCode(code),
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                            color: DizzyVoid.bone,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DizzySpace.sm),
                  Text(
                    room?.title ?? 'Watch Together',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: DizzyVoid.bone,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${room?.memberCount ?? 1} in room · ${session.isHost ? 'You host' : 'Guest view'}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: DizzyVoid.ash,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DizzySpace.sm),
            DizzyTactileCard(
              child: Row(
                children: [
                  Container(
                    width: 84,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(DizzyRadius.md),
                      gradient: DizzyGradients.beamButton,
                      border: Border.fromBorderSide(DizzyEdge.hairline),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 40,
                      color: DizzyVoid.bone,
                    ),
                  ),
                  const SizedBox(width: DizzySpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NOW PREVIEWING',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.8,
                            color: DizzyVoid.ash,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: DizzyVoid.bone,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          session.mediaRef ?? 'No media synced yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DizzyVoid.ash,
                          ),
                        ),
                        const SizedBox(height: DizzySpace.sm),
                        DizzyTactileButton(
                          onTap: session.isHost
                              ? () {
                                  HapticFeedback.mediumImpact();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Host sync pulse sent'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                }
                              : null,
                          child: Text(
                            session.isHost ? 'SYNC EVERYONE' : 'FOLLOWING HOST',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                              color: DizzyVoid.bone,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Mode 2: Listen Together ───

class _ListenTogetherBody extends StatelessWidget {
  final bool spinning;
  final Animation<double> spin;
  final List<String> queue;
  final TextEditingController queueController;
  final VoidCallback onToggleSpin;
  final VoidCallback onAddTrack;
  final ValueChanged<int> onPlayTrack;
  final ValueChanged<int> onRemoveTrack;

  const _ListenTogetherBody({
    required this.spinning,
    required this.spin,
    required this.queue,
    required this.queueController,
    required this.onToggleSpin,
    required this.onAddTrack,
    required this.onPlayTrack,
    required this.onRemoveTrack,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(DizzySpace.md),
      children: [
        DizzyTactileCard(
          child: Row(
            children: [
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: spin,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: spin.value * 6.28318,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF262B3A), DizzyColors.bg],
                      ),
                      border: Border.fromBorderSide(DizzyEdge.hairline),
                    ),
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: DizzyGlow.red,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.music_note_rounded,
                          size: 18,
                          color: DizzyVoid.bone,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: DizzySpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LYRICS PREVIEW',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                        color: DizzyVoid.ash,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final line in _lyricsPreview)
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                          color: DizzyVoid.bone,
                        ),
                      ),
                    const SizedBox(height: DizzySpace.sm),
                    DizzyTactileButton(
                      onTap: onToggleSpin,
                      child: Text(
                        spinning ? 'PAUSE VINYL' : 'SPIN VINYL',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          color: DizzyVoid.bone,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DizzySpace.sm),
        const Text(
          'COLLABORATIVE QUEUE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
            color: DizzyVoid.ash,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DizzySpace.sm,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DizzyRadius.md),
                  gradient: DizzyGradients.carvedSurface,
                  border: Border.fromBorderSide(DizzyEdge.hairline),
                ),
                child: TextField(
                  controller: queueController,
                  style: const TextStyle(
                    color: DizzyVoid.bone,
                    fontSize: 13.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Add a track…',
                    hintStyle: TextStyle(color: DizzyVoid.ash, fontSize: 13),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => onAddTrack(),
                ),
              ),
            ),
            const SizedBox(width: DizzySpace.sm),
            DizzyTactileButton(
              onTap: onAddTrack,
              child: const Icon(
                Icons.add_rounded,
                size: 20,
                color: DizzyVoid.bone,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ListenableBuilder(
          listenable: PartySession.instance,
          builder: (context, _) {
            final active = PartySession.instance.trackId;
            return Column(
              children: [
                for (var i = 0; i < queue.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: DizzyTactileCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DizzySpace.sm,
                        vertical: DizzySpace.xs,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            active == queue[i]
                                ? Icons.equalizer_rounded
                                : Icons.music_note_outlined,
                            size: 18,
                            color: active == queue[i]
                                ? DizzyGlow.volt
                                : DizzyVoid.ash,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              queue[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: DizzyVoid.bone,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              color: DizzyVoid.bone,
                              size: 20,
                            ),
                            tooltip: 'Play for room',
                            onPressed: () => onPlayTrack(i),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: DizzyVoid.ash,
                              size: 18,
                            ),
                            tooltip: 'Remove',
                            onPressed: () => onRemoveTrack(i),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Mode 3: Read Together ───

class _ReadTogetherBody extends StatelessWidget {
  const _ReadTogetherBody();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PartySession.instance,
      builder: (context, _) {
        final session = PartySession.instance;
        final page = session.pageIndex + 1;
        return ListView(
          padding: const EdgeInsets.all(DizzySpace.md),
          children: [
            DizzyTactileCard(
              glowColor: session.isHost ? DizzyGlow.gold : null,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: DizzyGradients.tactileSurface,
                      border: Border.fromBorderSide(
                        session.isHost
                            ? DizzyEdge.neon(DizzyGlow.gold)
                            : DizzyEdge.hairline,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      session.isHost
                          ? Icons.record_voice_over_rounded
                          : Icons.headset_mic_outlined,
                      size: 20,
                      color: session.isHost
                          ? DizzyGlow.gold
                          : DizzyVoid.ash,
                    ),
                  ),
                  const SizedBox(width: DizzySpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.isHost
                              ? 'YOU ARE PRESENTING'
                              : 'HOST IS PRESENTING',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: DizzyVoid.bone,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session.isHost
                              ? 'Everyone follows your page turns'
                              : 'Your pages auto-follow the presenter',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DizzyVoid.ash,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: DizzyGlow.volt.withValues(alpha: 0.14),
                      border: Border.fromBorderSide(DizzyEdge.neon(DizzyGlow.volt)),
                    ),
                    child: const Text(
                      'SYNCED',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: DizzyGlow.volt,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DizzySpace.sm),
            DizzyTactileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'CHAPTER SYNC',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.8,
                          color: DizzyVoid.ash,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Ch ${session.chapterIndex + 1}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: DizzyVoid.bone,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DizzySpace.xs),
                  Text(
                    session.mediaTitle ?? 'Shared manuscript',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: DizzyVoid.bone,
                    ),
                  ),
                  const SizedBox(height: DizzySpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: DizzyTactileButton(
                          onTap: session.chapterIndex > 0
                              ? () {
                                  HapticFeedback.lightImpact();
                                  session.setChapterIndex(
                                    session.chapterIndex - 1,
                                  );
                                }
                              : null,
                          child: const Text(
                            '− CHAPTER',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: DizzyVoid.bone,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: DizzySpace.sm),
                      Expanded(
                        child: DizzyTactileButton(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            session.setChapterIndex(
                              session.chapterIndex + 1,
                            );
                          },
                          child: const Text(
                            '+ CHAPTER',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: DizzyVoid.bone,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: DizzySpace.sm),
            DizzyTactileCard(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(DizzySpace.md),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(DizzyRadius.md),
                      color: const Color(0xFFF5F1E6),
                      border: Border.fromBorderSide(DizzyEdge.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Page $page',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                            color: Color(0xFF8A7D5B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'The room breathes as one — every reader lands on the same line at the same time. Turn the page and the whole circle follows.',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.65,
                            color: Color(0xFF23242B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DizzySpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: DizzyTactileButton(
                          onTap: session.pageIndex > 0
                              ? () {
                                  HapticFeedback.lightImpact();
                                  session.setPageIndex(session.pageIndex - 1);
                                }
                              : null,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.arrow_back_rounded,
                                size: 18,
                                color: DizzyVoid.bone,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'PREV',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                  color: DizzyVoid.bone,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: DizzySpace.sm),
                      Expanded(
                        child: DizzyTactileButton(
                          glowColor: DizzyGlow.beam,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            session.setPageIndex(session.pageIndex + 1);
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'NEXT',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                  color: DizzyVoid.bone,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: DizzyVoid.bone,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Bottom presenter bar ───

class _PresenterBar extends StatelessWidget {
  const _PresenterBar();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PartySession.instance,
      builder: (context, _) {
        final session = PartySession.instance;
        return Container(
          margin: const EdgeInsets.fromLTRB(
            DizzySpace.md,
            DizzySpace.xs,
            DizzySpace.md,
            DizzySpace.md,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DizzySpace.md,
            vertical: DizzySpace.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DizzyRadius.lg),
            gradient: DizzyGradients.tactileSurface,
            border: Border.fromBorderSide(DizzyEdge.hairline),
            boxShadow: DizzyShadow.card,
          ),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: session.inParty ? DizzyGlow.volt : DizzyVoid.ash,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.inParty
                      ? (session.isHost
                          ? 'Presenting · ${session.mediaKind}'
                          : 'Following host · ${session.mediaKind}')
                      : 'Preview mode · no live room',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: DizzyVoid.bone,
                  ),
                ),
              ),
              if (session.inParty)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    session.end();
                  },
                  child: const Text(
                    'LEAVE',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: DizzyGlow.red,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
