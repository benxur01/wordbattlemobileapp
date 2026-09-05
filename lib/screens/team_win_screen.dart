import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/confetti_rain.dart';
import '../widgets/flame_badge.dart';
import '../widgets/primary_button.dart';

/// The team-duel victory screen — [WinScreen]'s sibling, crediting the result
/// to "biz" (this player and their partner) rather than to the player alone.
/// A rematch queues the same team again rather than calling the two opponents
/// back — there is no team-to-team challenge to send.
class TeamWinScreen extends StatelessWidget {
  const TeamWinScreen({
    super.key,
    required this.me,
    required this.result,
    required this.onRematch,
    required this.onHome,
  });

  final UserDto? me;

  /// The `team_duel.finished` payload. Null only if the screen is somehow
  /// reached without a finished duel.
  final TeamFinishedDuel? result;
  final VoidCallback onRematch;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    if (result == null) return const SizedBox.shrink();

    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.48),
                radius: 1,
                colors: [Color.fromRGBO(53, 208, 127, .18), Colors.transparent],
                stops: [0, .7],
              ),
            ),
          ),
        ),
        const Positioned.fill(child: ConfettiRain()),
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
                      'Jamoa\nzanjiri uzilmadi',
                      textAlign: TextAlign.center,
                      style: WBText.grotesk(
                        size: 40,
                        weight: FontWeight.w700,
                        height: 1,
                        letterSpacing: -.02,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _TeamsRow(me: me, result: result),
                    const SizedBox(height: 18),
                    Column(
                      children: [
                        Text(
                          '+${result.delta}',
                          style: WBText.mono(
                            size: 62,
                            weight: FontWeight.w700,
                            color: WBColors.green,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${result.ratingBefore} → ${result.ratingAfter}',
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
                          const FlameIcon(width: 15, height: 20),
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
                          Text(
                            '${result.streakDays}',
                            style: WBText.mono(size: 15, weight: FontWeight.w700, color: WBColors.flameText),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _MiniStat(value: '${result.yourWords}', label: "so'z"),
                        const SizedBox(width: 26),
                        _MiniStat(value: result.averageLabel, label: "o'rtacha"),
                        const SizedBox(width: 26),
                        _MiniStat(value: '${result.newWords}', label: "yangi so'z"),
                      ],
                    ),
                  ],
                ),
              ),
              // Side by side, as [WinScreen]'s own pair is: the footer keeps
              // the height it had when going home was the only way off.
              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: onRematch,
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
                    onTap: onHome,
                    hoverColor: WBColors.whiteA(.1),
                    borderRadius: BorderRadius.circular(20),
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

/// "Biz" (you + partner) against "ular" (the two opponents) — the one piece
/// of framing a 2v2 result needs that a 1v1 one never did.
class _TeamsRow extends StatelessWidget {
  const _TeamsRow({required this.me, required this.result});

  final UserDto? me;
  final TeamFinishedDuel result;

  @override
  Widget build(BuildContext context) {
    Widget avatar(String initial, Gradient gradient, Color textColor) => Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(gradient: gradient, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(initial, style: WBText.grotesk(size: 13, weight: FontWeight.w700, color: textColor)),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        avatar(me?.initial ?? '?', wbPurpleGradient, WBColors.purpleText),
        Transform.translate(
          offset: const Offset(-8, 0),
          child: avatar(result.partner.initial, wbTealGradient, WBColors.tealText),
        ),
        const SizedBox(width: 10),
        Text('BIZ', style: WBText.mono(size: 11, weight: FontWeight.w600, color: WBColors.textA(.45))),
        const SizedBox(width: 10),
        Text('vs', style: WBText.grotesk(size: 13, color: WBColors.textA(.35))),
        const SizedBox(width: 10),
        Text('ULAR', style: WBText.mono(size: 11, weight: FontWeight.w600, color: WBColors.textA(.45))),
        const SizedBox(width: 10),
        avatar(result.opponentOne.initial, wbRoseGradient, WBColors.roseText),
        Transform.translate(
          offset: const Offset(-8, 0),
          child: avatar(result.opponentTwo.initial, wbAmber8Gradient, WBColors.amber8Text),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: WBText.mono(size: 19, weight: FontWeight.w700)),
        Text(label, style: WBText.grotesk(size: 11, color: WBColors.textA(.45))),
      ],
    );
  }
}
