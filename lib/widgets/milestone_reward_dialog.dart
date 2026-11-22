import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sound_effects.dart';
import '../theme.dart';
import 'animated_flame.dart';
import 'confetti_cannon.dart';
import 'primary_button.dart';

/// Rotating volumetric sunburst light rays painted behind the milestone reward chest.
class SunburstGlow extends StatefulWidget {
  const SunburstGlow({
    super.key,
    this.size = 280,
    this.rayCount = 14,
    this.color,
    this.animate = true,
  });

  final double size;
  final int rayCount;
  final Color? color;
  final bool animate;

  @override
  State<SunburstGlow> createState() => _SunburstGlowState();
}

class _SunburstGlowState extends State<SunburstGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rayColor = widget.color ?? WBColors.amber;

    if (!widget.animate) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _SunburstPainter(
            rotation: 0.0,
            rayCount: widget.rayCount,
            color: rayColor,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _SunburstPainter(
              rotation: _controller.value * 2 * math.pi,
              rayCount: widget.rayCount,
              color: rayColor,
            ),
          ),
        );
      },
    );
  }
}

class _SunburstPainter extends CustomPainter {
  const _SunburstPainter({
    required this.rotation,
    required this.rayCount,
    required this.color,
  });

  final double rotation;
  final int rayCount;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final angleStep = (2 * math.pi) / rayCount;
    final halfRay = angleStep * 0.45;

    final rayPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.38),
          color.withValues(alpha: 0.18),
          Colors.transparent,
        ],
        stops: const [0.15, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    for (var i = 0; i < rayCount; i++) {
      final baseAngle = rotation + (i * angleStep);
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + radius * math.cos(baseAngle - halfRay),
          center.dy + radius * math.sin(baseAngle - halfRay),
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          baseAngle - halfRay,
          halfRay * 2,
          false,
        )
        ..close();

      canvas.drawPath(path, rayPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.rayCount != rayCount ||
        oldDelegate.color != color;
  }
}

/// A festive celebration modal dialog presented when the player reaches
/// or claims a milestone (such as a 7-day streak or weekly achievement).
class MilestoneRewardDialog extends StatefulWidget {
  const MilestoneRewardDialog({
    super.key,
    this.milestoneDays = 7,
    this.title,
    this.subtitle,
    this.onClaim,
    this.onClose,
    this.animate = true,
  });

  /// The milestone tier achieved in days (defaults to 7).
  final int milestoneDays;

  /// Custom celebration header title.
  final String? title;

  /// Custom motivational subtitle.
  final String? subtitle;

  /// Callback fired when reward is claimed.
  final VoidCallback? onClaim;

  /// Callback fired when dialog is closed.
  final VoidCallback? onClose;

  /// Whether to run continuous entrance and sunburst animations.
  final bool animate;

  /// Launches the [MilestoneRewardDialog] as a modal with blur backdrop.
  static Future<void> show(
    BuildContext context, {
    int milestoneDays = 7,
    String? title,
    String? subtitle,
    VoidCallback? onClaim,
    bool animate = true,
  }) {
    HapticFeedback.heavyImpact();
    SoundEffects.instance.playVictory();

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Yopish',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, anim1, anim2) {
        return MilestoneRewardDialog(
          milestoneDays: milestoneDays,
          title: title,
          subtitle: subtitle,
          onClaim: onClaim,
          onClose: () => Navigator.of(ctx).pop(),
          animate: animate,
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curve,
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );
  }

  @override
  State<MilestoneRewardDialog> createState() => _MilestoneRewardDialogState();
}

class _MilestoneRewardDialogState extends State<MilestoneRewardDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;
  final GlobalKey<ConfettiCannonState> _confettiKey = GlobalKey<ConfettiCannonState>();
  Timer? _closeTimer;
  bool _claimed = false;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _bounceAnimation = Tween<double>(begin: 0.0, end: -8.0).animate(
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.easeInOutSine,
      ),
    );

    if (widget.animate) {
      _bounceController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _bounceController.dispose();
    super.dispose();
  }

  void _handleClaim() {
    if (_claimed) return;
    HapticFeedback.heavyImpact();
    SoundEffects.instance.playWordSuccess();
    _confettiKey.currentState?.blast();
    setState(() => _claimed = true);
    widget.onClaim?.call();

    // Auto close after brief acknowledgment delay
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        if (widget.onClose != null) {
          widget.onClose!();
        } else {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleText = widget.title ?? '${widget.milestoneDays} KUNLIK CHEMPION!';
    final subtitleText = widget.subtitle ??
        'Ajoyib mahorat! ${widget.milestoneDays} kun ketma-ket g‘alaba qozonib, haftalik marrani zabt etdingiz!';

    return Stack(
      children: [
        // Full screen 60 FPS Confetti Cannon Particle Emitter
        Positioned.fill(
          child: ConfettiCannon(
            key: _confettiKey,
            blastOnStart: true,
            animate: widget.animate,
            particleCount: 60,
          ),
        ),

        // Centered Celebration Card
        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: WBColors.bgPanel.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: WBColors.amber.withValues(alpha: 0.45),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: WBColors.amber.withValues(alpha: 0.25),
                    blurRadius: 36,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 1. Rotating Sunburst Rays
                    Positioned(
                      top: -40,
                      child: SunburstGlow(
                        size: 280,
                        animate: widget.animate,
                        color: WBColors.amber,
                      ),
                    ),

                // 2. Foreground Card Content
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Floating Reward Trophy/Chest
                      AnimatedBuilder(
                        animation: _bounceAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, widget.animate ? _bounceAnimation.value : 0.0),
                            child: child,
                          );
                        },
                        child: _buildTrophyBadge(),
                      ),

                      const SizedBox(height: 16),

                      // Title
                      Text(
                        titleText,
                        textAlign: TextAlign.center,
                        style: WBText.grotesk(
                          size: 20,
                          weight: FontWeight.w800,
                          color: WBColors.text,
                          letterSpacing: -0.01,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Subtitle
                      Text(
                        subtitleText,
                        textAlign: TextAlign.center,
                        style: WBText.grotesk(
                          size: 12.5,
                          weight: FontWeight.w400,
                          color: WBColors.textA(0.8),
                          height: 1.38,
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Rewards Breakdown List
                      _buildRewardsList(),

                      const SizedBox(height: 22),

                      // Claim CTA Button
                      _buildClaimButton(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ],
);
  }

  Widget _buildTrophyBadge() {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            WBColors.amber,
            WBColors.flameTop,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: WBColors.amber.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            size: 44,
            color: Colors.white,
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: LiveStreakFlame(
              size: 22,
              tier: StreakFlameTier.blazing,
              animate: widget.animate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardsList() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WBColors.whiteA(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WBColors.whiteA(0.09)),
      ),
      child: Column(
        children: [
          _buildRewardRow(
            icon: Icons.star_rounded,
            iconColor: WBColors.amber,
            label: '+50 Reyting Balli',
            subtitle: 'Umumiy reytingingizga qo‘shiladi',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Colors.white12),
          ),
          _buildRewardRow(
            icon: Icons.local_fire_department_rounded,
            iconColor: WBColors.flameTop,
            label: 'Olovli Profil Ramkasi',
            subtitle: '7 kun davomida faol unvon',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Colors.white12),
          ),
          _buildRewardRow(
            icon: Icons.ac_unit_rounded,
            iconColor: WBColors.tealText,
            label: '1x Streak Himoyasi',
            subtitle: 'Kutilmagan o‘tkazib yuborishdan himoya',
          ),
        ],
      ),
    );
  }

  Widget _buildRewardRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: WBText.grotesk(
                  size: 13,
                  weight: FontWeight.w700,
                  color: WBColors.text,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: WBText.grotesk(
                  size: 10.5,
                  weight: FontWeight.w400,
                  color: WBColors.textA(0.65),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClaimButton(BuildContext context) {
    return Pressable(
      onTap: _claimed ? null : _handleClaim,
      pressScale: 0.96,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _claimed
                ? [WBColors.green, const Color(0xFF0B7A42)]
                : [WBColors.amber, WBColors.flameTop],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (_claimed ? WBColors.green : WBColors.amber).withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          _claimed ? 'MUKOFOT QABUL QILINDI!' : 'QABUL QILISH',
          style: WBText.grotesk(
            size: 14,
            weight: FontWeight.w800,
            color: _claimed ? Colors.white : Colors.black87,
            letterSpacing: 0.04,
          ),
        ),
      ),
    );
  }
}
