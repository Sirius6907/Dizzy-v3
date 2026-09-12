import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/cloud/watch_party_service.dart';
import '../../services/watchparty/party_session.dart';

/// v1.2.0-T2.8: one-tap Watch Together entry (non-tech flagship).
/// Movie/TV page pe bada button → room auto-create with media prefilled →
/// host session start → caller opens player. Friend ko code + Share milta hai.
class WatchTogetherButton extends StatefulWidget {
  final String mediaRef;
  final String mediaTitle;
  final int? season;
  final int? episode;
  final VoidCallback? onPlayerOpen;

  const WatchTogetherButton({
    super.key,
    required this.mediaRef,
    required this.mediaTitle,
    this.season,
    this.episode,
    this.onPlayerOpen,
  });

  @override
  State<WatchTogetherButton> createState() => _WatchTogetherButtonState();
}

class _WatchTogetherButtonState extends State<WatchTogetherButton> {
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final room = await WatchPartyService.createRoom(
        title: widget.mediaTitle,
        isPrivate: false,
      );
      if (!mounted) return;
      if (room == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Couldn't start Watch Together. Check net, tap Retry."),
          ),
        );
        return;
      }
      PartySession.instance.startAsHost(
        room: room,
        mediaRef: widget.mediaRef,
        mediaTitle: widget.mediaTitle,
        season: widget.season,
        episode: widget.episode,
      );
      // v1.2.0-P1: publish "now watching" so joiners see it (fail-soft).
      // ignore: unawaited_futures
      WatchPartyService.updateCurrentMedia(
        roomId: room.roomId,
        ref: widget.mediaRef,
        title: widget.mediaTitle,
      );
      widget.onPlayerOpen?.call();
      if (!mounted) return;
      _showCodeSheet(room);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showCodeSheet(WatchPartyRoom room) {
    final code = room.roomId;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141A26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👥', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            const Text(
              'Room ready! Friend ko code bhejo.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Code copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C5CFF),
                    ),
                    onPressed: () {
                      // v1.2.0: no share dep — copy full invite text instead.
                      Clipboard.setData(ClipboardData(
                        text:
                            'Join my Watch Together: $code — ${widget.mediaTitle}',
                      ));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Invite copied. Paste it on WhatsApp.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF7C5CFF),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _busy ? null : _start,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Text('👥', style: TextStyle(fontSize: 20)),
        label: Text(
          _busy ? 'Starting...' : 'Watch Together',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
