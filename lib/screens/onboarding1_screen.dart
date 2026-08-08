import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/glow_orb.dart';
import '../widgets/primary_button.dart';
import '../widgets/spinner_ring.dart';

class Onboarding1Screen extends StatelessWidget {
  const Onboarding1Screen({super.key, required this.onGoogle, this.onDevLogin, this.busy = false});

  final VoidCallback onGoogle;

  /// Null in a properly configured build. Non-null only while the Google
  /// client ID is still a placeholder, so the app can still be opened.
  final VoidCallback? onDevLogin;

  /// True while the login request is in flight — the button must not fire twice.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.6),
          radius: 1.1,
          colors: [Color.fromRGBO(247, 183, 51, .16), Colors.transparent],
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
                  GlowOrb(
                    glowColor: WBColors.amber,
                    borderRadius: BorderRadius.circular(34),
                    child: Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(gradient: wbAmberGradient, borderRadius: BorderRadius.circular(34)),
                      alignment: Alignment.center,
                      child: Text('W', style: WBText.mono(size: 46, weight: FontWeight.w700, color: WBColors.amberInk2)),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text('WORD\nBATTLE',
                      textAlign: TextAlign.center,
                      style: WBText.grotesk(size: 36, weight: FontWeight.w700, height: 1.05, letterSpacing: -.02)),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 250),
                    child: Text(
                      "Ingliz so'zlari bilan jonli jang. Raqibingdan tez o'yla, zanjirni uzma.",
                      textAlign: TextAlign.center,
                      style: WBText.grotesk(size: 15, height: 1.5, color: WBColors.textA(.6)),
                    ),
                  ),
                  // 26px, the outer column's gap — not the 12px gap that sits
                  // between the title and its subtitle inside the text group.
                  const SizedBox(height: 26),
                  Wrap(
                    spacing: 8,
                    children: [
                      _Pill(text: '1v1 REAL-TIME'),
                      _Pill(text: 'GLICKO-2'),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Pressable(
                  onTap: busy ? null : onGoogle,
                  pressScale: .98,
                  child: Container(
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: wbAmberGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: WBColors.amberA(.28), blurRadius: 34, offset: const Offset(0, 14))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (busy)
                          const SpinnerRing(
                            size: 22,
                            trackColor: Color.fromRGBO(18, 11, 1, .25),
                            activeColor: WBColors.amberInk,
                            strokeWidth: 2.5,
                          )
                        else
                          // The design draws an abstract disc rather than a
                          // provider logo; the G keeps that shape language.
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: WBColors.amberInk.withValues(alpha: .85),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text('G',
                                style: WBText.mono(size: 13, weight: FontWeight.w700, color: WBColors.amber)),
                          ),
                        const SizedBox(width: 10),
                        Text(
                          busy ? 'Kirilmoqda…' : 'Google orqali kirish',
                          style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: WBColors.amberInk),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text("Parol yo'q. 30 soniyada birinchi jangingda.",
                    textAlign: TextAlign.center, style: WBText.grotesk(size: 12.5, color: WBColors.textA(.42))),
                if (onDevLogin != null) ...[
                  const SizedBox(height: 12),
                  Pressable(
                    onTap: busy ? null : onDevLogin,
                    pressScale: .96,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text('Dev login',
                          style: WBText.mono(
                            size: 11,
                            weight: FontWeight.w500,
                            color: WBColors.textA(.38),
                            letterSpacing: .12,
                          )),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.05),
        border: Border.all(color: WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: WBText.mono(size: 11, weight: FontWeight.w500, color: WBColors.textA(.65))),
    );
  }
}
