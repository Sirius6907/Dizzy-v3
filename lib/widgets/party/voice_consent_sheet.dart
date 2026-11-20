import 'package:flutter/material.dart';

import '../../services/watchparty/party_voice_quality.dart';
import '../../services/watchparty/party_voice_service.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../services/theme/app_theme_service.dart';

/// v1.2.0-T2.8: one-tap voice consent + join (no Settings maze).
/// First voice tap per room → sheet: "Talk while you watch? [Allow] [No thanks]".
/// Allow = join (muted) in one tap. Denied = easy message, party still works.
/// Mic-denied system permission → easy message, never a crash.
///
/// v1.4: the same sheet carries the voice-quality choice, because "join a call"
/// is the one moment where the question is real. It is three chips, not a
/// settings page — and the answer is remembered.
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
    await PartyVoiceQualityService.ensureLoaded();
    if (!context.mounted) return;
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white70;
    final allow = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: isLight ? PrismLight.bg : PrismDark.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎙️', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text(
                'Talk while you watch?',
                style: TextStyle(
                  color: ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You join muted. Tap mic to speak.',
                style: TextStyle(color: inkSoft, fontSize: 13.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _QualityPicker(
                ink: ink,
                inkSoft: inkSoft,
                accent: palette.primaryColor,
                onPick: (q) async {
                  await PartyVoiceQualityService.set(q);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('No thanks', style: TextStyle(color: ink)),
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
      ),
    );
    if (allow != true) return;
    if (!context.mounted) return;
    final ok = await PartyVoiceService.join(roomCode: code, asHost: asHost);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Voice on. You are muted — tap mic to speak.'
              : "Couldn't start voice. Party still works.",
        ),
      ),
    );
  }
}

/// Three chips, one line of explanation. Tapping saves immediately so the
/// next join uses it; the current call keeps its encoding until rejoin.
class _QualityPicker extends StatelessWidget {
  const _QualityPicker({
    required this.ink,
    required this.inkSoft,
    required this.accent,
    required this.onPick,
  });

  final Color ink;
  final Color inkSoft;
  final Color accent;
  final ValueChanged<PartyVoiceQuality> onPick;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PartyVoiceQuality>(
      valueListenable: PartyVoiceQualityService.current,
      builder: (context, selected, _) => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final q in PartyVoiceQuality.values) ...[
                if (q != PartyVoiceQuality.values.first)
                  const SizedBox(width: 8),
                _chip(q, q == selected),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selected.hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: inkSoft, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _chip(PartyVoiceQuality q, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onPick(q),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: active ? accent.withValues(alpha: 0.16) : Colors.transparent,
            border: Border.all(
              color: active ? accent : inkSoft.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            q.label,
            style: TextStyle(
              color: active ? ink : inkSoft,
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
