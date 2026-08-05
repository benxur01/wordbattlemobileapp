import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The design draws its checkmarks and chevrons as a rotated box with only two
/// borders (`border-left`+`border-bottom` at -45° = a tick, `border-top`+
/// `border-right` at 45° = a chevron). Material's `Icons.check` /
/// `Icons.arrow_forward` are visibly different shapes, so those two-sided
/// boxes are reproduced literally here.
class StrokeGlyph extends StatelessWidget {
  const StrokeGlyph._({
    required this.width,
    required this.height,
    required this.thickness,
    required this.color,
    required this.turn,
    required this.left,
    required this.bottom,
    required this.top,
    required this.right,
    this.offset = Offset.zero,
  });

  /// `border-left` + `border-bottom`, rotated -45°.
  const StrokeGlyph.check({
    required double width,
    required double height,
    required double thickness,
    required Color color,
    Offset offset = Offset.zero,
  }) : this._(
          width: width,
          height: height,
          thickness: thickness,
          color: color,
          turn: -45,
          left: true,
          bottom: true,
          top: false,
          right: false,
          offset: offset,
        );

  /// `border-top` + `border-right`, rotated 45° — points right.
  const StrokeGlyph.chevronRight({
    required double size,
    required double thickness,
    required Color color,
    Offset offset = Offset.zero,
  }) : this._(
          width: size,
          height: size,
          thickness: thickness,
          color: color,
          turn: 45,
          left: false,
          bottom: false,
          top: true,
          right: true,
          offset: offset,
        );

  /// `border-left` + `border-bottom`, rotated 45° — points left.
  const StrokeGlyph.chevronLeft({
    required double size,
    required double thickness,
    required Color color,
    Offset offset = Offset.zero,
  }) : this._(
          width: size,
          height: size,
          thickness: thickness,
          color: color,
          turn: 45,
          left: true,
          bottom: true,
          top: false,
          right: false,
          offset: offset,
        );

  final double width;
  final double height;
  final double thickness;
  final Color color;
  final double turn; // degrees
  final bool left;
  final bool bottom;
  final bool top;
  final bool right;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: color, width: thickness);
    const none = BorderSide.none;
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: turn * math.pi / 180,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            border: Border(
              left: left ? side : none,
              bottom: bottom ? side : none,
              top: top ? side : none,
              right: right ? side : none,
            ),
          ),
        ),
      ),
    );
  }
}
