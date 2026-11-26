import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sound_effects.dart';
import '../theme.dart';
import '../utils/hint_filter.dart';

/// Interactive practice hints filter panel featuring a segmented word-length
/// selector with a smoothly sliding indicator pill and tactile haptic clicks.
class HintFilterBar extends StatefulWidget {
  const HintFilterBar({
    super.key,
    required this.selectedLetter,
    required this.defaultLetter,
    required this.selectedLength,
    required this.onLetterSelected,
    required this.onLengthSelected,
  });

  /// Active starting letter (`a`..`z`), or null when disabled.
  final String? selectedLetter;

  /// Ending letter of the current word of the day, highlighted first.
  final String? defaultLetter;

  /// Active word length filter bucket.
  final HintLengthFilter selectedLength;

  final ValueChanged<String> onLetterSelected;
  final ValueChanged<HintLengthFilter> onLengthSelected;

  @override
  State<HintFilterBar> createState() => _HintFilterBarState();
}

class _HintFilterBarState extends State<HintFilterBar> {
  void _selectLength(HintLengthFilter next) {
    if (next == widget.selectedLength) return;
    HapticFeedback.selectionClick();
    SoundEffects.instance.playTap();
    widget.onLengthSelected(next);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.035),
        border: Border.all(color: WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLengthSegmentedBar(),
        ],
      ),
    );
  }

  Widget _buildLengthSegmentedBar() {
    const filters = HintLengthFilter.values;
    final activeIndex = filters.indexOf(widget.selectedLength);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.04),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WBColors.whiteA(.07)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / filters.length;
          return Stack(
            children: [
              AnimatedPositioned(
                key: const ValueKey('hint_length_sliding_pill'),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: segmentWidth * activeIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: wbIndigoGradient,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: WBColors.indigo.withValues(alpha: .28),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final filter in filters)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selectLength(filter),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                filter.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WBText.grotesk(
                                  size: 11.5,
                                  weight: filter == widget.selectedLength
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: filter == widget.selectedLength
                                      ? WBColors.indigoInk
                                      : WBColors.textA(.68),
                                ),
                              ),
                              if (filter.rangeBadge != null)
                                Text(
                                  filter.rangeBadge!,
                                  style: WBText.mono(
                                    size: 9,
                                    weight: FontWeight.w600,
                                    color: filter == widget.selectedLength
                                        ? WBColors.indigoInk.withValues(alpha: .82)
                                        : WBColors.textA(.42),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
