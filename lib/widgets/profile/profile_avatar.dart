import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/dizzy_tactile.dart';
import '../../design/dizzy_tokens.dart';
import '../../design/prism_tokens.dart';
import '../../services/social/profile_avatar_service.dart';
import '../../services/theme/app_theme_service.dart';

/// The one avatar the app draws everywhere: the person's own picture when
/// they added one, otherwise an initials monogram on a fixed gradient (so
/// the same name always gets the same colours). Listens to
/// [ProfileAvatarService.path], so choosing a photo updates every avatar
/// on screen without any screen-level plumbing.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.size = 92,
    this.username,
    this.editable = false,
    this.onTap,
    this.showRing = true,
  });

  final double size;
  final String? username;

  /// Draws the small camera chip — the visual promise that tapping works.
  final bool editable;
  final VoidCallback? onTap;

  /// Off in dense lists where a gradient ring would read as a badge.
  final bool showRing;

  static const _ringWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final scaffold = AppThemeService.currentPalette.value.scaffoldBackgroundColor;
    final accent = PrismAccent.text(isLight);

    return Semantics(
      button: onTap != null,
      label: onTap != null ? 'Change profile photo' : 'Profile photo',
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Soft accent halo, not a shader: one blurred shadow.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: isLight ? 0.16 : 0.28),
                        blurRadius: size * 0.22,
                        offset: Offset(0, size * 0.06),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  padding: EdgeInsets.all(showRing ? _ringWidth + 1 : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: showRing
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: 0.85),
                              DizzyGlow.gold.withValues(alpha: 0.65),
                            ],
                          )
                        : null,
                  ),
                  child: ClipOval(
                    child: ValueListenableBuilder<String?>(
                      valueListenable: ProfileAvatarService.path,
                      builder: (context, path, _) {
                        final f = (path == null || path.isEmpty)
                            ? null
                            : File(path);
                        if (f == null) return _monogram(isLight);
                        return Image.file(
                          f,
                          fit: BoxFit.cover,
                          width: size,
                          height: size,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => _monogram(isLight),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (editable)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: size * 0.32,
                    height: size * 0.32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PrismAccent.accent,
                      border: Border.all(color: scaffold, width: 2.4),
                      boxShadow: [
                        BoxShadow(
                          color: PrismAccent.accent.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.photo_camera_rounded,
                      size: size * 0.16,
                      color: PrismAccent.onAccent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monogram(bool isLight) {
    const pairs = DizzyColors.avatarPairs;
    final seed = (username ?? '').trim().toLowerCase();
    // Stable hash: the same name keeps its colours across launches.
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final pair = pairs[hash % pairs.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pair,
        ),
      ),
      child: Text(
        avatarInitial(username),
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: PrismType.wBold,
          height: 1,
          letterSpacing: -size * 0.01,
          color: Colors.white,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: size * 0.08,
              offset: Offset(0, size * 0.02),
            ),
          ],
        ),
      ),
    );
  }
}
