import 'package:flutter/material.dart';
import '../theme.dart';
import 'shimmer.dart';

/// Shimmering skeleton grid placeholder for the profile badges section.
class BadgesGridSkeleton extends StatelessWidget {
  const BadgesGridSkeleton({
    super.key,
    this.itemCount = 4,
    this.crossAxisCount = 4,
  });

  /// Total number of placeholder badge tiles to draw.
  final int itemCount;

  /// Number of columns in the grid (defaults to 4 matching profile layout).
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: WBColors.whiteA(.035),
            border: Border.all(color: WBColors.whiteA(.08)),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Badge mark shape
              ShimmerBox(
                width: 26,
                height: 26,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 8),
              // Badge label placeholder
              ShimmerBox(
                width: 38,
                height: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A full-page shimmering skeleton placeholder for ProfileScreen while
/// profile data is in flight from the server.
class ProfileSkeletonLoader extends StatelessWidget {
  const ProfileSkeletonLoader({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(22, 14, 22, 90),
  });

  /// Insets matching the real profile screen scroll view.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: ListView(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // 1. User Header (Avatar, name, meta, rating)
          Row(
            children: [
              // Avatar (matches 62x62 squircle)
              ShimmerBox(
                width: 62,
                height: 62,
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(width: 14),
              // User Label & Meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(
                      width: 130,
                      height: 20,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 7),
                    ShimmerBox(
                      width: 95,
                      height: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Rating column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ShimmerBox(
                    width: 58,
                    height: 22,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 6),
                  ShimmerBox(
                    width: 44,
                    height: 11,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Rating Chart Card
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: WBColors.whiteA(.045),
              border: Border.all(color: WBColors.whiteA(.09)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ShimmerBox(
                      width: 90,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    ShimmerBox(
                      width: 42,
                      height: 11,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Chart area waveform placeholder bars
                SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final h in [30.0, 45.0, 38.0, 56.0, 48.0, 68.0, 60.0, 75.0])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ShimmerBox(
                              height: h,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ShimmerBox(
                      width: 32,
                      height: 9,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    ShimmerBox(
                      width: 32,
                      height: 9,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. 2x2 Stat Cards
          Row(
            children: [
              Expanded(child: _buildStatCardSkeleton()),
              const SizedBox(width: 10),
              Expanded(child: _buildStatCardSkeleton()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildStatCardSkeleton()),
              const SizedBox(width: 10),
              Expanded(child: _buildStatCardSkeleton()),
            ],
          ),
          const SizedBox(height: 12),

          // 4. History Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: WBColors.whiteA(.045),
              border: Border.all(color: WBColors.whiteA(.09)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShimmerBox(
                  width: 110,
                  height: 13,
                  borderRadius: BorderRadius.circular(4),
                ),
                ShimmerBox(
                  width: 14,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Badges Section Header & Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerBox(
                width: 70,
                height: 14,
                borderRadius: BorderRadius.circular(4),
              ),
              ShimmerBox(
                width: 36,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const BadgesGridSkeleton(itemCount: 4),
        ],
      ),
    );
  }

  static Widget _buildStatCardSkeleton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.045),
        border: Border.all(color: WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(
            width: 48,
            height: 22,
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: 6),
          ShimmerBox(
            width: 72,
            height: 10,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}
