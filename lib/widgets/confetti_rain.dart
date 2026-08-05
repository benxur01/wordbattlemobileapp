import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Ports the `wbFall` keyframe animation: a handful of falling/rotating
/// confetti pieces used on the win screen. Each piece has its own left
/// position, size, color, duration and delay — matching the five
/// hand-placed `<div>`s in the source.
class ConfettiRain extends StatelessWidget {
  const ConfettiRain({super.key});

  static const _pieces = [
    _Piece(left: .12, width: 8, height: 14, color: Color(0xFFF7B733), durationMs: 3000, delayMs: 0),
    _Piece(left: .34, width: 7, height: 12, color: Color(0xFF35D07F), durationMs: 3400, delayMs: 400),
    _Piece(left: .58, width: 9, height: 13, color: Color(0xFF7C8AFF), durationMs: 3100, delayMs: 900),
    _Piece(left: .78, width: 7, height: 15, color: Color(0xFFF7B733), durationMs: 3600, delayMs: 200),
    _Piece(left: .88, width: 8, height: 11, color: Color(0xFFFF9A55), durationMs: 3300, delayMs: 1300),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              for (final p in _pieces)
                Positioned(
                  left: constraints.maxWidth * p.left,
                  top: 0,
                  child: _FallingPiece(piece: p, travel: 520),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.left,
    required this.width,
    required this.height,
    required this.color,
    required this.durationMs,
    required this.delayMs,
  });

  final double left;
  final double width;
  final double height;
  final Color color;
  final int durationMs;
  final int delayMs;
}

class _FallingPiece extends StatefulWidget {
  const _FallingPiece({required this.piece, required this.travel});

  final _Piece piece;
  final double travel;

  @override
  State<_FallingPiece> createState() => _FallingPieceState();
}

class _FallingPieceState extends State<_FallingPiece> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.piece.durationMs),
  )..repeat();

  /// CSS `animation-delay` expressed as a phase offset, so no extra timer has
  /// to be scheduled (and left dangling) per confetti piece.
  late final double _phase = widget.piece.delayMs / widget.piece.durationMs;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = (_c.value + 1 - _phase % 1) % 1.0;
        final y = -40 + widget.travel * t;
        final opacity = t < 0.12 ? t / 0.12 : (1 - t).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, y),
          child: Transform.rotate(
            angle: t * 420 * math.pi / 180,
            child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
          ),
        );
      },
      child: Container(
        width: widget.piece.width,
        height: widget.piece.height,
        color: widget.piece.color,
      ),
    );
  }
}
