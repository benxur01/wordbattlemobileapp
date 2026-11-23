import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/bot_difficulty_card.dart';
import '../widgets/primary_button.dart';

export '../widgets/bot_difficulty_card.dart' show BotDifficultyTier;

/// "Bot bilan jang": the player picks how strong the bot is before the duel
/// starts, through tiered difficulty cards (Novice, Tactician, Master) or fine-tuning
/// via the rating slider, and optionally chooses a theme for the duel.
class BotBattleScreen extends StatelessWidget {
  const BotBattleScreen({
    super.key,
    required this.rating,
    required this.myRating,
    required this.themes,
    required this.theme,
    required this.onRatingChanged,
    required this.onThemeChanged,
    required this.onStart,
    required this.onBack,
  });

  /// The range the server clamps to — `DuelService.MIN_BOT_RATING` and
  /// `MAX_BOT_RATING`.
  static const minRating = 200.0;
  static const maxRating = 2000.0;
  static const step = 50.0;

  /// The bot's rating as it stands. Held by the caller.
  final int rating;

  /// This player's own rating.
  final int? myRating;

  /// The topics on offer, from `GET /api/themes`.
  final List<WordThemeDto> themes;

  /// The topic picked, by id, or null for the full dictionary.
  final String? theme;

  final ValueChanged<int> onRatingChanged;
  final ValueChanged<String?> onThemeChanged;
  final VoidCallback onStart;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: WBColors.whiteA(.07))),
      ),
      child: Row(
        children: [
          Pressable(
            onTap: onBack,
            borderRadius: BorderRadius.circular(12),
            semanticLabel: 'Orqaga',
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.1)),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.arrow_back_ios_new, size: 14, color: WBColors.textA(.7)),
            ),
          ),
          Expanded(
            child: Text(
              'Bot bilan jang',
              textAlign: TextAlign.center,
              style: WBText.grotesk(size: 15, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 38),
        ],
      ),
    );
  }

  Widget _body() {
    final activeTier = BotDifficultyTier.fromRating(rating);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Bot Avatar with Tier aura and icon
                  _botAvatar(activeTier),
                  const SizedBox(height: 18),
                  // Difficulty Level Tier Cards (Novice, Tactician, Master)
                  _difficultyTiers(activeTier),
                  const SizedBox(height: 16),
                  // Bot Rating Display
                  Text(
                    'BOT REYTINGI',
                    style: WBText.mono(
                      size: 11,
                      weight: FontWeight.w500,
                      color: WBColors.textA(.35),
                      letterSpacing: .2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$rating',
                    style: WBText.mono(size: 38, weight: FontWeight.w700, color: activeTier.color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    myRating == null ? 'jang reytingsiz' : 'sizniki: $myRating · jang reytingsiz',
                    style: WBText.grotesk(size: 12, color: WBColors.textA(.45)),
                  ),
                  const SizedBox(height: 12),
                  _slider(activeTier),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${minRating.round()}',
                          style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(.3)),
                        ),
                        Text(
                          '${maxRating.round()}',
                          style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(.3)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Tier Description Hint Box
                  _tierDescription(activeTier),
                  if (themes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _themes(),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Pressable(
            onTap: onStart,
            pressScale: .97,
            borderRadius: BorderRadius.circular(19),
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: wbAccentGradient,
                borderRadius: BorderRadius.circular(19),
              ),
              alignment: Alignment.center,
              child: Text(
                'Jangni boshlash',
                style: WBText.grotesk(size: 16, weight: FontWeight.w600, color: WBColors.accentInk),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botAvatar(BotDifficultyTier tier) {
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        gradient: tier.gradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: tier.color.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 2.5,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        tier.icon,
        size: 38,
        color: Colors.white,
      ),
    );
  }

  Widget _difficultyTiers(BotDifficultyTier activeTier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'QAYSI DARAJADA O\'YNAYSIZ?',
            style: WBText.mono(
              size: 10.5,
              weight: FontWeight.w600,
              color: WBColors.textA(.4),
              letterSpacing: .15,
            ),
          ),
        ),
        Row(
          children: [
            BotDifficultyCard(
              tier: BotDifficultyTier.novice,
              isSelected: activeTier == BotDifficultyTier.novice,
              onTap: () => onRatingChanged(BotDifficultyTier.novice.defaultRating),
            ),
            const SizedBox(width: 8),
            BotDifficultyCard(
              tier: BotDifficultyTier.tactician,
              isSelected: activeTier == BotDifficultyTier.tactician,
              onTap: () => onRatingChanged(BotDifficultyTier.tactician.defaultRating),
            ),
            const SizedBox(width: 8),
            BotDifficultyCard(
              tier: BotDifficultyTier.master,
              isSelected: activeTier == BotDifficultyTier.master,
              onTap: () => onRatingChanged(BotDifficultyTier.master.defaultRating),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tierDescription(BotDifficultyTier tier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tier.color.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Icon(tier.icon, size: 16, color: tier.color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${tier.label}: ${tier.subtitle}',
              style: WBText.grotesk(
                size: 12.5,
                weight: FontWeight.w500,
                color: WBColors.textA(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The topic row.
  Widget _themes() {
    return Column(
      children: [
        Text(
          'MAVZU',
          style: WBText.mono(
            size: 11,
            weight: FontWeight.w500,
            color: WBColors.textA(.35),
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 11),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _themeChip('Mavzusiz', theme == null, () => onThemeChanged(null)),
            for (final option in themes)
              _themeChip(option.name, theme == option.id, () => onThemeChanged(option.id)),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: Text(
            "Mavzu tanlasangiz, siz ham, bot ham faqat o'sha mavzudagi "
            "so'zlarni o'ynaysiz.",
            textAlign: TextAlign.center,
            style: WBText.grotesk(size: 12, height: 1.45, color: WBColors.textA(.4)),
          ),
        ),
      ],
    );
  }

  Widget _themeChip(String label, bool selected, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      pressScale: .96,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? WBColors.accentA(.16) : WBColors.whiteA(.05),
          border: Border.all(color: selected ? WBColors.accentA(.45) : WBColors.whiteA(.1)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: WBText.grotesk(
            size: 13,
            weight: FontWeight.w600,
            color: selected ? WBColors.accent : WBColors.textA(.6),
          ),
        ),
      ),
    );
  }

  Widget _slider(BotDifficultyTier tier) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: tier.color,
        inactiveTrackColor: WBColors.whiteA(.09),
        thumbColor: tier.color,
        overlayColor: tier.color.withValues(alpha: .14),
      ),
      child: Slider(
        value: rating.toDouble().clamp(minRating, maxRating),
        min: minRating,
        max: maxRating,
        divisions: ((maxRating - minRating) / step).round(),
        onChanged: (value) => onRatingChanged(value.round()),
      ),
    );
  }
}
