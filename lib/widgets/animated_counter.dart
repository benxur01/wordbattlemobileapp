import 'package:flutter/material.dart';

/// An animated number counter that rolls smoothly from a starting value to a
/// target value with tabular figures (preventing width jitter) and an optional
/// spring settle punch on completion.
class AnimatedCounter extends StatefulWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.initialValue = 0,
    this.duration = const Duration(milliseconds: 900),
    this.curve = Curves.easeOutCubic,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.fractionDigits = 0,
    this.enableSpringSettle = true,
    this.onComplete,
  });

  /// The target number to count towards.
  final num value;

  /// The starting number when first mounted.
  final num initialValue;

  /// Total duration of the roll-up count animation.
  final Duration duration;

  /// Easing curve for the counting animation.
  final Curve curve;

  /// Text style applied to the formatted number string.
  final TextStyle? style;

  /// Prefix prepended before the number (e.g. '+').
  final String prefix;

  /// Suffix appended after the number (e.g. ' kun', '%').
  final String suffix;

  /// Number of decimal places to format (0 for integer counts).
  final int fractionDigits;

  /// Whether to fire a subtle scale bounce when the count completes.
  final bool enableSpringSettle;

  /// Optional callback invoked when the roll-up finishes.
  final ValueChanged<num>? onComplete;

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with TickerProviderStateMixin {
  late AnimationController _countController;
  late Animation<double> _countAnimation;
  AnimationController? _settleController;
  Animation<double>? _settleScaleAnimation;
  late num _fromValue;

  @override
  void initState() {
    super.initState();
    _fromValue = widget.initialValue;

    _countController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _countAnimation = Tween<double>(
      begin: _fromValue.toDouble(),
      end: widget.value.toDouble(),
    ).animate(CurvedAnimation(
      parent: _countController,
      curve: widget.curve,
    ));

    if (widget.enableSpringSettle) {
      _settleController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 240),
      );

      _settleScaleAnimation = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.06)
              .chain(CurveTween(curve: Curves.easeOutQuad)),
          weight: 40,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.06, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 60,
        ),
      ]).animate(_settleController!);
    }

    _countController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call(widget.value);
        if (widget.enableSpringSettle && mounted) {
          _settleController?.forward(from: 0.0);
        }
      }
    });

    _countController.forward();
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _fromValue = _countAnimation.value;
      _countAnimation = Tween<double>(
        begin: _fromValue.toDouble(),
        end: widget.value.toDouble(),
      ).animate(CurvedAnimation(
        parent: _countController,
        curve: widget.curve,
      ));
      _countController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _countController.dispose();
    _settleController?.dispose();
    super.dispose();
  }

  String _formatNumber(double current) {
    if (widget.fractionDigits <= 0) {
      return current.round().toString();
    }
    return current.toStringAsFixed(widget.fractionDigits);
  }

  @override
  Widget build(BuildContext context) {
    // Merge fontFeatures to ensure tabular numbers without jitter
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final tabularStyle = baseStyle.copyWith(
      fontFeatures: [
        ...?baseStyle.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
    );

    final content = AnimatedBuilder(
      animation: _countAnimation,
      builder: (context, _) {
        final formatted = _formatNumber(_countAnimation.value);
        return Text(
          '${widget.prefix}$formatted${widget.suffix}',
          style: tabularStyle,
        );
      },
    );

    if (_settleScaleAnimation != null) {
      return AnimatedBuilder(
        animation: _settleScaleAnimation!,
        builder: (context, child) => Transform.scale(
          scale: _settleScaleAnimation!.value,
          child: child,
        ),
        child: content,
      );
    }

    return content;
  }
}
