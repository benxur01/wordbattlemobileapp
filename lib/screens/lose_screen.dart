import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../theme.dart';
import '../widgets/flame_badge.dart';
import '../widgets/primary_button.dart';

/// The defeat screen. Unlike the design — where every number was static — the
/// rating change, streak and the "stuck letter" hints all come from the
/// server's `duel.finished` payload.
class LoseScreen extends StatelessWidget {
  const LoseScreen({super.key, required this.result, required this.onRematch, required this.onPractice});

  final FinishedDuel? result;
  final VoidCallback onRematch;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    if (result == null) return const SizedBox.shrink();

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
                      Text(
                        result.rated ? '${result.delta}' : '—',
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
                ],
              ),
            ),
            Column(
              children: [
                Pressable(
                  onTap: onRematch,
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
                Pressable(
                  onTap: onPractice,
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
                      'Avval mashq qilaman',
                      style: WBText.grotesk(size: 15, weight: FontWeight.w500, color: WBColors.textA(.7)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
