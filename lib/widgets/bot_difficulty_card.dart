import 'package:flutter/material.dart';

import '../theme.dart';
import 'primary_button.dart';

/// Predefined bot difficulty tiers for quick selection in Word Battle.
enum BotDifficultyTier {
  novice,
  tactician,
  master;

  String get label => switch (this) {
        BotDifficultyTier.novice => 'Boshlovchi',
        BotDifficultyTier.tactician => 'Taktik',
        BotDifficultyTier.master => 'Usta',
      };

  String get englishLabel => switch (this) {
        BotDifficultyTier.novice => 'Novice',
        BotDifficultyTier.tactician => 'Tactician',
        BotDifficultyTier.master => 'Master',
      };

  String get subtitle => switch (this) {
        BotDifficultyTier.novice => 'Oddiy kundalik so\'zlar',
        BotDifficultyTier.tactician => 'O\'rtacha va chaqqon o\'yin',
        BotDifficultyTier.master => 'Keng va kamyob lug\'at',
      };

  int get defaultRating => switch (this) {
        BotDifficultyTier.novice => 600,
        BotDifficultyTier.tactician => 1200,
        BotDifficultyTier.master => 1800,
      };

  Color get color => switch (this) {
        BotDifficultyTier.novice => WBColors.green,
        BotDifficultyTier.tactician => WBColors.blue,
        BotDifficultyTier.master => WBColors.amber,
      };

  IconData get icon => switch (this) {
        BotDifficultyTier.novice => Icons.eco_rounded,
        BotDifficultyTier.tactician => Icons.bolt_rounded,
        BotDifficultyTier.master => Icons.workspace_premium_rounded,
      };

  LinearGradient get gradient => switch (this) {
        BotDifficultyTier.novice => wbTealGradient,
        BotDifficultyTier.tactician => wbBlueGradient,
        BotDifficultyTier.master => wbAmberGradient,
      };

  /// Determines the active tier based on the current bot rating.
  static BotDifficultyTier fromRating(int rating) {
    if (rating < 900) return BotDifficultyTier.novice;
    if (rating < 1500) return BotDifficultyTier.tactician;
    return BotDifficultyTier.master;
  }
}

/// A tactile, interactive card for selecting a bot difficulty tier.
class BotDifficultyCard extends StatelessWidget {
  const BotDifficultyCard({
    super.key,
    required this.tier,
    required this.isSelected,
    required this.onTap,
  });

  final BotDifficultyTier tier;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = tier.color;

    return Expanded(
      child: Pressable(
        onTap: onTap,
        pressScale: 0.95,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.12)
                : WBColors.whiteA(0.035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.7)
                  : WBColors.whiteA(0.08),
              width: isSelected ? 1.8 : 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Badge
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: isSelected ? tier.gradient : null,
                  color: isSelected ? null : WBColors.whiteA(0.06),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.35),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  tier.icon,
                  size: 20,
                  color: isSelected ? Colors.white : WBColors.textA(0.6),
                ),
              ),
              const SizedBox(height: 8),
              // Tier Title
              Text(
                tier.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: WBText.grotesk(
                  size: 13,
                  weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? activeColor : WBColors.textA(0.8),
                ),
              ),
              const SizedBox(height: 3),
              // Rating Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.16)
                      : WBColors.whiteA(0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${tier.defaultRating}',
                  style: WBText.mono(
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: isSelected ? activeColor : WBColors.textA(0.45),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
