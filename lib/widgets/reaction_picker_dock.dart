import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio/sound_effects.dart';
import '../theme.dart';

/// The default fixed reaction set accepted by the server.
const List<String> kDefaultDuelReactions = ['🔥', '😂', '👏', '😮', '🤝', '😢'];

/// An iOS-dock inspired floating reaction picker widget with liquid frosted
/// glass aesthetics, magnifying spring physics, tactile haptics, and tap audio.
class ReactionPickerDock extends StatelessWidget {
  const ReactionPickerDock({
    super.key,
    required this.onReact,
    this.reactions = kDefaultDuelReactions,
    this.itemSize = 32.0,
    this.spacing = 5.0,
    this.enableHaptics = true,
    this.enableAudio = true,
    this.onHapticFeedback,
    this.onAudioFeedback,
  });

  /// Invoked with the selected emoji string when tapped.
  final ValueChanged<String> onReact;

  /// The list of emoji strings to render in the dock.
  final List<String> reactions;

  /// The default width and height of each unmagnified emoji tile.
  final double itemSize;

  /// The horizontal gap between adjacent emoji tiles.
  final double spacing;

  /// Whether to fire light tactile haptics on selection.
  final bool enableHaptics;

  /// Whether to trigger the crisp UI tap chime on selection.
  final bool enableAudio;

  /// Optional custom callback when haptic feedback triggers (useful for tests).
  final VoidCallback? onHapticFeedback;

  /// Optional custom callback when audio triggers (useful for tests).
  final VoidCallback? onAudioFeedback;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: WBColors.whiteA(.045),
                  border: Border.all(color: WBColors.whiteA(.12)),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < reactions.length; i++) ...[
                _DockEmojiItem(
                  emoji: reactions[i],
                  size: itemSize,
                  onSelect: (emoji) {
                    if (enableHaptics) {
                      if (onHapticFeedback != null) {
                        onHapticFeedback!();
                      } else {
                        HapticFeedback.lightImpact();
                      }
                    }
                    if (enableAudio) {
                      if (onAudioFeedback != null) {
                        onAudioFeedback!();
                      } else {
                        SoundEffects.instance.playReaction();
                      }
                    }
                    onReact(emoji);
                  },
                ),
                if (i < reactions.length - 1) SizedBox(width: spacing),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DockEmojiItem extends StatefulWidget {
  const _DockEmojiItem({
    required this.emoji,
    required this.size,
    required this.onSelect,
  });

  final String emoji;
  final double size;
  final ValueChanged<String> onSelect;

  @override
  State<_DockEmojiItem> createState() => _DockEmojiItemState();
}

class _DockEmojiItemState extends State<_DockEmojiItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _liftAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 260),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.36).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuad,
        reverseCurve: Curves.easeOutBack,
      ),
    );

    _liftAnimation = Tween<double>(begin: 0.0, end: -6.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuad,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    HapticFeedback.selectionClick();
    _controller.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _controller.reverse();
    widget.onSelect(widget.emoji);
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Reaksiya: ${widget.emoji}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final lift = _liftAnimation.value;
            final scale = _scaleAnimation.value;
            final t = _controller.value;

            return Transform.translate(
              offset: Offset(0, lift),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      WBColors.whiteA(.05),
                      WBColors.accentA(.28),
                      t,
                    ),
                    border: Border.all(
                      color: Color.lerp(
                        WBColors.whiteA(.1),
                        WBColors.accentA(.55),
                        t,
                      )!,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: t > 0.01
                        ? [
                            BoxShadow(
                              color: WBColors.accentA(0.3 * t),
                              blurRadius: 10 * t,
                              spreadRadius: 1 * t,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    widget.emoji,
                    style: TextStyle(
                      fontSize: widget.size * 0.5,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
