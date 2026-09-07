import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/dashed_border.dart';
import '../widgets/primary_button.dart';
import '../widgets/radar_rings.dart';

/// The 2v2 queue's searching screen — [MatchmakingScreen]'s sibling: the same
/// radar, clock and cancel button, with both teammates shown searching
/// together rather than one player's avatar alone.
class TeamQueueScreen extends StatelessWidget {
  const TeamQueueScreen({
    super.key,
    required this.user,
    required this.partner,
    required this.matchClock,
    required this.onCancel,
  });

  final UserDto? user;

  /// The teammate queued alongside [user] — null only in the moment between
  /// `team.formed` and the fields being applied, which should never be long
  /// enough to see.
  final UserDto? partner;
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
                      RadarRings(size: 220, color: WBColors.accent),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(gradient: wbPurpleGradient, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text(
                              user?.initial ?? '?',
                              style: WBText.grotesk(size: 26, weight: FontWeight.w700, color: WBColors.purpleText),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(gradient: wbTealGradient, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text(
                              partner?.initial ?? '?',
                              style: WBText.grotesk(size: 26, weight: FontWeight.w700, color: WBColors.tealText),
                            ),
                          ),
                        ],
                      ),
                      _SpinningDashedRing(size: 200),
                    ],
                  ),
                ),
                const SizedBox(height: 72),
                Text('Raqib jamoa qidirilmoqda', style: WBText.grotesk(size: 22, weight: FontWeight.w600)),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    partner == null
                        ? "Sizga yaqin reytingdagi jamoalar orasidan"
                        : "${partner!.label} bilan birga — sizga yaqin reytingdagi jamoalar orasidan",
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
