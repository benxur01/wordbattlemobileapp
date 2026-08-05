import 'package:flutter/material.dart';

/// Ports the `wbRadar` keyframe animation: three expanding, fading rings,
/// staggered 0.8s apart, used on the matchmaking screen.
class RadarRings extends StatefulWidget {
  const RadarRings({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<RadarRings> createState() => _RadarRingsState();
}

class _RadarRingsState extends State<RadarRings> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _ring(double delayFraction) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = (_c.value + delayFraction) % 1.0;
        final scale = 0.35 + (1.9 - 0.35) * t;
        final opacity = t < 0.05 ? 0.55 * (t / 0.05) : 0.55 * (1 - t);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: widget.color.withValues(alpha: opacity.clamp(0, 1)), width: 1.5),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(0),
          _ring(0.8 / 2.4),
          _ring(1.6 / 2.4),
        ],
      ),
    );
  }
}
