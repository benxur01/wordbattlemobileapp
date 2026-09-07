import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

/// The outgoing team-duel invite's "waiting for them to answer" screen —
/// mirrors [InviteScreen], with no "skip to a random opponent" escape hatch:
/// a team is always formed with a specific friend, so there is no matchmaking
/// equivalent to fall back to while this wait is on.
class TeamInviteScreen extends StatelessWidget {
  const TeamInviteScreen({
    super.key,
    required this.me,
    required this.invite,
    required this.clock,
    required this.onCancel,
  });

  final UserDto? me;

  /// The team invite we sent; null once it is answered or expires.
  final PendingTeamInvite? invite;
  final String clock;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final invite = this.invite;
    if (invite == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -.32),
          radius: 1,
          colors: [WBColors.accentA(.14), Colors.transparent],
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
                      Icon(Icons.group_outlined, size: 22, color: WBColors.textA(.4)),
                      const SizedBox(width: 16),
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          gradient: wbTealGradient,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          invite.user.initial,
                          style: WBText.grotesk(size: 28, weight: FontWeight.w700, color: WBColors.tealText),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text('Jamoa taklifi yuborildi', style: WBText.grotesk(size: 22, weight: FontWeight.w600)),
                  const SizedBox(height: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      '${invite.user.label} javobini kutmoqdamiz. Qabul qilsa, ikkovlaringiz birga raqib jamoa qidirasiz.',
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
      ),
    );
  }
}
