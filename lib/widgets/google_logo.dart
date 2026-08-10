import 'package:flutter/material.dart';

import 'svg_path.dart';

/// Google's four-colour "G", drawn from the sign-in asset's own path data.
///
/// Shipping the mark as an image file would be the obvious move, and it is the
/// one thing this project cannot do cheaply: there is no `assets:` section in
/// `pubspec.yaml` at all — only fonts — so a logo would mean either one bitmap
/// per screen density or pulling in an SVG runtime for a single 20dp glyph.
/// The nav icons already answered this question (see `nav_icons.dart`): keep
/// the source path data and draw it with [parseSvgPath]. Four filled paths cost
/// nothing in the APK and stay sharp at any density.
///
/// The path data is the 48×48 viewBox from Google's own sign-in button asset,
/// kept verbatim. It is not redrawn or simplified — a trademark that has been
/// traced by hand is a trademark drawn wrong.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

/// The mark's four arcs with the brand colours they are published in. They abut
/// rather than overlap, so the drawing order carries no meaning.
const _arcs = <(Color, String)>[
  (
    Color(0xFF4285F4),
    'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6'
        'c4.51-4.18 7.09-10.36 7.09-17.65z',
  ),
  (
    Color(0xFF34A853),
    'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91'
        'l-7.98 6.19C6.51 42.62 14.62 48 24 48z',
  ),
  (
    Color(0xFFFBBC05),
    'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24'
        'c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
  ),
  (
    Color(0xFFEA4335),
    'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22'
        'l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z',
  ),
];

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    for (final (color, d) in _arcs) {
      canvas.drawPath(parseSvgPath(d), Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleLogoPainter old) => false;
}
