import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme.dart';

/// Represents a single confetti particle with 3D tumble physics.
class _ConfettiParticle {
  _ConfettiParticle({
    required this.origin,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.angularVelocity,
    required this.flipAngle,
    required this.flipSpeed,
    required this.delayFraction,
  });

  final Offset origin;
  final double vx;
  final double vy;
  final Size size;
  final Color color;
  final double rotation;
  final double angularVelocity;
  final double flipAngle;
  final double flipSpeed;
  final double delayFraction;

  double x = 0;
  double y = 0;
  double opacity = 1.0;
  double currentRotation = 0;
  double currentFlip = 0;

  void update(double progress) {
    if (progress < delayFraction) {
      opacity = 0.0;
      return;
    }

    // Normalized progress after launch delay
    final t = ((progress - delayFraction) / (1.0 - delayFraction)).clamp(0.0, 1.0);
    final timeSeconds = t * 2.8;

    // Physics: ballistic trajectory with gravity and aerodynamic drag
    const gravity = 580.0;
    const drag = 0.94;
    final dragFactor = math.pow(drag, timeSeconds * 30).toDouble();

    x = origin.dx + (vx * timeSeconds * dragFactor);
    y = origin.dy + (vy * timeSeconds * dragFactor) + (0.5 * gravity * timeSeconds * timeSeconds);

    currentRotation = rotation + (angularVelocity * timeSeconds);
    currentFlip = flipAngle + (flipSpeed * timeSeconds);

    // Fade out smoothly during the final 20% of life
    if (t > 0.8) {
      opacity = ((1.0 - t) / 0.2).clamp(0.0, 1.0);
    } else {
      opacity = (t / 0.08).clamp(0.0, 1.0);
    }
  }
}

/// A 60 FPS GPU-accelerated confetti cannon particle emitter with 3D flutter.
class ConfettiCannon extends StatefulWidget {
  const ConfettiCannon({
    super.key,
    this.particleCount = 55,
    this.duration = const Duration(milliseconds: 3200),
    this.blastOnStart = true,
    this.loop = true,
    this.animate = true,
  });

  /// Total number of confetti particles emitted.
  final int particleCount;

  /// Duration of a single burst wave.
  final Duration duration;

  /// Whether to burst immediately when inserted into the widget tree.
  final bool blastOnStart;

  /// Whether to continuously repeat burst waves.
  final bool loop;

  /// Ticker enable switch for unit testing without infinite frame locks.
  final bool animate;

  @override
  State<ConfettiCannon> createState() => ConfettiCannonState();
}

class ConfettiCannonState extends State<ConfettiCannon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_ConfettiParticle> _particles = [];
  final math.Random _rng = math.Random();
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    if (widget.animate && widget.blastOnStart) {
      if (widget.loop) {
        _controller.repeat();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Triggers a fresh explosive celebration burst.
  void blast() {
    if (!mounted) return;
    _generateParticles(_lastSize);
    _controller.forward(from: 0.0);
  }

  void _generateParticles(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _particles.clear();

    final colors = [
      WBColors.amber,
      WBColors.flameTop,
      WBColors.flameBottom,
      WBColors.green,
      WBColors.indigo,
      WBColors.tealText,
      WBColors.rose,
      Colors.white,
      Colors.amberAccent,
    ];

    final leftOrigin = Offset(size.width * 0.1, size.height * 0.85);
    final rightOrigin = Offset(size.width * 0.9, size.height * 0.85);
    final centerOrigin = Offset(size.width * 0.5, size.height * 0.4);

    for (var i = 0; i < widget.particleCount; i++) {
      // 40% left cannon, 40% right cannon, 20% central fountain
      final originType = _rng.nextDouble();
      Offset origin;
      double vx;
      double vy;

      if (originType < 0.42) {
        // Left cannon shooting up-right
        origin = leftOrigin;
        vx = 120 + _rng.nextDouble() * 260;
        vy = -380 - _rng.nextDouble() * 320;
      } else if (originType < 0.84) {
        // Right cannon shooting up-left
        origin = rightOrigin;
        vx = -120 - _rng.nextDouble() * 260;
        vy = -380 - _rng.nextDouble() * 320;
      } else {
        // Center firework spray
        origin = centerOrigin;
        final angle = _rng.nextDouble() * 2 * math.pi;
        final speed = 120 + _rng.nextDouble() * 280;
        vx = speed * math.cos(angle);
        vy = -180 + (speed * math.sin(angle) * 0.6);
      }

      final color = colors[_rng.nextInt(colors.length)];
      final w = 6.0 + _rng.nextDouble() * 5.0;
      final h = 9.0 + _rng.nextDouble() * 7.0;

      _particles.add(
        _ConfettiParticle(
          origin: origin,
          vx: vx,
          vy: vy,
          size: Size(w, h),
          color: color,
          rotation: _rng.nextDouble() * 2 * math.pi,
          angularVelocity: (_rng.nextDouble() - 0.5) * 12.0,
          flipAngle: _rng.nextDouble() * math.pi,
          flipSpeed: 4.0 + _rng.nextDouble() * 10.0,
          delayFraction: (_rng.nextDouble() * 0.22),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _lastSize && size.width > 0 && size.height > 0) {
            _lastSize = size;
            _generateParticles(size);
          }

          if (!widget.animate) {
            return CustomPaint(
              size: size,
              painter: _ConfettiPainter(
                particles: _particles,
                progress: 0.5,
              ),
            );
          }

          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: size,
                painter: _ConfettiPainter(
                  particles: _particles,
                  progress: _controller.value,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      p.update(progress);
      if (p.opacity <= 0.01) continue;

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.currentRotation);

      // 3D tumble flutter: simulate flipping ribbon by scaling Y via cosine
      final flipScale = math.cos(p.currentFlip);
      canvas.scale(1.0, flipScale);

      final paint = Paint()
        ..color = p.color.withValues(alpha: p.opacity)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: p.size.width,
        height: p.size.height,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
