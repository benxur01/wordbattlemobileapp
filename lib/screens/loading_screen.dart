import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/glow_orb.dart';
import '../widgets/primary_button.dart';
import '../widgets/spinner_ring.dart';

/// Shown while the saved session is restored, and again — with a message and a
/// retry — when the server cannot be reached. The design has no such screen;
/// a real app needs one, so it reuses the onboarding logo and palette.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = onRetry != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.6),
          radius: 1.1,
          colors: [WBColors.accentA(.16), Colors.transparent],
          stops: const [0, .7],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlowOrb(
              glowColor: WBColors.accent,
              borderRadius: BorderRadius.circular(34),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(gradient: wbAccentGradient, borderRadius: BorderRadius.circular(28)),
                alignment: Alignment.center,
                child: Text('W', style: WBText.mono(size: 38, weight: FontWeight.w700, color: WBColors.accentInk)),
              ),
            ),
            const SizedBox(height: 30),
            if (!failed)
              SpinnerRing(
                size: 22,
                trackColor: WBColors.textA(.18),
                activeColor: WBColors.accent,
                strokeWidth: 2.5,
              )
            else ...[
              Text(
                message ?? "Serverga ulanib bo'lmadi",
                textAlign: TextAlign.center,
                style: WBText.grotesk(size: 15, height: 1.5, color: WBColors.textA(.7)),
              ),
              const SizedBox(height: 22),
              Pressable(
                onTap: onRetry,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  decoration: BoxDecoration(
                    gradient: wbAccentGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: WBColors.accentA(.24), blurRadius: 28, offset: const Offset(0, 12))],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Qayta urinish',
                    style: WBText.grotesk(size: 16, weight: FontWeight.w600, color: WBColors.accentInk),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
