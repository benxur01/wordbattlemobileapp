import 'dart:math' as math;

import 'package:flutter/material.dart';

/// `border: … dashed`. Flutter's [Border] only draws solid strokes, so the
/// design's dashed outlines (the matchmaking orbit ring, the locked profile
/// badges) are stroked by hand.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1,
    this.radius,
    this.circle = false,
    this.dash = 3,
    this.gap = 3,
  });

  final Color color;
  final double strokeWidth;

  /// Corner radius for the rounded-rectangle form. Ignored when [circle].
  final double? radius;
  final bool circle;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(inset, inset, size.width - strokeWidth, size.height - strokeWidth);
    final path = Path();
    if (circle) {
      path.addOval(rect);
    } else {
      path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius ?? 0)));
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.radius != radius || old.circle != circle;
}
