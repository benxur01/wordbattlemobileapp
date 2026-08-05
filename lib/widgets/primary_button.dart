import 'package:flutter/material.dart';

/// Reusable press-scale wrapper: ports the design's `style-active`
/// (`transform:scale(.98)` / `.95` / `.96`) and `style-hover` overlays,
/// which the design-tool runtime applied via CSS pseudo-classes.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressScale = 0.98,
    this.hoverColor,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressScale;
  final Color? hoverColor;
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
        onTapCancel: widget.onTap == null ? null : () => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? widget.pressScale : 1.0,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: _hover ? widget.hoverColor : Colors.transparent,
              borderRadius: widget.borderRadius,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
