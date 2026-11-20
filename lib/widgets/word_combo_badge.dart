import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sound_effects.dart';
import '../theme.dart';

/// Categories of combo achievements triggered on word submission.
enum WordComboType {
  longWord,
  rareLetter,
  speedDemon,
  megaCombo;

  String get defaultTitle {
    switch (this) {
      case WordComboType.longWord:
        return "UZUN SO'Z!";
      case WordComboType.rareLetter:
        return "NOYOB HARF!";
      case WordComboType.speedDemon:
        return "CHAQMOQ TEZKOR!";
      case WordComboType.megaCombo:
        return "AQLBOVAR QILMAS!";
    }
  }

  Color get accentColor {
    switch (this) {
      case WordComboType.longWord:
        return const Color(0xFF00E5FF); // Electric Cyan
      case WordComboType.rareLetter:
        return const Color(0xFFFFB300); // Golden Amber
      case WordComboType.speedDemon:
        return const Color(0xFF00E676); // Spring Emerald
      case WordComboType.megaCombo:
        return const Color(0xFFFF3366); // Neon Rose
    }
  }

  IconData get icon {
    switch (this) {
      case WordComboType.longWord:
        return Icons.auto_awesome_rounded;
      case WordComboType.rareLetter:
        return Icons.stars_rounded;
      case WordComboType.speedDemon:
        return Icons.bolt_rounded;
      case WordComboType.megaCombo:
        return Icons.local_fire_department_rounded;
    }
  }
}

/// An elastic, spring-popped neon badge with particle sparkles and radiant glow,
/// celebrating extraordinary words played in duel battles.
class WordComboBadge extends StatefulWidget {
  const WordComboBadge({
    super.key,
    required this.type,
    this.title,
    this.subtitle,
    this.bonusPoints,
    this.duration = const Duration(milliseconds: 2100),
    this.onComplete,
    this.enableSound = true,
  });

  /// Category of the combo.
  final WordComboType type;

  /// Custom badge header title (defaults to [WordComboType.defaultTitle]).
  final String? title;

  /// Supporting subtitle description (e.g. "8 ta harf", "Q, X harflari").
  final String? subtitle;

  /// Bonus points awarded (e.g. +12).
  final int? bonusPoints;

  /// Total lifespan of the badge overlay.
  final Duration duration;

  /// Callback when the badge completes its presentation.
  final VoidCallback? onComplete;

  /// Whether to play celebratory audio chime and haptics on entry.
  final bool enableSound;

  @override
  State<WordComboBadge> createState() => _WordComboBadgeState();
}

class _WordComboBadgeState extends State<WordComboBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _shimmerAnimation;
  late final Animation<double> _particleProgress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    // Elastic pop entry (0.0 to 0.3)
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.18, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.75)
            .chain(CurveTween(curve: Curves.easeInBack)),
        weight: 15,
      ),
    ]).animate(_controller);

    // Fade in and out
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 64,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 18,
      ),
    ]).animate(_controller);

    // Diagonal metallic sheen sweep
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.75, curve: Curves.easeInOut),
      ),
    );

    // Sparkle particle expansion
    _particleProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.08, 0.7, curve: Curves.easeOutQuart),
    );

    if (widget.enableSound) {
      SoundEffects.instance.playWordSuccess();
      HapticFeedback.mediumImpact();
    }

    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.type.accentColor;
    final titleText = widget.title ?? widget.type.defaultTitle;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = _scaleAnimation.value;
        final opacity = _opacityAnimation.value;
        if (opacity <= 0.0) return const SizedBox.shrink();

        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Radiating Particle Sparkles
                CustomPaint(
                  size: const Size(260, 100),
                  painter: _SparkleParticlesPainter(
                    progress: _particleProgress.value,
                    accentColor: themeColor,
                  ),
                ),

                // Radiant Aura Halo
                Container(
                  width: 240,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: themeColor.withValues(alpha: 0.38),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),

                // Glass Pill Badge Body
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161A26).withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: themeColor.withValues(alpha: 0.65),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          // Metallic Sheen Reflection
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(_shimmerAnimation.value * 200, 0),
                              child: Transform.rotate(
                                angle: 0.45,
                                child: Container(
                                  width: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Colors.white.withValues(alpha: 0.28),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Badge Content Row
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Icon Orb
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: themeColor.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: themeColor.withValues(alpha: 0.55),
                                    width: 1.2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  widget.type.icon,
                                  color: themeColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Title & Subtitle Stack
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        titleText,
                                        style: WBText.mono(
                                          size: 14,
                                          weight: FontWeight.w800,
                                          color: themeColor,
                                          letterSpacing: .12,
                                        ),
                                      ),
                                      if (widget.bonusPoints != null && widget.bonusPoints! > 0) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: WBColors.greenA(.2),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: WBColors.greenA(.4)),
                                          ),
                                          child: Text(
                                            '+${widget.bonusPoints}',
                                            style: WBText.mono(
                                              size: 10.5,
                                              weight: FontWeight.w700,
                                              color: WBColors.green,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.subtitle!,
                                      style: WBText.grotesk(
                                        size: 11.5,
                                        weight: FontWeight.w500,
                                        color: WBColors.textA(.75),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Custom painter rendering orbiting star sparkle particles around the combo badge.
class _SparkleParticlesPainter extends CustomPainter {
  _SparkleParticlesPainter({
    required this.progress,
    required this.accentColor,
  });

  final double progress;
  final Color accentColor;

  static final List<({double angle, double distance, double size, double phase})> _particles = [
    (angle: 0.25, distance: 110.0, size: 4.5, phase: 0.1),
    (angle: 0.85, distance: 95.0, size: 3.5, phase: 0.3),
    (angle: 1.55, distance: 80.0, size: 5.0, phase: 0.0),
    (angle: 2.20, distance: 105.0, size: 3.8, phase: 0.2),
    (angle: 3.45, distance: 115.0, size: 4.8, phase: 0.15),
    (angle: 4.10, distance: 90.0, size: 3.2, phase: 0.25),
    (angle: 4.95, distance: 85.0, size: 5.2, phase: 0.05),
    (angle: 5.80, distance: 100.0, size: 4.0, phase: 0.18),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in _particles) {
      final effectiveProgress = (progress + p.phase).clamp(0.0, 1.0);
      final currentDistance = p.distance * effectiveProgress;
      final x = center.dx + math.cos(p.angle) * currentDistance;
      final y = center.dy + math.sin(p.angle) * (currentDistance * 0.6); // slight ellipse

      final opacity = (1.0 - effectiveProgress).clamp(0.0, 1.0);
      final particleSize = p.size * (1.0 - effectiveProgress * 0.5);

      paint.color = accentColor.withValues(alpha: opacity * 0.85);

      // Draw diamond / 4-pointed star
      final path = Path()
        ..moveTo(x, y - particleSize)
        ..lineTo(x + particleSize * 0.5, y)
        ..lineTo(x, y + particleSize)
        ..lineTo(x - particleSize * 0.5, y)
        ..close();

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkleParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.accentColor != accentColor;
  }
}
