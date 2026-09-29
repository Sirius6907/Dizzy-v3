import 'package:flutter/material.dart';

import '../../../design/dizzy_tokens.dart';
import '../../../widgets/common/poster_skeleton.dart';

class HomeLoadingSkeleton extends StatelessWidget {
  final double topPadding;

  const HomeLoadingSkeleton({super.key, required this.topPadding});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final heroHeight =
        screenWidth < DizzyBreakpoints.mobile ? 420.0 : 520.0;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            DizzySpace.md,
            topPadding + 76,
            DizzySpace.md,
            0,
          ),
          child: ClipRRect(
            borderRadius: DizzyRadius.xlAll,
            child: SizedBox(height: heroHeight, child: const PosterSkeleton()),
          ),
        ),
        const SizedBox(height: DizzySpace.lg),
        _skeletonRow(screenWidth),
        _skeletonRow(screenWidth),
      ],
    );
  }

  Widget _skeletonRow(double screenWidth) {
    final cardWidth = (screenWidth - DizzySpace.md * 2 - DizzySpace.sm * 2) / 3;
    return Padding(
      padding: const EdgeInsets.only(
        left: DizzySpace.md,
        top: DizzySpace.lg,
        bottom: DizzySpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 140,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: DizzyRadius.smAll,
            ),
          ),
          const SizedBox(height: DizzySpace.sm),
          SizedBox(
            height: cardWidth * 1.5,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: DizzySpace.sm),
              itemBuilder: (context, _) => ClipRRect(
                borderRadius: DizzyRadius.mdAll,
                child: SizedBox(width: cardWidth, child: const PosterSkeleton()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
