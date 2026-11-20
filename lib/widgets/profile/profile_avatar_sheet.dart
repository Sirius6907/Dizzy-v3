import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/dizzy_tactile.dart';
import '../../design/prism_tokens.dart';
import '../../services/social/profile_avatar_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../common/notify.dart';
import '../tactile/dizzy_tactile_button.dart';
import 'profile_avatar.dart';

/// One sheet, three entry points: the header avatar, the "Profile photo"
/// row in the account hub, and the first-run name screen. It only ever
/// offers two real actions — choose a picture, or drop the one you have —
/// because a photo is optional and the monogram is a fine answer.
class ProfileAvatarSheet extends StatefulWidget {
  const ProfileAvatarSheet({super.key, this.username});

  final String? username;

  /// Opens the sheet. Safe to call from anywhere; a tap that arrives while
  /// the sheet is already up is ignored rather than stacking two sheets.
  static Future<void> show(BuildContext context, {String? username}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => ProfileAvatarSheet(username: username),
    );
  }

  @override
  State<ProfileAvatarSheet> createState() => _ProfileAvatarSheetState();
}

class _ProfileAvatarSheetState extends State<ProfileAvatarSheet> {
  bool _busy = false;

  Future<void> _choose() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await ProfileAvatarService.pick();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      DizzyNotify.show(context, error, tone: NotifyTone.warn);
      return;
    }
    // Only close when something actually landed — a cancelled picker keeps
    // the sheet open so the person can try again without hunting for it.
    if (ProfileAvatarService.hasPhoto) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      DizzyNotify.show(context, 'Profile photo updated ✓', tone: NotifyTone.success);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ProfileAvatarService.remove();
    if (!mounted) return;
    setState(() => _busy = false);
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    DizzyNotify.show(context, 'Back to your initials.', tone: NotifyTone.info);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final panel = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final hairline =
        isLight ? PrismLight.borderSubtle : Colors.white.withValues(alpha: 0.08);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: PrismLayout.contentPad,
          right: PrismLayout.contentPad,
          bottom: PrismSpace.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            PrismSpace.lg,
            PrismSpace.lg,
            PrismSpace.lg,
            PrismSpace.lg,
          ),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: PrismRadius.xlAll,
            border: Border.all(color: hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.16 : 0.45),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ValueListenableBuilder<String?>(
            valueListenable: ProfileAvatarService.path,
            builder: (context, path, _) {
              final hasPhoto = (path ?? '').isNotEmpty;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Grab handle — small, centred, no label.
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: inkSoft.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: PrismSpace.lg),
                  Text(
                    'Profile photo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ink,
                      fontSize: PrismType.title,
                      fontWeight: PrismType.wBold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: PrismSpace.xs),
                  Text(
                    hasPhoto
                        ? 'Your photo stays on this device.'
                        : 'Optional — your initials work just as well.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: inkSoft,
                      fontSize: PrismType.caption,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: PrismSpace.xl),
                  Center(
                    child: ProfileAvatar(
                      size: 104,
                      username: widget.username,
                      editable: false,
                    ),
                  ),
                  const SizedBox(height: PrismSpace.xl),
                  DizzyTactileButton(
                    height: 46,
                    onTap: _busy ? null : _choose,
                    gradient: DizzyGradients.emberButton,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_busy)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        else
                          const Icon(
                            Icons.photo_library_rounded,
                            size: 18,
                            color: PrismAccent.onAccent,
                          ),
                        const SizedBox(width: PrismSpace.xs),
                        Text(
                          hasPhoto ? 'Choose another' : 'Choose from device',
                          style: const TextStyle(
                            color: PrismAccent.onAccent,
                            fontWeight: PrismType.wBold,
                            fontSize: PrismType.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasPhoto) ...[
                    const SizedBox(height: PrismSpace.sm),
                    DizzyTactileButton(
                      height: 44,
                      onTap: _busy ? null : _remove,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: PrismAccent.danger,
                          ),
                          SizedBox(width: PrismSpace.xs),
                          Text(
                            'Remove photo',
                            style: TextStyle(
                              color: PrismAccent.danger,
                              fontWeight: PrismType.wSemiBold,
                              fontSize: PrismType.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: PrismSpace.xs),
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Not now',
                      style: TextStyle(
                        color: inkSoft,
                        fontWeight: PrismType.wSemiBold,
                        fontSize: PrismType.body,
                      ),
                    ),
                  ),
                  const SizedBox(height: PrismSpace.xxs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 12,
                        color: DizzyGlow.volt.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'JPG or PNG · never uploaded',
                        style: TextStyle(
                          color: inkSoft.withValues(alpha: 0.85),
                          fontSize: PrismType.micro,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
