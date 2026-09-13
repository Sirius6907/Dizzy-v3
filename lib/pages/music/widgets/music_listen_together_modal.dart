import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/music/music_listen_together_service.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';

class MusicListenTogetherModal extends StatefulWidget {
  const MusicListenTogetherModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MusicListenTogetherModal(),
    );
  }

  @override
  State<MusicListenTogetherModal> createState() => _MusicListenTogetherModalState();
}

class _MusicListenTogetherModalState extends State<MusicListenTogetherModal> {
  final listenService = MusicListenTogetherService.instance;
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    listenService.isConnected.addListener(_onUpdate);
    listenService.memberCount.addListener(_onUpdate);
  }

  @override
  void dispose() {
    listenService.isConnected.removeListener(_onUpdate);
    listenService.memberCount.removeListener(_onUpdate);
    _codeController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = listenService.isConnected.value;
    final roomCode = listenService.activeRoomCode.value;
    final members = listenService.memberCount.value;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F121C).withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D2EF).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.people_alt_rounded, color: Color(0xFF00D2EF), size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Listen Together',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Real-time synchronized music session with friends',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (isConnected && roomCode != null) ...[
              // Active Room Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D2EF).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00D2EF).withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.radio_rounded, color: Color(0xFF00D2EF), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Room: $roomCode',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D2EF).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$members Listening',
                            style: const TextStyle(
                              color: Color(0xFF00D2EF),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Any song you or your friend plays or pauses stays synchronized in real time! ✨',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: roomCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Room code copied! Share with friends 🚀')),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy Code'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                            foregroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            listenService.leaveRoom();
                          },
                          child: const Text('Leave Room'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Start New Party Button
              MusicHoverable(
                scaleFactor: 1.02,
                child: InkWell(
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    final code = await listenService.createRoom();
                    Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF00D2EF),
                          content: Text('Room $code created! Code copied to clipboard 🎧'),
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C5CFF), Color(0xFF00D2EF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Start Listening Room',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Divider
              const Row(
                children: [
                  Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('OR JOIN A FRIEND', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: Divider(color: Colors.white12)),
                ],
              ),
              const SizedBox(height: 16),

              // Join Code Input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Enter Room Code (e.g. DIZ-8219)',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13, letterSpacing: 0),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF00D2EF)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D2EF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                    onPressed: () async {
                      final code = _codeController.text.trim();
                      if (code.isNotEmpty) {
                        HapticFeedback.mediumImpact();
                        await listenService.joinRoom(code);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF00D2EF),
                              content: Text('Joined Room $code! Syncing music 🎶'),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Join', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
