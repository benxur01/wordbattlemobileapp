import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Tier of fire intensity based on current streak count.
enum StreakFlameTier {
  gentle,
  vibrant,
  blazing;

  static StreakFlameTier fromDays(int days) {
    if (days >= 7) return StreakFlameTier.blazing;
    if (days >= 3) return StreakFlameTier.vibrant;
    return StreakFlameTier.gentle;
  }

  Color get primaryColor {
    switch (this) {
      case StreakFlameTier.gentle:
        return const Color(0xFFFF9100); // Warm amber
      case StreakFlameTier.vibrant:
        return const Color(0xFFFF3D00); // Blazing orange-red
      case StreakFlameTier.blazing:
        return const Color(0xFFFF1744); // Electric crimson-fire
    }
  }

  Color get innerColor {
    switch (this) {
      case StreakFlameTier.gentle:
        return const Color(0xFFFFD54F);
      case StreakFlameTier.vibrant:
        return const Color(0xFFFFF176);
      case StreakFlameTier.blazing:
        return const Color(0xFF80D8FF); // Hot blue base core
    }
  }

  Color get haloColor {
    switch (this) {
      case StreakFlameTier.gentle:
        return const Color(0xFFFFAB00);
      case StreakFlameTier.vibrant:
        return const Color(0xFFFF6D00);
      case StreakFlameTier.blazing:
        return const Color(0xFFFF5252);
    }
  }
}

/// An organic, living flame widget with realistic sinusoidal bezier tongue
/// oscillation, heat aura pulse, and rising floating ember particles.
class LiveStreakFlame extends StatefulWidget {
  const LiveStreakFlame({
    super.key,
    this.size = 24.0,
    this.tier = StreakFlameTier.vibrant,
    this.animate = true,
    this.showEmbers = true,
  });

  /// Size (width and height bounding box) of the flame.
  final double size;

  /// Fire tier reflecting streak progression.
  final StreakFlameTier tier;

  /// Whether the flame and embers should animate.
  final bool animate;

  /// Whether to emit floating heat ember sparks.
  final bool showEmbers;

  @override
  State<LiveStreakFlame> createState() => _LiveStreakFlameState();
}

class _LiveStreakFlameState extends State<LiveStreakFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(LiveStreakFlame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(s, s * 1.3),
          painter: _FlamePainter(
            progress: widget.animate ? _controller.value : 0.5,
            tier: widget.tier,
            showEmbers: widget.showEmbers,
          ),
        );
      },
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({
    required this.progress,
    required this.tier,
    required this.showEmbers,
  });

  final double progress;
  final StreakFlameTier tier;
  final bool showEmbers;

  static final List<({double xSeed, double ySeed, double size, double speed})> _embers = [
    (xSeed: -0.22, ySeed: 0.1, size: 1.8, speed: 1.0),
    (xSeed: 0.18, ySeed: 0.35, size: 1.5, speed: 1.2),
    (xSeed: -0.08, ySeed: 0.6, size: 2.2, speed: 0.85),
    (xSeed: 0.28, ySeed: 0.8, size: 1.4, speed: 1.1),
    (xSeed: -0.15, ySeed: 0.95, size: 1.9, speed: 0.95),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h * 0.72;

    final primary = tier.primaryColor;
    final inner = tier.innerColor;
    final halo = tier.haloColor;

    // 1. Soft Warmth Aura Halo
    final auraPulse = 0.85 + 0.15 * math.sin(progress * 2 * math.pi);
    final auraRadius = (w * 0.7) * auraPulse;
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          halo.withValues(alpha: 0.32),
          halo.withValues(alpha: 0.12),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: auraRadius));

    canvas.drawCircle(Offset(cx, cy), auraRadius, auraPaint);

    // 2. Outer Licking Flame Tongue
    final wave1 = math.sin(progress * 2 * math.pi) * (w * 0.08);
    final wave2 = math.cos(progress * 2 * math.pi) * (h * 0.04);
    final tipY = (h * 0.08) + wave2;

    final outerPath = Path();
    outerPath.moveTo(cx, tipY);
    // Right side curve
    outerPath.cubicTo(
      cx + (w * 0.5) + wave1,
      h * 0.35,
      cx + (w * 0.52),
      h * 0.8,
      cx + (w * 0.2),
      h * 0.95,
    );
    // Base bottom curve
    outerPath.quadraticBezierTo(cx, h * 0.98, cx - (w * 0.2), h * 0.95);
    // Left side curve
    outerPath.cubicTo(
      cx - (w * 0.52),
      h * 0.8,
      cx - (w * 0.5) - wave1,
      h * 0.35,
      cx,
      tipY,
    );
    outerPath.close();

    final outerGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        primary,
        const Color(0xFFFF6D00),
        const Color(0xFFFFAB00),
      ],
      stops: const [0.0, 0.6, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, w, h));

    final outerPaint = Paint()
      ..shader = outerGradient
      ..style = PaintingStyle.fill;

    canvas.drawPath(outerPath, outerPaint);

    // 3. Inner White/Yellow Hot Core
    final coreW = w * 0.55;
    final coreTipY = (h * 0.38) + wave2 * 0.5;

    final innerPath = Path();
    innerPath.moveTo(cx, coreTipY);
    innerPath.cubicTo(
      cx + (coreW * 0.5) + wave1 * 0.5,
      h * 0.55,
      cx + (coreW * 0.45),
      h * 0.82,
      cx + (coreW * 0.15),
      h * 0.92,
    );
    innerPath.quadraticBezierTo(cx, h * 0.94, cx - (coreW * 0.15), h * 0.92);
    innerPath.cubicTo(
      cx - (coreW * 0.45),
      h * 0.82,
      cx - (coreW * 0.5) - wave1 * 0.5,
      h * 0.55,
      cx,
      coreTipY,
    );
    innerPath.close();

    final innerGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        inner,
        const Color(0xFFFFFDE7),
      ],
    ).createShader(Rect.fromLTWH(0, 0, w, h));

    final innerPaint = Paint()
      ..shader = innerGradient
      ..style = PaintingStyle.fill;

    canvas.drawPath(innerPath, innerPaint);

    // 4. Rising Heat Embers
    if (showEmbers) {
      final emberPaint = Paint()..style = PaintingStyle.fill;

      for (final ember in _embers) {
        final cycle = (progress * ember.speed + ember.ySeed) % 1.0;
        final emberY = (h * 0.5) - (cycle * h * 0.6);
        final emberX = cx + (ember.xSeed * w) + math.sin(cycle * 3 * math.pi) * (w * 0.12);

        final opacity = (1.0 - cycle).clamp(0.0, 1.0);
        final currentSize = ember.size * (1.0 - cycle * 0.4);

        emberPaint.color = Color.lerp(inner, halo, cycle)!.withValues(alpha: opacity * 0.9);
        canvas.drawCircle(Offset(emberX, emberY), currentSize, emberPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FlamePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.tier != tier;
  }
}
