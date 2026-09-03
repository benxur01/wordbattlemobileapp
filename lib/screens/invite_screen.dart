import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

class InviteScreen extends StatelessWidget {
  const InviteScreen({
    super.key,
    required this.me,
    required this.invite,
    required this.clock,
    required this.onSkipToMatch,
    required this.onCancel,
  });

  final UserDto? me;

  /// The challenge we sent; null once it is answered or expires.
  final PendingInvite? invite;
  final String clock;
  final VoidCallback onSkipToMatch;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final invite = this.invite;
    if (invite == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -.32),
          radius: 1,
          colors: [Color.fromRGBO(247, 183, 51, .14), Colors.transparent],
          stops: [0, .7],
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          gradient: wbPurpleGradient,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          me?.initial ?? '?',
                          style: WBText.grotesk(
                            size: 28,
                            weight: FontWeight.w700,
                            color: WBColors.purpleText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'VS',
                        style: WBText.mono(size: 17, weight: FontWeight.w700, color: WBColors.textA(.4)),
                      ),
                      const SizedBox(width: 16),
                      _PulsingTarget(initial: invite.user.initial),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text('Chaqiruv yuborildi', style: WBText.grotesk(size: 22, weight: FontWeight.w600)),
                  const SizedBox(height: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 250),
                    child: Text(
                      '${invite.user.label} javobini kutmoqdamiz. Qabul qilishi bilan jang boshlanadi.',
                      textAlign: TextAlign.center,
                      style: WBText.grotesk(size: 14, height: 1.5, color: WBColors.textA(.5)),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    clock,
                    style: WBText.mono(size: 30, weight: FontWeight.w700, color: WBColors.accent),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Pressable(
                  onTap: onSkipToMatch,
                  hoverColor: WBColors.whiteA(.08),
                  borderRadius: BorderRadius.circular(19),
                  child: Container(
                    height: 58,
                    decoration: BoxDecoration(
                      color: WBColors.whiteA(.05),
                      border: Border.all(color: WBColors.whiteA(.12)),
                      borderRadius: BorderRadius.circular(19),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Kutmayman · tasodifiy raqib',
                      style: WBText.grotesk(size: 15.5, weight: FontWeight.w500, color: WBColors.textA(.75)),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                Pressable(
                  onTap: onCancel,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    child: Text(
                      'Bekor qilish',
                      style: WBText.grotesk(size: 15, weight: FontWeight.w500, color: WBColors.textA(.45)),
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

class _PulsingTarget extends StatefulWidget {
  const _PulsingTarget({required this.initial});
  final String initial;

  @override
  State<_PulsingTarget> createState() => _PulsingTargetState();
}

class _PulsingTargetState extends State<_PulsingTarget> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_c.value);
              return Transform.scale(
                scale: 1.0 + 0.08 * t,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: WBColors.accentA(.5), width: 2),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(gradient: wbTealGradient, borderRadius: BorderRadius.circular(24)),
            alignment: Alignment.center,
            child: Text(
              widget.initial,
              style: WBText.grotesk(size: 28, weight: FontWeight.w700, color: WBColors.tealText),
            ),
          ),
        ],
      ),
    );
  }
}
