import 'package:flutter/material.dart';

import '../../design/dizzy_tokens.dart';

/// Polish P5 — co-watch overlay in ONE voice (Easy English, non-tech).
///
/// Two states only (dadi-ma test — bina samjhaye samajh aaye):
/// - catching up: guest is auto-fixing to host (past 5s drift).
/// - paused by host: host ne roka, guest controls locked.
///
/// Pure UI — no Supabase, no timers. Caller decides when to show.
enum PartyOverlayKind { catchingUp, pausedByHost }

class PartyCoWatchOverlay extends StatelessWidget {
  final PartyOverlayKind kind;
  final String? hostTitle;

  const PartyCoWatchOverlay({
    super.key,
    required this.kind,
    this.hostTitle,
  });

  @override
  Widget build(BuildContext context) {
    final isCatching = kind == PartyOverlayKind.catchingUp;
    return Semantics(
      liveRegion: true,
      label: isCatching
          ? 'Catching up with host'
          : 'Paused by host',
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: DizzySpace.lg),
          padding: const EdgeInsets.symmetric(
            horizontal: DizzySpace.md,
            vertical: DizzySpace.sm,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: DizzyRadius.lgAll,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCatching)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  Icons.pause_circle_filled_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              const SizedBox(width: DizzySpace.sm),
              Flexible(
                child: Text(
                  isCatching
                      ? 'Catching up with host…'
                      : hostTitle != null && hostTitle!.trim().isNotEmpty
                          ? 'Host paused • ${hostTitle!.trim()}'
                          : 'Host paused. You just watch.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: DizzyType.body,
                    fontWeight: DizzyType.wSemiBold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
