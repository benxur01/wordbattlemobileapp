import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../audio/sound_effects.dart';
import '../theme.dart';
import '../widgets/animated_counter.dart';
import '../widgets/confetti_rain.dart';
import '../widgets/flame_badge.dart';
import '../widgets/post_match_words_sheet.dart';
import '../widgets/primary_button.dart';

class WinScreen extends StatelessWidget {
  const WinScreen({
    super.key,
    required this.result,
    this.words = const [],
    required this.onRematch,
    required this.onHome,
  });

  /// The `duel.finished` payload. Null only if the screen is somehow reached
  /// without a finished duel.
  final FinishedDuel? result;

  /// Words played in the duel. Falls back to `result.words` if omitted.
  final List<ChainWord> words;
  final VoidCallback onRematch;

  /// The design leaves this square button unwired. On a phone that reads as a
  /// broken control, so it goes back to the lobby — under the home icon
  /// [TeamWinScreen]'s twin uses, not the design's abstract open-box glyph.
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    if (result == null) return const SizedBox.shrink();
    final effectiveWords = words.isNotEmpty ? words : result.words;

    return Stack(
      children: [
        // Positioned.fill: a childless DecoratedBox in a Stack takes the
        // smallest size the constraints allow — zero — so the win screen's
        // green glow was never painted.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -.48),
                radius: 1,
                colors: [WBColors.greenA(.18), Colors.transparent],
                stops: const [0, .7],
              ),
            ),
          ),
        ),
        Positioned.fill(child: ConfettiRain()),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 0, 26, 30),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: WBColors.greenA(.14),
                        border: Border.all(color: WBColors.greenA(.4)),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        "G'ALABA",
                        style: WBText.mono(
                          size: 12,
                          weight: FontWeight.w600,
                          color: WBColors.green,
                          letterSpacing: .16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Zanjir\nsendan uzilmadi',
                      textAlign: TextAlign.center,
                      style: WBText.grotesk(
                        size: 40,
                        weight: FontWeight.w700,
                        height: 1,
                        letterSpacing: -.02,
                      ),
                    ),
                    const SizedBox(height: 22),
                    // A duel against the bot is unrated: showing "+0" would look
                    // like a bug, so it says so instead.
                    Column(
                      children: [
                        result.rated
                            ? AnimatedCounter(
                                value: result.delta,
                                prefix: '+',
                                style: WBText.mono(
                                  size: 62,
                                  weight: FontWeight.w700,
                                  color: WBColors.green,
                                  height: 1,
                                ),
                                duration: const Duration(milliseconds: 900),
                              )
                            : Text(
                                '—',
                                style: WBText.mono(
                                  size: 62,
                                  weight: FontWeight.w700,
                                  color: WBColors.green,
                                  height: 1,
                                ),
                              ),
                        const SizedBox(height: 3),
                        Text(
                          result.rated
                              ? '${result.ratingBefore} → ${result.ratingAfter}'
                              : 'Mashq jangi · reyting o\'zgarmadi',
                          style: WBText.mono(size: 14, weight: FontWeight.w500, color: WBColors.textA(.55)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                      decoration: BoxDecoration(
                        color: WBColors.whiteA(.045),
                        border: Border.all(color: WBColors.whiteA(.1)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          FlameIcon(width: 15, height: 20),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${result.streakDays} kunlik streak',
                                  style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                                ),
                                Text(
                                  "Ertaga ham o'yna — saqlanib qoladi",
                                  style: WBText.grotesk(size: 12, color: WBColors.textA(.5)),
                                ),
                              ],
                            ),
                          ),
                          AnimatedCounter(
                            value: result.streakDays,
                            style: WBText.mono(size: 15, weight: FontWeight.w700, color: WBColors.flameText),
                            duration: const Duration(milliseconds: 700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _MiniStat(numericValue: result.yourWords, label: "so'z"),
                        const SizedBox(width: 26),
                        _MiniStat(value: result.averageLabel, label: "o'rtacha"),
                        const SizedBox(width: 26),
                        _MiniStat(numericValue: result.newWords, label: "yangi so'z"),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Pressable(
                      key: const ValueKey('post_match_words_button'),
                      onTap: () {
                        SoundEffects.instance.playTap();
                        PostMatchWordsSheet.show(
                          context,
                          words: effectiveWords,
                        );
                      },
                      hoverColor: WBColors.whiteA(.05),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: WBColors.whiteA(.05),
                          border: Border.all(color: WBColors.whiteA(.12)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.format_list_bulleted_rounded, size: 16, color: WBColors.accent),
                            const SizedBox(width: 8),
                            Text(
                              effectiveWords.isNotEmpty
                                  ? "So'zlar tahlili (${effectiveWords.length})"
                                  : "So'zlar tahlili",
                              style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: WBColors.text),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios_rounded, size: 11, color: WBColors.textA(.4)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: () {
                        SoundEffects.instance.playTap();
                        onRematch();
                      },
                      pressScale: .98,
                      child: Container(
                        height: 62,
                        decoration: BoxDecoration(
                          gradient: wbAccentGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: WBColors.accentA(.26),
                              blurRadius: 32,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Yana o'ynash",
                          style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: WBColors.accentInk),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Pressable(
                    onTap: () {
                      SoundEffects.instance.playTap();
                      onHome();
                    },
                    hoverColor: WBColors.whiteA(.1),
                    borderRadius: BorderRadius.circular(20),
                    semanticLabel: 'Bosh sahifa',
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: WBColors.whiteA(.06),
                        border: Border.all(color: WBColors.whiteA(.12)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.home_outlined, size: 20, color: WBColors.textA(.75)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({this.numericValue, this.value, required this.label});
  final int? numericValue;
  final String? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (numericValue != null)
          AnimatedCounter(
            value: numericValue!,
            style: WBText.mono(size: 19, weight: FontWeight.w700),
            duration: const Duration(milliseconds: 650),
          )
        else
          Text(value ?? '—', style: WBText.mono(size: 19, weight: FontWeight.w700)),
        Text(label, style: WBText.grotesk(size: 11, color: WBColors.textA(.45))),
      ],
    );
  }
}
