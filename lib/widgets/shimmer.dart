import 'package:flutter/material.dart';
import '../theme.dart';

/// Data shared down the widget tree by a [ShimmerScope] so that all skeleton
/// elements shimmer synchronously in a single wave.
class ShimmerScopeData {
  const ShimmerScopeData({
    required this.percent,
    required this.baseColor,
    required this.highlightColor,
  });

  final double percent;
  final Color baseColor;
  final Color highlightColor;
}

class _ShimmerInherited extends InheritedWidget {
  const _ShimmerInherited({
    required this.data,
    required super.child,
  });

  final ShimmerScopeData data;

  @override
  bool updateShouldNotify(_ShimmerInherited oldWidget) =>
      data.percent != oldWidget.data.percent ||
      data.baseColor != oldWidget.data.baseColor ||
      data.highlightColor != oldWidget.data.highlightColor;
}

/// Orchestrates a synchronized left-to-right shimmering gradient across all
/// descendant [ShimmerBox] widgets.
class ShimmerScope extends StatefulWidget {
  const ShimmerScope({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1400),
    this.baseColor,
    this.highlightColor,
  });

  final Widget child;
  final Duration duration;
  final Color? baseColor;
  final Color? highlightColor;

  static ShimmerScopeData? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShimmerInherited>()?.data;
  }

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? WBColors.whiteA(.06);
    final highlight = widget.highlightColor ?? WBColors.whiteA(.16);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return _ShimmerInherited(
          data: ShimmerScopeData(
            percent: _controller.value,
            baseColor: base,
            highlightColor: highlight,
          ),
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}

/// A placeholder shape (rectangle, rounded rectangle, or circle) painted with
/// an animated light sweep.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.baseColor,
    this.highlightColor,
  });

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final Color? baseColor;
  final Color? highlightColor;

  /// Convenience factory for circular skeletons (e.g. avatars).
  factory ShimmerBox.circle({
    Key? key,
    required double size,
    Color? baseColor,
    Color? highlightColor,
  }) {
    return ShimmerBox(
      key: key,
      width: size,
      height: size,
      shape: BoxShape.circle,
      baseColor: baseColor,
      highlightColor: highlightColor,
    );
  }

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  AnimationController? _fallbackController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hasScope = ShimmerScope.of(context) != null;
    if (!hasScope && _fallbackController == null) {
      _fallbackController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat();
    } else if (hasScope && _fallbackController != null) {
      _fallbackController?.dispose();
      _fallbackController = null;
    }
  }

  @override
  void dispose() {
    _fallbackController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scopeData = ShimmerScope.of(context);
    final fallback = _fallbackController;

    if (scopeData != null) {
      return _buildContainer(
        percent: scopeData.percent,
        baseColor: widget.baseColor ?? scopeData.baseColor,
        highlightColor: widget.highlightColor ?? scopeData.highlightColor,
      );
    }

    if (fallback != null) {
      return AnimatedBuilder(
        animation: fallback,
        builder: (context, _) => _buildContainer(
          percent: fallback.value,
          baseColor: widget.baseColor ?? WBColors.whiteA(.06),
          highlightColor: widget.highlightColor ?? WBColors.whiteA(.16),
        ),
      );
    }

    return _buildContainer(
      percent: 0.0,
      baseColor: widget.baseColor ?? WBColors.whiteA(.06),
      highlightColor: widget.highlightColor ?? WBColors.whiteA(.16),
    );
  }

  Widget _buildContainer({
    required double percent,
    required Color baseColor,
    required Color highlightColor,
  }) {
    // Slide gradient from -1.0 to +2.0 across animation cycle
    final start = -1.0 + (percent * 3.0);
    final end = start + 1.0;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        shape: widget.shape,
        borderRadius: widget.shape == BoxShape.circle
            ? null
            : (widget.borderRadius ?? BorderRadius.circular(8)),
        gradient: LinearGradient(
          begin: Alignment(start, 0),
          end: Alignment(end, 0),
          colors: [
            baseColor,
            highlightColor,
            baseColor,
          ],
          stops: const [0.1, 0.5, 0.9],
        ),
      ),
    );
  }
}
