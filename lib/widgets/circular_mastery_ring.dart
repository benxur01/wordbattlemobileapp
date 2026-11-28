import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Spring-animated circular mastery indicator (`Curves.easeOutBack`) paired with
/// a radial letter-particle burst when a rare-letter word is accepted.
class CircularMasteryRing extends StatefulWidget {
  const CircularMasteryRing({
    super.key,
    required this.letter,
    required this.progress,
    required this.accentColor,
    this.mastered = false,
    this.burstNonce = 0,
    this.size = 52,
    this.strokeWidth = 4.2,
  });

  final String letter;
  final double progress;
  final Color accentColor;
  final bool mastered;
  final int burstNonce;
  final double size;
  final double strokeWidth;

  @override
  State<CircularMasteryRing> createState() => _CircularMasteryRingState();
}

class _CircularMasteryRingState extends State<CircularMasteryRing>
    with TickerProviderStateMixin {
  late final AnimationController _ringController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  late final AnimationController _burstController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  late Animation<double> _progressAnim = AlwaysStoppedAnimation(widget.progress.clamp(0.0, 1.0));
  double _currentProgress = 0;

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.progress.clamp(0.0, 1.0);
    _progressAnim = AlwaysStoppedAnimation(_currentProgress);
  }

  @override
  void didUpdateWidget(covariant CircularMasteryRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.progress.clamp(0.0, 1.0);
    if ((oldWidget.progress - widget.progress).abs() > 0.001) {
      final begin = _progressAnim.value.clamp(0.0, 1.0);
      _progressAnim = Tween<double>(begin: begin, end: next).animate(
        CurvedAnimation(parent: _ringController, curve: Curves.easeOutBack),
      );
      _currentProgress = next;
      _ringController.forward(from: 0);
    }
    if (oldWidget.burstNonce != widget.burstNonce) {
      _burstController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ringController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final upper = widget.letter.trim().isEmpty ? 'X' : widget.letter.trim()[0].toUpperCase();
    final ringColor = widget.mastered ? WBColors.green : widget.accentColor;
    final pct = (_currentProgress * 100).round();

    return Semantics(
      excludeSemantics: true,
      label: "$upper harfi mahorati: $pct foiz",
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ringController, _burstController]),
          builder: (context, child) {
            final value = _progressAnim.value;
            final scalePulse = _burstController.isAnimating
                ? 1.0 + math.sin(_burstController.value * math.pi) * 0.08
                : 1.0;

            return Transform.scale(
              scale: scalePulse,
              child: CustomPaint(
                painter: _MasteryRingAndParticlePainter(
                  progress: value,
                  color: ringColor,
                  trackColor: WBColors.hairlineStrong,
                  strokeWidth: widget.strokeWidth,
                  burstProgress: _burstController.isAnimating ? _burstController.value : 0.0,
                  letter: upper,
                ),
                child: Center(
                  child: Text(
                    upper,
                    style: WBText.mono(
                      size: widget.size * 0.36,
                      weight: FontWeight.w700,
                      color: widget.mastered ? WBColors.green : WBColors.text,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MasteryRingAndParticlePainter extends CustomPainter {
  _MasteryRingAndParticlePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    required this.burstProgress,
    required this.letter,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final double burstProgress;
  final String letter;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    final clampedSweep = progress.clamp(0.0, 1.12);
    if (clampedSweep > 0.002) {
      final activePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * clampedSweep.clamp(0.0, 1.0),
        false,
        activePaint,
      );
    }

    if (burstProgress > 0 && burstProgress < 1) {
      final eased = Curves.easeOutCubic.transform(burstProgress);
      final fade = (1.0 - burstProgress).clamp(0.0, 1.0);
      const count = 8;
      for (var i = 0; i < count; i++) {
        final angle = (math.pi * 2 / count) * i - math.pi / 4;
        final dist = radius + 4 + (eased * 16);
        final pos = center + Offset(math.cos(angle) * dist, math.sin(angle) * dist);

        if (i.isEven) {
          final tp = TextPainter(
            text: TextSpan(
              text: letter,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 8.5 + (1 - eased) * 2.5,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: fade * 0.9),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
        } else {
          final sparkPaint = Paint()
            ..color = color.withValues(alpha: fade * 0.85)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(pos, 2.2 * (1 - eased * 0.35), sparkPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MasteryRingAndParticlePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.burstProgress != burstProgress ||
      oldDelegate.letter != letter;
}
