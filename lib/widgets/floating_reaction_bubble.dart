import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../audio/sound_effects.dart';
import '../theme.dart';

/// A floating, wobbling reaction bubble rendered with liquid frosted glass,
/// spring entrance physics, organic buoyancy float, and graceful pop exit.
class FloatingReactionBubble extends StatefulWidget {
  const FloatingReactionBubble({
    super.key,
    required this.emoji,
    this.sender,
    this.size = 56.0,
    this.duration = const Duration(milliseconds: 1800),
    this.onComplete,
    this.enableSound = false,
  });

  /// The reaction emoji string (e.g. '🔥', '😂').
  final String emoji;

  /// Optional sender name displayed in a frosted pill beneath the bubble.
  final String? sender;

  /// Diameter of the circular bubble.
  final double size;

  /// Total lifespan duration of the floating bubble animation.
  final Duration duration;

  /// Callback fired when the animation completes its lifecycle.
  final VoidCallback? onComplete;

  /// Whether to play a tap chime on appearance.
  final bool enableSound;

  @override
  State<FloatingReactionBubble> createState() => _FloatingReactionBubbleState();
}

class _FloatingReactionBubbleState extends State<FloatingReactionBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    if (widget.enableSound) {
      SoundEffects.instance.playTap();
    }

    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        // 1. Opacity Curve: In [0..0.15], Hold [0.15..0.75], Out [0.75..1.0]
        double opacity;
        if (t < 0.15) {
          opacity = (t / 0.15).clamp(0.0, 1.0);
        } else if (t <= 0.75) {
          opacity = 1.0;
        } else {
          opacity = (1.0 - ((t - 0.75) / 0.25)).clamp(0.0, 1.0);
        }

        // 2. Scale Curve: Spring pop in [0..0.2], subtle expand pop out [0.75..1.0]
        double scale;
        if (t < 0.2) {
          final popT = t / 0.2;
          scale = 0.2 + (0.95 * Curves.easeOutBack.transform(popT));
        } else if (t <= 0.75) {
          scale = 1.0;
        } else {
          final exitT = (t - 0.75) / 0.25;
          scale = 1.0 + (0.15 * Curves.easeOutQuad.transform(exitT));
        }

        // 3. Vertical Buoyancy Float (rises up to -38px)
        final translateY = -38.0 * Curves.easeOutCubic.transform(t);

        // 4. Horizontal Sinusoidal Wobble & Tilt (organic soap-bubble sway)
        final wobbleProgress = t * 3.0 * math.pi;
        final translateX = math.sin(wobbleProgress) * 5.0;
        final rotation = math.sin(wobbleProgress) * 0.055;

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(translateX, translateY),
            child: Transform.rotate(
              angle: rotation,
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main Frosted Glass Bubble
                    ClipRRect(
                      borderRadius: BorderRadius.circular(widget.size / 2),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          width: widget.size,
                          height: widget.size,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                WBColors.whiteA(.18),
                                WBColors.whiteA(.06),
                              ],
                            ),
                            border: Border.all(
                              color: WBColors.whiteA(.28),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: WBColors.accentA(.25),
                                blurRadius: 16,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            widget.emoji,
                            style: TextStyle(
                              fontSize: widget.size * 0.52,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Optional Sender Pill
                    if (widget.sender != null) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 100),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              border: Border.all(
                                color: WBColors.whiteA(.15),
                                width: 0.8,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              widget.sender!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: WBText.mono(
                                size: 10,
                                weight: FontWeight.w600,
                                color: WBColors.textA(.85),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
