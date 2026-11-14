import 'package:flutter/material.dart';
import '../theme.dart';
import 'shimmer.dart';

/// A shimmering skeleton placeholder list that matches the layout of
/// Leaderboard rows 1:1 while data is in flight from the server.
class LeaderboardSkeletonLoader extends StatelessWidget {
  const LeaderboardSkeletonLoader({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.fromLTRB(22, 14, 22, 85),
  });

  /// How many skeleton placeholder rows to render.
  final int itemCount;

  /// Insets matching the real leaderboard scroll view.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // Realistic variable widths so the skeleton looks like real user names
    const nameWidths = [120.0, 95.0, 135.0, 110.0, 85.0, 105.0];
    const cityWidths = [55.0, 70.0, 45.0, 60.0, 50.0, 65.0];

    return ShimmerScope(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final nameWidth = nameWidths[index % nameWidths.length];
          final cityWidth = cityWidths[index % cityWidths.length];
          final isTopPodium = index == 0;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: isTopPodium ? WBColors.amberA(.04) : WBColors.whiteA(.045),
              border: Border.all(
                color: isTopPodium ? WBColors.accentA(.25) : WBColors.whiteA(.09),
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                // Rank number skeleton
                const SizedBox(
                  width: 26,
                  child: ShimmerBox(
                    width: 16,
                    height: 16,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
                const SizedBox(width: 5),
                // Avatar skeleton (rounded squircle matching gradientFor)
                ShimmerBox(
                  width: 40,
                  height: 40,
                  borderRadius: BorderRadius.circular(13),
                ),
                const SizedBox(width: 13),
                // Player nickname & city skeleton
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShimmerBox(
                        width: nameWidth,
                        height: 15,
                        borderRadius: const BorderRadius.all(Radius.circular(4)),
                      ),
                      const SizedBox(height: 5),
                      ShimmerBox(
                        width: cityWidth,
                        height: 11,
                        borderRadius: const BorderRadius.all(Radius.circular(3)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Rating digits skeleton
                const ShimmerBox(
                  width: 38,
                  height: 16,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
