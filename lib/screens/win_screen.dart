import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../theme.dart';
import '../widgets/confetti_rain.dart';
import '../widgets/flame_badge.dart';
import '../widgets/primary_button.dart';

class WinScreen extends StatelessWidget {
  const WinScreen({super.key, required this.result, required this.onRematch, required this.onHome});

  /// The `duel.finished` payload. Null only if the screen is somehow reached
  /// without a finished duel.
  final FinishedDuel? result;
  final VoidCallback onRematch;

  /// The design leaves this square button unwired. On a phone that reads as a
  /// broken control, so it goes back to the lobby.
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    if (result == null) return const SizedBox.shrink();

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
                        Text(
                          result.rated ? '+${result.delta}' : '—',
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
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CustomPaint(painter: _OpenBoxGlyph(color: WBColors.textA(.75))),
                      ),
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

/// The design's second button glyph: a 16px rounded square whose top edge is
/// transparent. A non-uniform `Border` cannot be combined with a border radius
/// in a `BoxDecoration`, so it is stroked directly.
class _OpenBoxGlyph extends CustomPainter {
  _OpenBoxGlyph({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 4.0;
    final path = Path()
      ..moveTo(1, 0)
      ..lineTo(1, size.height - r - 1)
      ..arcToPoint(Offset(1 + r, size.height - 1), radius: const Radius.circular(r))
      ..lineTo(size.width - r - 1, size.height - 1)
      ..arcToPoint(Offset(size.width - 1, size.height - r - 1), radius: const Radius.circular(r))
      ..lineTo(size.width - 1, 0);

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _OpenBoxGlyph old) => old.color != color;
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
