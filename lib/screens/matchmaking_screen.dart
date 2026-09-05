import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/dashed_border.dart';
import '../widgets/primary_button.dart';
import '../widgets/radar_rings.dart';

class MatchmakingScreen extends StatelessWidget {
  const MatchmakingScreen({super.key, required this.user, required this.matchClock, required this.onCancel});

  final UserDto? user;
  final String matchClock;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 26, 30),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const RadarRings(size: 220, color: WBColors.accent),
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          gradient: wbPurpleGradient,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          user?.initial ?? '?',
                          style: WBText.grotesk(
                            size: 34,
                            weight: FontWeight.w700,
                            color: WBColors.purpleText,
                          ),
                        ),
                      ),
                      _SpinningDashedRing(size: 180),
                    ],
                  ),
                ),
                const SizedBox(height: 72),
                Text('Raqib qidirilmoqda', style: WBText.grotesk(size: 22, weight: FontWeight.w600)),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    "Sizga yaqin reytingdagi o'yinchilar orasidan",
                    textAlign: TextAlign.center,
                    style: WBText.grotesk(size: 14, height: 1.5, color: WBColors.textA(.5)),
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        Text(
                          matchClock,
                          style: WBText.mono(size: 26, weight: FontWeight.w700, color: WBColors.accent),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "O'TDI",
                          style: WBText.mono(
                            size: 10,
                            weight: FontWeight.w500,
                            color: WBColors.textA(.35),
                            letterSpacing: .14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Pressable(
            onTap: onCancel,
            hoverColor: WBColors.whiteA(.08),
            borderRadius: BorderRadius.circular(19),
            child: Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.12)),
                borderRadius: BorderRadius.circular(19),
              ),
              alignment: Alignment.center,
              child: Text(
                'Bekor qilish',
                style: WBText.grotesk(size: 16, weight: FontWeight.w500, color: WBColors.textA(.75)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpinningDashedRing extends StatefulWidget {
  const _SpinningDashedRing({required this.size});
  final double size;

  @override
  State<_SpinningDashedRing> createState() => _SpinningDashedRingState();
}

class _SpinningDashedRingState extends State<_SpinningDashedRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 9))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        // `border:2px dashed rgba(255,255,255,.14)` — a solid ring read as a
        // plain grey circle instead of an orbit.
        child: CustomPaint(
          painter: DashedBorderPainter(
            color: WBColors.whiteA(.14),
            strokeWidth: 2,
            circle: true,
            dash: 6,
            gap: 6,
          ),
        ),
      ),
    );
  }
}
