import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Ports the `wbSpin` keyframe animation: a rotating partial ring, used for
/// the nickname-checking and word-checking loading states.
class SpinnerRing extends StatefulWidget {
  const SpinnerRing({
    super.key,
    required this.size,
    required this.trackColor,
    required this.activeColor,
    this.strokeWidth = 2,
    this.period = const Duration(milliseconds: 700),
  });

  final double size;
  final Color trackColor;
  final Color activeColor;
  final double strokeWidth;
  final Duration period;

  @override
  State<SpinnerRing> createState() => _SpinnerRingState();
}

class _SpinnerRingState extends State<SpinnerRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _SpinnerPainter(
            trackColor: widget.trackColor,
            activeColor: widget.activeColor,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({required this.trackColor, required this.activeColor, required this.strokeWidth});

  final Color trackColor;
  final Color activeColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 0.6,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter oldDelegate) => false;
}
