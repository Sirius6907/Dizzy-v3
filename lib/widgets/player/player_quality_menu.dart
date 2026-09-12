import 'package:flutter/material.dart';
import '../../services/player/quality_service.dart';
import 'player_menu_shell.dart';

/// P7 — Manual quality menu (gear → Quality).
/// Shows Auto + only the qualities this video actually has.
class PlayerQualityMenu extends StatelessWidget {
  final List<QualityChoice> options;
  final QualityChoice current;
  final ValueChanged<QualityChoice> onSelected;
  final VoidCallback onClose;

  const PlayerQualityMenu({
    super.key,
    required this.options,
    required this.current,
    required this.onSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return PlayerMenuShell(
      title: 'QUALITY',
      onClose: onClose,
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final opt in options)
            Builder(builder: (context) {
              final isSelected = opt == current;
              final isAuto = opt == QualityChoice.auto;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelected(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF7C5CFF).withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF7C5CFF).withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.06),
                        width: isSelected ? 1.4 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF7C5CFF)
                                : Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF7C5CFF)
                                  : Colors.white30,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: isSelected
                              ? const Icon(Icons.check_rounded,
                                  size: 13, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isAuto ? '✨' : '🎞️',
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                opt.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              if (isAuto)
                                Text(
                                  'Best for your speed',
                                  style: TextStyle(
                                    color: isSelected
                                        ? const Color(0xFF00D2EF)
                                        : Colors.white.withValues(alpha: 0.4),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
