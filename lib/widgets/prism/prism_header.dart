import 'package:flutter/material.dart';

import '../../../design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';
import 'prism_button.dart';

/// Prism section header (SPEC §3): title 18/700 + "See all" text button.
class PrismSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final Widget? trailing;

  const PrismSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onSeeAll,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final ink = palette.isLight ? PrismLight.ink : PrismDark.ink;
    final soft = palette.isLight ? PrismLight.inkSoft : PrismDark.inkSoft;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PrismLayout.contentPad,
        10,
        PrismSpace.md,
        2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: PrismType.section,
                    fontWeight: PrismType.wBold,
                    letterSpacing: -0.36,
                    height: 1.1,
                    color: ink,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: soft,
                      fontWeight: PrismType.wMedium,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            trailing!,
            if (onSeeAll != null) const SizedBox(width: PrismSpace.xxs),
          ],
          if (onSeeAll != null)
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: onSeeAll,
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: PrismSpace.giant,
                    minHeight: PrismSpace.giant,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See all',
                        style: TextStyle(
                          fontSize: PrismType.body,
                          fontWeight: PrismType.wBold,
                          // Accent *text* token: #E50914 is 4.1:1 on light
                          // clay, below AA at 14px.
                          color: PrismAccent.text(palette.isLight),
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

/// Prism app header, 56px (SPEC §3): title + subtitle, avatar, search,
/// theme toggle. Implements [PreferredSizeWidget] for Scaffold(appBar:).
class PrismAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final Widget? avatar;
  final VoidCallback? onSearchTap;
  final VoidCallback? onAvatarTap;
  final List<Widget>? actions;
  final Widget? leading;

  const PrismAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.avatar,
    this.onSearchTap,
    this.onAvatarTap,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(PrismLayout.headerHeight);

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final ink = palette.isLight ? PrismLight.ink : PrismDark.ink;
    final soft = palette.isLight ? PrismLight.inkSoft : PrismDark.inkSoft;

    return Container(
      height: PrismLayout.headerHeight + MediaQuery.paddingOf(context).top,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + PrismSpace.xxs,
        bottom: PrismSpace.xxs,
        left: PrismSpace.sm,
        right: PrismSpace.sm,
      ),
      color: palette.isLight ? PrismLight.bg : PrismDark.bg,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: PrismSpace.xs),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: PrismType.title,
                    fontWeight: PrismType.wBold,
                    letterSpacing: -0.4,
                    color: ink,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: soft),
                  ),
              ],
            ),
          ),
          if (onSearchTap != null)
            PrismIconButton(
              icon: Icons.search_rounded,
              size: 40,
              tooltip: 'Search',
              onPressed: onSearchTap,
            ),
          ...?actions,
          const SizedBox(width: PrismSpace.xxs),
          GestureDetector(
            onTap: onAvatarTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: PrismSpace.giant,
              height: PrismSpace.giant,
              child: Center(
                child:
                    avatar ??
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [palette.primaryColor, palette.accentColor],
                        ),
                      ),
                      child: Text(
                        title.isNotEmpty ? title[0].toUpperCase() : 'D',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: PrismType.wBold,
                          fontSize: 16,
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
