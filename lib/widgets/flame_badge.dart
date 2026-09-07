import 'package:flutter/material.dart';
import '../theme.dart';

/// Ports the `wbFlame` keyframe animation: a small flickering flame shape
/// used next to streak counters.
class FlameIcon extends StatefulWidget {
  const FlameIcon({super.key, this.width = 8, this.height = 11, this.animate = true});

  final double width;
  final double height;

  /// The lose screen and the profile badge draw the same shape without
  /// `animation:wbFlame`, so they hold still.
  final bool animate;

  @override
  State<FlameIcon> createState() => _FlameIconState();
}

class _FlameIconState extends State<FlameIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

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
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -2 * t),
          child: Transform.scale(
            scaleY: 1.0 + 0.14 * t,
            child: Opacity(opacity: 0.95 + 0.05 * t, child: child),
          ),
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          gradient: wbFlameGradient,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(100),
            topRight: Radius.circular(100),
            bottomLeft: Radius.circular(60),
            bottomRight: Radius.circular(60),
          ),
        ),
      ),
    );
  }
}
