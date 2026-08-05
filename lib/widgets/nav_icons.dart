import 'package:flutter/material.dart';

import 'svg_path.dart';

/// The four bottom-nav icons, drawn from the design's own SVG path data
/// (20×20 viewBox, 1.7 stroke, round caps and joins) instead of the Material
/// glyphs that previously stood in for them.
enum WBNavIcon { home, friends, board, profile }

const _paths = <WBNavIcon, List<String>>{
  // shield with a lightning bolt
  WBNavIcon.home: [
    'M10 2.6 16.4 5.2v4.9c0 3.4-2.6 5.7-6.4 7.3-3.8-1.6-6.4-3.9-6.4-7.3V5.2Z',
    'M10.9 7.1 8.7 10.5h2.5l-1.1 2.6',
  ],
  // two people
  WBNavIcon.friends: [
    'M2.9 15.9c0-2.5 2.1-3.9 4.8-3.9s4.8 1.4 4.8 3.9',
    'M13.4 5.4a2.6 2.6 0 0 1 0 4.5',
    'M14.4 12.2c1.9.4 3.1 1.6 3.1 3.7',
  ],
  // trophy
  WBNavIcon.board: [
    'M6.4 3.4h7.2v4.2a3.6 3.6 0 0 1-7.2 0Z',
    'M6.4 4.6H4.1a2.3 2.3 0 0 0 2.3 3',
    'M13.6 4.6h2.3a2.3 2.3 0 0 1-2.3 3',
    'M10 11.2v2.5',
    'M7.4 16.6h5.2l-.6-2.9H8Z',
  ],
  // bust
  WBNavIcon.profile: ['M4.2 16.8c0-3.1 2.6-4.8 5.8-4.8s5.8 1.7 5.8 4.8'],
};

const _circles = <WBNavIcon, List<(double, double, double)>>{
  WBNavIcon.friends: [(7.7, 7.6, 2.7)],
  WBNavIcon.profile: [(10.0, 7.1, 3.1)],
};

class NavIcon extends StatelessWidget {
  const NavIcon({super.key, required this.icon, required this.color, this.size = 19});

  final WBNavIcon icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _NavIconPainter(icon: icon, color: color)),
    );
  }
}

class _NavIconPainter extends CustomPainter {
  _NavIconPainter({required this.icon, required this.color});

  final WBNavIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 20, size.height / 20);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final d in _paths[icon] ?? const <String>[]) {
      canvas.drawPath(parseSvgPath(d), paint);
    }
    for (final c in _circles[icon] ?? const <(double, double, double)>[]) {
      canvas.drawCircle(Offset(c.$1, c.$2), c.$3, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter old) => old.icon != icon || old.color != color;
}
