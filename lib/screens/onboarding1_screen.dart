import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/glow_orb.dart';
import '../widgets/google_logo.dart';
import '../widgets/primary_button.dart';
import '../widgets/spinner_ring.dart';

/// The sign-in button's own colours, deliberately not in [WBColors]: that class
/// is the Word Battle design file ported 1:1, and none of these three came from
/// it. They are Google's published button values, and they are here because the
/// button is the one place in the app that answers to somebody else's spec.
const _googleSurface = Color(0xFFFFFFFF);
const _googleInk = Color(0xFF1F1F1F);
const _googleStroke = Color(0xFFDADCE0);

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
                // The design draws this as an amber plate with an abstract disc
                // where a provider logo would go, and it was built that way
                // first — the disc read as decoration rather than as the Google
                // button, which is the one thing it has to be, since it is the
                // only way into the app. So this button follows Google's spec
                // instead of the design file: their mark, on white, in their
                // ink. The amber went with it rather than being kept as a tint,
                // because their brand rules put the mark on a light surface —
                // recolouring the plate around it is not ours to do.
                Pressable(
                  onTap: busy ? null : onGoogle,
                  pressScale: .98,
                  child: Container(
                    height: 62,
                    decoration: BoxDecoration(
                      color: _googleSurface,
                      borderRadius: BorderRadius.circular(20),
                      // Google's own button stroke. On this near-black page it
                      // barely registers as a line — its job is to stop the
                      // white plate's corners fraying into the background.
                      border: Border.all(color: _googleStroke),
                      // The amber button glowed in its own colour to lift it off
                      // the page, and a white one still has to: with no shadow
                      // at all it reads as a hole cut in the background, and a
                      // dark shadow is invisible on #08080D. Same blur and drop
                      // as the amber had, in white and at half the alpha —
                      // white carries much further than amber does.
                      boxShadow: [BoxShadow(color: WBColors.whiteA(.13), blurRadius: 34, offset: const Offset(0, 14))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (busy)
                          // Dark on light now, the way the old spinner was dark
                          // on amber — the amber pair vanished on white.
                          SpinnerRing(
                            size: 22,
                            trackColor: _googleInk.withValues(alpha: .2),
                            activeColor: _googleInk,
                            strokeWidth: 2.5,
                          )
                        else
                          // 20dp against a 17px label: Google asks for a mark
                          // about the height of the text it sits beside.
                          const GoogleLogo(size: 20),
                        const SizedBox(width: 10),
                        Text(
                          busy ? 'Kirilmoqda…' : 'Google orqali kirish',
                          style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: _googleInk),
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
