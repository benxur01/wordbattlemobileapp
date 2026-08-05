import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/progress_ring.dart';

class IncomingScreen extends StatefulWidget {
  const IncomingScreen({
    super.key,
    required this.invite,
    required this.secondsLeft,
    required this.progress,
    required this.onAccept,
    required this.onDismiss,
  });

  /// The challenge waiting for an answer; null once it is gone.
  final PendingInvite? invite;
  final int secondsLeft;
  final double progress;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  State<IncomingScreen> createState() => _IncomingScreenState();
}

class _IncomingScreenState extends State<IncomingScreen> with SingleTickerProviderStateMixin {
  // The design's sheet enters with `animation:wbRise .3s ease-out`.
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
      // rgba(5,5,8,.82) + backdrop-filter:blur(6px)
      filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        color: WBColors.bgDeep.withValues(alpha: .82),
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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.fromRGBO(30, 28, 44, .98), Color.fromRGBO(12, 12, 20, .98)],
                ),
                border: Border.all(color: WBColors.whiteA(.12)),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: WBColors.greenA(.14),
                      border: Border.all(color: WBColors.greenA(.36)),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      "DO'STLIK JANGI",
                      style: WBText.mono(
                        size: 11,
                        weight: FontWeight.w600,
                        color: WBColors.green,
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
                          color: WBColors.green,
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
                    '${invite.user.label} seni chaqirdi',
                    textAlign: TextAlign.center,
                    style: WBText.grotesk(size: 22, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${invite.user.rating} reyting',
                    style: WBText.mono(size: 13, weight: FontWeight.w500, color: WBColors.textA(.5)),
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
                            gradient: wbAmberGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: WBColors.amberA(.26),
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
                              color: WBColors.amberInk,
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
