import 'package:flutter/material.dart';

import '../../services/watchparty/party_voice_service.dart';

/// v1.2.0-T2.8: one-tap voice consent + join (no Settings maze).
/// First voice tap per room → sheet: "Talk while you watch? [Allow] [No thanks]".
/// Allow = join (muted) in one tap. Denied = easy message, party still works.
/// Mic-denied system permission → easy message, never a crash.
class VoiceConsentSheet {
  static final Set<String> _asked = {};

  static Future<void> maybeAsk({
    required BuildContext context,
    required String roomCode,
    bool asHost = false,
  }) async {
    final code = roomCode.trim().toUpperCase();
    if (_asked.contains(code)) return;
    _asked.add(code);
    if (!context.mounted) return;
    final allow = await showModalBottomSheet<bool>(
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
            const Text('🎙️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            const Text(
              'Talk while you watch?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'You join muted. Tap mic to speak.',
              style: TextStyle(color: Colors.white70, fontSize: 13.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('No thanks'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C5CFF),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Allow'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (allow != true) return;
    if (!context.mounted) return;
    final ok =
        await PartyVoiceService.join(roomCode: code, asHost: asHost);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Voice on. You are muted — tap mic to speak.'
            : "Couldn't start voice. Party still works."),
      ),
    );
  }
}
