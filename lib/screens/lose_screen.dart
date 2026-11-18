import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../audio/sound_effects.dart';
import '../theme.dart';
import '../widgets/animated_counter.dart';
import '../widgets/flame_badge.dart';
import '../widgets/post_match_words_sheet.dart';
import '../widgets/primary_button.dart';

/// The defeat screen. Unlike the design — where every number was static — the
/// rating change, streak and the "stuck letter" hints all come from the
/// server's `duel.finished` payload.
class LoseScreen extends StatelessWidget {
  const LoseScreen({
    super.key,
    required this.result,
    this.words = const [],
    required this.onRematch,
    required this.onHome,
    required this.onPractice,
  });

  final FinishedDuel? result;

  /// Words played in the duel. Falls back to `result.words` if omitted.
  final List<ChainWord> words;
  final VoidCallback onRematch;

  /// Not in the design, which left Android's back gesture as the only way to
  /// the lobby from here — and iOS has no such gesture.
  final VoidCallback onHome;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    if (result == null) return const SizedBox.shrink();
    final effectiveWords = words.isNotEmpty ? words : result.words;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -.44),
          radius: 1,
          colors: [WBColors.indigoA(.14), Colors.transparent],
          stops: const [0, .7],
        ),
      ),
      child: Padding(
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
                      color: WBColors.indigoA(.13),
                      border: Border.all(color: WBColors.indigoA(.36)),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'JANG TUGADI',
                      style: WBText.mono(
                        size: 12,
                        weight: FontWeight.w600,
                        color: WBColors.indigoText,
                        letterSpacing: .16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Yaqin edi.\nYana bir bor?',
                    textAlign: TextAlign.center,
                    style: WBText.grotesk(
                      size: 38,
                      weight: FontWeight.w700,
                      height: 1.05,
                      letterSpacing: -.02,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Column(
                    children: [
                      result.rated
                          ? AnimatedCounter(
                              value: result.delta,
                              prefix: result.delta > 0 ? '+' : '',
                              style: WBText.mono(
                                size: 56,
                                weight: FontWeight.w700,
                                color: WBColors.textA(.75),
                                height: 1,
                              ),
                              duration: const Duration(milliseconds: 900),
                            )
                          : Text(
                              '—',
                              style: WBText.mono(
                                size: 56,
                                weight: FontWeight.w700,
                                color: WBColors.textA(.75),
                                height: 1,
                              ),
                            ),
                      const SizedBox(height: 3),
                      Text(
                        result.rated
                            ? '${result.ratingBefore} → ${result.ratingAfter}'
                            : 'Mashq jangi · reyting o\'zgarmadi',
                        style: WBText.mono(size: 14, weight: FontWeight.w500, color: WBColors.textA(.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: WBColors.whiteA(.045),
                      border: Border.all(color: WBColors.whiteA(.1)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            FlameIcon(width: 15, height: 20, animate: false),
                            const SizedBox(width: 11),
                            Text(
                              'Streak saqlandi · ${result.streakDays} kun',
                              style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Text(
                              'OK',
                              style: WBText.mono(size: 12, weight: FontWeight.w600, color: WBColors.green),
                            ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        Container(height: 1, color: WBColors.whiteA(.08)),
                        const SizedBox(height: 11),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'SEN QOTIB QOLGAN HARF',
                                style: WBText.mono(
                                  size: 11,
                                  weight: FontWeight.w500,
                                  color: WBColors.textA(.4),
                                  letterSpacing: .13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: WBColors.accentA(.15),
                                    border: Border.all(color: WBColors.accentA(.4)),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    result.stuckLetter ?? '?',
                                    style: WBText.mono(
                                      size: 15,
                                      weight: FontWeight.w700,
                                      color: WBColors.accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    result.hints.isEmpty
                                        ? "Keyingi safar tayyor bo'l"
                                        : "${result.hints.join(' · ')} — keyingi safar tayyor bo'l",
                                    style: WBText.grotesk(size: 13, height: 1.4, color: WBColors.textA(.62)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
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
            Column(
              children: [
                Pressable(
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
                        BoxShadow(color: WBColors.accentA(.24), blurRadius: 32, offset: const Offset(0, 14)),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Qasos olaman',
                      style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: WBColors.accentInk),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                // Side by side, as [TeamLoseScreen]'s pair is: the way home
                // costs the footer no extra height.
                Row(
                  children: [
                    Expanded(
                      child: Pressable(
                        onTap: () {
                          SoundEffects.instance.playTap();
                          onHome();
                        },
                        hoverColor: WBColors.whiteA(.05),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            border: Border.all(color: WBColors.whiteA(.13)),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Bosh sahifaga',
                            style: WBText.grotesk(size: 15, weight: FontWeight.w500, color: WBColors.textA(.7)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Pressable(
                        onTap: () {
                          SoundEffects.instance.playTap();
                          onPractice();
                        },
                        hoverColor: WBColors.whiteA(.05),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            border: Border.all(color: WBColors.whiteA(.13)),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Mashq qilaman',
                            style: WBText.grotesk(size: 15, weight: FontWeight.w500, color: WBColors.textA(.7)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
