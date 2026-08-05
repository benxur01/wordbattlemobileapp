import 'dart:ui';

/// Minimal SVG path-data parser, enough for the icon paths copied verbatim out
/// of the design file (`M/m L/l H/h V/v C/c S/s Q/q A/a Z`).
///
/// The nav-bar icons in the source are hand-drawn `<svg>` strokes, not an icon
/// font; substituting Material glyphs changed their silhouette noticeably, so
/// the original path data is kept and drawn as-is.
Path parseSvgPath(String d) {
  final tokens = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?')
      .allMatches(d)
      .map((m) => m[0]!)
      .toList();

  final path = Path();
  var i = 0;
  var cx = 0.0, cy = 0.0; // current point
  var sx = 0.0, sy = 0.0; // subpath start
  var lastC = Offset.zero; // previous cubic control point, for S/s
  var lastQ = Offset.zero; // previous quadratic control point, for T/t
  String? cmd;
  var prevCmd = '';

  double num() => double.parse(tokens[i++]);
  bool isCommand(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);

  while (i < tokens.length) {
    if (isCommand(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd == null) {
      break;
    } else if (cmd == 'M') {
      cmd = 'L'; // implicit lineto after a moveto
    } else if (cmd == 'm') {
      cmd = 'l';
    }

    switch (cmd) {
      case 'M':
      case 'm':
        final x = num(), y = num();
        cx = cmd == 'M' ? x : cx + x;
        cy = cmd == 'M' ? y : cy + y;
        sx = cx;
        sy = cy;
        path.moveTo(cx, cy);
      case 'L':
      case 'l':
        final x = num(), y = num();
        cx = cmd == 'L' ? x : cx + x;
        cy = cmd == 'L' ? y : cy + y;
        path.lineTo(cx, cy);
      case 'H':
      case 'h':
        final x = num();
        cx = cmd == 'H' ? x : cx + x;
        path.lineTo(cx, cy);
      case 'V':
      case 'v':
        final y = num();
        cy = cmd == 'V' ? y : cy + y;
        path.lineTo(cx, cy);
      case 'C':
      case 'c':
        final rel = cmd == 'c';
        final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
        final c1 = Offset(ox + num(), oy + num());
        final c2 = Offset(ox + num(), oy + num());
        final end = Offset(ox + num(), oy + num());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        lastC = c2;
        cx = end.dx;
        cy = end.dy;
      case 'S':
      case 's':
        final rel = cmd == 's';
        final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
        final reflect = RegExp(r'^[CcSs]$').hasMatch(prevCmd)
            ? Offset(2 * cx - lastC.dx, 2 * cy - lastC.dy)
            : Offset(cx, cy);
        final c2 = Offset(ox + num(), oy + num());
        final end = Offset(ox + num(), oy + num());
        path.cubicTo(reflect.dx, reflect.dy, c2.dx, c2.dy, end.dx, end.dy);
        lastC = c2;
        cx = end.dx;
        cy = end.dy;
      case 'Q':
      case 'q':
        final rel = cmd == 'q';
        final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
        final c = Offset(ox + num(), oy + num());
        final end = Offset(ox + num(), oy + num());
        path.quadraticBezierTo(c.dx, c.dy, end.dx, end.dy);
        lastQ = c;
        cx = end.dx;
        cy = end.dy;
      case 'T':
      case 't':
        final rel = cmd == 't';
        final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
        final c = RegExp(r'^[QqTt]$').hasMatch(prevCmd)
            ? Offset(2 * cx - lastQ.dx, 2 * cy - lastQ.dy)
            : Offset(cx, cy);
        final end = Offset(ox + num(), oy + num());
        path.quadraticBezierTo(c.dx, c.dy, end.dx, end.dy);
        lastQ = c;
        cx = end.dx;
        cy = end.dy;
      case 'A':
      case 'a':
        final rel = cmd == 'a';
        final rx = num(), ry = num(), rot = num();
        final largeArc = num() != 0, sweep = num() != 0;
        final x = num(), y = num();
        cx = rel ? cx + x : x;
        cy = rel ? cy + y : y;
        path.arcToPoint(
          Offset(cx, cy),
          radius: Radius.elliptical(rx, ry),
          rotation: rot,
          largeArc: largeArc,
          clockwise: sweep,
        );
      case 'Z':
      case 'z':
        path.close();
        cx = sx;
        cy = sy;
      default:
        return path; // unsupported command — stop rather than misdraw
    }
    prevCmd = cmd;
  }

  return path;
}
