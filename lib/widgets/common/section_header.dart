import 'package:flutter/material.dart';

import '../prism/prism_header.dart';

/// Clean section header — title on left, optional trailing widget / "See All" on right.
///
/// prism/v2-reskin: hard-switched to the Prism skin.
/// Same props, zero call-site change.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onSeeAll,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return PrismSectionHeader(
      title: title,
      subtitle: subtitle,
      onSeeAll: onSeeAll,
      trailing: trailing,
    );
  }
}
