import 'package:flutter/material.dart';
import '../theme.dart';
import 'shimmer.dart';

/// Shimmering skeleton loader matching the layout of friends list and search
/// result rows while data is in flight from the server.
class FriendsSkeletonLoader extends StatelessWidget {
  const FriendsSkeletonLoader({
    super.key,
    this.itemCount = 5,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
    this.physics = const NeverScrollableScrollPhysics(),
  });

  /// Factory tailored for search query in-flight results.
  const FriendsSkeletonLoader.search({
    super.key,
    this.itemCount = 2,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = true,
    this.physics = const NeverScrollableScrollPhysics(),
  });

  /// Number of placeholder rows to display.
  final int itemCount;

  /// Insets around the skeleton list.
  final EdgeInsetsGeometry padding;

  /// Whether the list should shrink-wrap its contents.
  final bool shrinkWrap;

  /// Scroll physics for the list.
  final ScrollPhysics physics;

  @override
  Widget build(BuildContext context) {
    // Variable widths give the skeleton a natural, organic look matching real names
    const nameWidths = [115.0, 95.0, 130.0, 100.0, 85.0];
    const statusWidths = [65.0, 48.0, 58.0, 72.0, 52.0];

    final list = ListView.separated(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        final nameWidth = nameWidths[index % nameWidths.length];
        final statusWidth = statusWidths[index % statusWidths.length];

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: WBColors.whiteA(.045),
            border: Border.all(color: WBColors.whiteA(.08)),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              // Avatar placeholder (matches 42x42 squircle)
              ShimmerBox(
                width: 42,
                height: 42,
                borderRadius: BorderRadius.circular(14),
              ),
              const SizedBox(width: 12),
              // Name and status subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(
                      width: nameWidth,
                      height: 15,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 6),
                    ShimmerBox(
                      width: statusWidth,
                      height: 11,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Trailing action button placeholder ("Jang" or "+ Taklif")
              ShimmerBox(
                width: 58,
                height: 36,
                borderRadius: BorderRadius.circular(14),
              ),
            ],
          ),
        );
      },
    );

    // If already inside a ShimmerScope, inherit it; otherwise provide one.
    if (ShimmerScope.of(context) != null) {
      return list;
    }
    return ShimmerScope(child: list);
  }
}
