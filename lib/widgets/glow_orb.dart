import 'package:flutter/material.dart';

/// Ports the `wbGlow` keyframe animation: a soft pulsing scale + box-shadow
/// glow, used behind the onboarding logo and the lobby "JANG BOSHLASH" CTA.
class GlowOrb extends StatefulWidget {
  const GlowOrb({
    super.key,
    required this.child,
    required this.glowColor,
    this.period = const Duration(milliseconds: 2800),
    this.borderRadius,
  });

  final Widget child;
  final Color glowColor;
  final Duration period;

  /// The shape the glow is cast from. Null means a circle (the lobby CTA); the
  /// onboarding logo is a 34px-rounded square, and casting a circular glow
  /// behind it left dark crescents poking out past its corners.
  final BorderRadius? borderRadius;

  @override
  State<GlowOrb> createState() => _GlowOrbState();
}

class _GlowOrbState extends State<GlowOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)..repeat(reverse: true);

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
        final scale = 1.0 + 0.045 * t;
        final spread = 26.0 * t;
        final alpha = 0.34 * (1 - t);
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              shape: widget.borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: widget.borderRadius,
              boxShadow: [
                BoxShadow(
                  color: widget.glowColor.withValues(alpha: alpha),
                  spreadRadius: spread,
                  blurRadius: 0,
                ),
                BoxShadow(
                  color: widget.glowColor.withValues(alpha: .18 + .14 * t),
                  blurRadius: 50,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
