import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

/// "Bot bilan jang": the player picks how strong the bot is before the duel
/// starts, instead of being handed the one matchmaking falls back to, and —
/// if they want one — a topic the whole duel is played inside.
///
/// The strength is shown as a rating and nothing else. On the server it decides
/// which pool the bot's words are drawn from — short everyday ones low down,
/// the long tail of the dictionary high up — which is an approximation of
/// difficulty by length and rarity rather than a real measure of one, so the
/// screen names the number and leaves it at that. A letter grade here would be
/// claiming something the word lists cannot back.
///
/// The two choices are independent: a themed duel is still played at whatever
/// rating the slider is on, out of that theme's own easy and rare words.
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
  /// `MAX_BOT_RATING`. Anything outside it is pulled back inside there rather
  /// than refused, so the two only have to agree for the slider to be honest
  /// about what it is asking for.
  static const minRating = 200.0;
  static const maxRating = 2000.0;
  static const step = 50.0;

  /// The bot's rating as it stands. Held by the caller, like every other bit of
  /// state in this app's screens.
  final int rating;

  /// This player's own rating, so the number above means something next to it.
  /// Null only in the moment between login and the first `hello` frame.
  final int? myRating;

  /// The topics on offer, from `GET /api/themes`. Empty until they arrive —
  /// and if they never do, the whole row goes and the screen is the strength
  /// picker it was before themes existed.
  final List<WordThemeDto> themes;

  /// The topic picked, by id, or null for the full dictionary — which is what
  /// the screen opens on, so a player who ignores this row plays exactly the
  /// duel they always did.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 26, 30),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(gradient: wbAccentGradient, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(
                    'W',
                    style: WBText.grotesk(size: 34, weight: FontWeight.w700, color: WBColors.accentInk),
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'BOT REYTINGI',
                  style: WBText.mono(
                    size: 11,
                    weight: FontWeight.w500,
                    color: WBColors.textA(.35),
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$rating',
                  style: WBText.mono(size: 44, weight: FontWeight.w700, color: WBColors.accent),
                ),
                const SizedBox(height: 4),
                Text(
                  myRating == null ? 'jang reytingsiz' : 'sizniki: $myRating · jang reytingsiz',
                  style: WBText.grotesk(size: 12.5, color: WBColors.textA(.45)),
                ),
                const SizedBox(height: 18),
                _slider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${minRating.round()}',
                        style: WBText.mono(size: 11, weight: FontWeight.w500, color: WBColors.textA(.3)),
                      ),
                      Text(
                        '${maxRating.round()}',
                        style: WBText.mono(size: 11, weight: FontWeight.w500, color: WBColors.textA(.3)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 270),
                  child: Text(
                    "Reyting qancha baland bo'lsa, bot shuncha uzun va kam "
                    "uchraydigan so'zlar o'ynaydi.",
                    textAlign: TextAlign.center,
                    style: WBText.grotesk(size: 13.5, height: 1.5, color: WBColors.textA(.5)),
                  ),
                ),
                if (themes.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _themes(),
                ],
              ],
            ),
          ),
          Pressable(
            onTap: onStart,
            pressScale: .97,
            borderRadius: BorderRadius.circular(19),
            child: Container(
              width: double.infinity,
              height: 58,
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

  /// The topic row. "Mavzusiz" is a chip like any other rather than an absent
  /// selection, so the full dictionary is something the player can see they
  /// are choosing — and can get back to after trying one.
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
        const SizedBox(height: 13),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: Text(
            "Mavzu tanlasangiz, siz ham, bot ham faqat o'sha mavzudagi "
            "so'zlarni o'ynaysiz.",
            textAlign: TextAlign.center,
            style: WBText.grotesk(size: 12.5, height: 1.5, color: WBColors.textA(.4)),
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

  Widget _slider() {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: WBColors.accent,
        inactiveTrackColor: WBColors.whiteA(.09),
        thumbColor: WBColors.accent,
        overlayColor: WBColors.accentA(.14),
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
