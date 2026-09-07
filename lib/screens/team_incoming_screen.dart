import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/progress_ring.dart';

/// The incoming team-duel invite's accept/decline sheet — mirrors
/// [IncomingScreen] exactly, badged and worded for a team rather than a duel.
class TeamIncomingScreen extends StatefulWidget {
  const TeamIncomingScreen({
    super.key,
    required this.invite,
    required this.secondsLeft,
    required this.progress,
    required this.onAccept,
    required this.onDismiss,
  });

  /// The invite waiting for an answer; null once it is gone.
  final PendingTeamInvite? invite;
  final int secondsLeft;
  final double progress;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  State<TeamIncomingScreen> createState() => _TeamIncomingScreenState();
}

class _TeamIncomingScreenState extends State<TeamIncomingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    if (invite == null) return const SizedBox.shrink();

    final progress = widget.progress;

    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        color: WBColors.scrim,
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: FadeTransition(
          opacity: _rise,
          child: AnimatedBuilder(
            animation: _rise,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 10 * (1 - Curves.easeOut.transform(_rise.value))),
              child: child,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
              decoration: BoxDecoration(
                gradient: wbSheetGradient,
                border: Border.all(color: WBColors.whiteA(.12)),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: WBColors.accentA(.14),
                      border: Border.all(color: WBColors.accentA(.36)),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'JAMOA TAKLIFI',
                      style: WBText.mono(
                        size: 11,
                        weight: FontWeight.w600,
                        color: WBColors.accent,
                        letterSpacing: .14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ProgressRing(
                          progress: progress,
                          color: WBColors.accent,
                          trackColor: WBColors.whiteA(.09),
                          strokeWidth: 7,
                        ),
                        Container(
                          width: 82,
                          height: 82,
                          decoration: BoxDecoration(
                            gradient: wbTealGradient,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            invite.user.initial,
                            style: WBText.grotesk(
                              size: 30,
                              weight: FontWeight.w700,
                              color: WBColors.tealText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${invite.user.label} sizni jamoaga taklif qilmoqda',
                    textAlign: TextAlign.center,
                    style: WBText.grotesk(size: 22, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "birga 2v2 raqib jamoa qidirasiz",
                    style: WBText.grotesk(size: 13, color: WBColors.textA(.5)),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    "${widget.secondsLeft} soniyadan keyin bekor bo'ladi",
                    style: WBText.grotesk(size: 12.5, color: WBColors.textA(.45)),
                  ),
                  const SizedBox(height: 18),
                  Column(
                    children: [
                      Pressable(
                        onTap: widget.onAccept,
                        pressScale: .98,
                        child: Container(
                          width: double.infinity,
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
                            'Qabul qilish',
                            style: WBText.grotesk(
                              size: 17,
                              weight: FontWeight.w600,
                              color: WBColors.accentInk,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Pressable(
                        onTap: widget.onDismiss,
                        hoverColor: WBColors.whiteA(.05),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            border: Border.all(color: WBColors.whiteA(.13)),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Hozir emas',
                            style: WBText.grotesk(
                              size: 15,
                              weight: FontWeight.w500,
                              color: WBColors.textA(.65),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
