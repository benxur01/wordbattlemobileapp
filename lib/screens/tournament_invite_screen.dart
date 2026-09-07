import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api/tournament_models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

/// A tournament invite waiting for Accept/Decline — the closest analogue is
/// `IncomingScreen`'s bottom-sheet, adapted for a challenge that comes from
/// the admin rather than a friend, and names a format instead of a rating.
///
/// A weekly Global bracket sends the same sheet with nobody behind it: the
/// player was picked off the top of the ladder, so it says that rather than
/// crediting an admin who did nothing. That one does expire, quietly and on
/// the server — see `TournamentService#expireStaleGlobalInvites` — where every
/// other invite here waits as long as it takes.
class TournamentInviteScreen extends StatefulWidget {
  const TournamentInviteScreen({
    super.key,
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  /// The invite waiting for an answer; null once it is gone.
  final TournamentInvite? invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  State<TournamentInviteScreen> createState() => _TournamentInviteScreenState();
}

class _TournamentInviteScreenState extends State<TournamentInviteScreen> with SingleTickerProviderStateMixin {
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
                      'TURNIR TAKLIFI',
                      style: WBText.mono(size: 11, weight: FontWeight.w600, color: WBColors.accent, letterSpacing: .14),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(gradient: wbAccentGradient, borderRadius: BorderRadius.circular(26)),
                    alignment: Alignment.center,
                    child: Icon(Icons.emoji_events_outlined, size: 36, color: WBColors.accentInk),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    invite.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WBText.grotesk(size: 22, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    invite.isTeam
                        ? "${invite.size} jamoa · 2v2 · yagona eliminatsiya"
                        : "${invite.size} o'yinchi · yagona eliminatsiya",
                    style: WBText.mono(size: 13, weight: FontWeight.w500, color: WBColors.textA(.5)),
                  ),
                  if (invite.teammate != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      "${invite.teammate!.label} bilan bir jamoada o'ynaysiz",
                      textAlign: TextAlign.center,
                      style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: WBColors.accent),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    invite.isGlobal
                        ? "Reytingingizga ko'ra ushbu haftalik global turnirga tanlandingiz. Qatnashish uchun quyidagi tugmani bosing."
                        : "${invite.organizer?.label ?? 'Admin'} sizni ushbu turnirga taklif qildi. Qatnashish uchun quyidagi tugmani bosing.",
                    textAlign: TextAlign.center,
                    style: WBText.grotesk(size: 12.5, height: 1.4, color: WBColors.textA(.55)),
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
                            'Qatnashaman',
                            style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: WBColors.accentInk),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Pressable(
                        onTap: widget.onDecline,
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
                            style: WBText.grotesk(size: 15, weight: FontWeight.w500, color: WBColors.textA(.65)),
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
