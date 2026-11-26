import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sound_effects.dart';
import '../theme.dart';
import '../utils/hint_filter.dart';

import 'primary_button.dart';

/// Interactive practice hints filter panel featuring a horizontal A–Z starting
/// letter strip and a segmented word-length selector with a smoothly sliding
/// indicator pill and tactile haptic clicks.
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

  /// Ending letter of the current word of the day, pinned first in the strip.
  final String? defaultLetter;

  /// Active word length filter bucket.
  final HintLengthFilter selectedLength;

  final ValueChanged<String> onLetterSelected;
  final ValueChanged<HintLengthFilter> onLengthSelected;

  @override
  State<HintFilterBar> createState() => _HintFilterBarState();
}

class _HintFilterBarState extends State<HintFilterBar> {
  final ScrollController _letterScroll = ScrollController();

  @override
  void dispose() {
    _letterScroll.dispose();
    super.dispose();
  }

  void _selectLetter(String letter) {
    final normalized = HintFilterHelper.normalizeLetter(letter);
    if (normalized == null || normalized == HintFilterHelper.normalizeLetter(widget.selectedLetter)) {
      return;
    }
    HapticFeedback.selectionClick();
    SoundEffects.instance.playTap();
    widget.onLetterSelected(normalized);
  }

  void _selectLength(HintLengthFilter next) {
    if (next == widget.selectedLength) return;
    HapticFeedback.selectionClick();
    SoundEffects.instance.playTap();
    widget.onLengthSelected(next);
  }

  List<String> get _orderedLetters {
    final def = HintFilterHelper.normalizeLetter(widget.defaultLetter);
    if (def == null) return HintFilterHelper.alphabet;
    return [def, ...HintFilterHelper.alphabet.where((l) => l != def)];
  }

  @override
  Widget build(BuildContext context) {
    final def = HintFilterHelper.normalizeLetter(widget.defaultLetter);
    final active = HintFilterHelper.normalizeLetter(widget.selectedLetter) ?? def;
    final showResetLetter = def != null && active != null && active != def;
    final isLight = WBTheme.isLight;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight ? WBColors.bgPanel.withValues(alpha: .88) : WBColors.whiteA(.035),
        border: Border.all(color: isLight ? WBColors.textA(.10) : WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'FILTR · BOSHLANISH HARFI',
                style: WBText.mono(
                  size: 9.5,
                  weight: FontWeight.w600,
                  color: WBColors.textA(.52),
                  letterSpacing: .11,
                ),
              ),
              const Spacer(),
              if (showResetLetter)
                Pressable(
                  onTap: () {
                    if (_letterScroll.hasClients) {
                      _letterScroll.animateTo(
                        0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                      );
                    }
                    _selectLetter(def);
                  },
                  pressScale: .94,
                  borderRadius: BorderRadius.circular(8),
                  semanticLabel: "Asl harf ${def.toUpperCase()} ga qaytarish",
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Asl harf (${def.toUpperCase()})',
                      style: WBText.grotesk(
                        size: 11,
                        weight: FontWeight.w600,
                        color: WBColors.indigoText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStartingLetterStrip(active: active, defaultNorm: def, isLight: isLight),
          const SizedBox(height: 10),
          _buildLengthSegmentedBar(isLight: isLight),
        ],
      ),
    );
  }

  Widget _buildStartingLetterStrip({
    required String? active,
    required String? defaultNorm,
    required bool isLight,
  }) {
    final letters = _orderedLetters;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        controller: _letterScroll,
        scrollDirection: Axis.horizontal,
        itemCount: letters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final letter = letters[index];
          final selected = letter == active;
          final isWordDefault = letter == defaultNorm;
          final upper = letter.toUpperCase();

          return Semantics(
            selected: selected,
            button: true,
            label: "$upper harfi bilan boshlanadigan maslahatlar",
            child: Pressable(
              onTap: () => _selectLetter(letter),
              pressScale: .92,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(minWidth: 34),
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected ? wbIndigoGradient : null,
                  color: selected
                      ? null
                      : (isWordDefault
                          ? WBColors.indigoA(isLight ? .12 : .10)
                          : WBColors.whiteA(isLight ? .06 : .045)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? WBColors.indigo.withValues(alpha: .88)
                        : (isWordDefault ? WBColors.indigoA(.34) : WBColors.whiteA(.09)),
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: WBColors.indigo.withValues(alpha: isLight ? .20 : .28),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : const [],
                ),
                child: Text(
                  upper,
                  style: WBText.mono(
                    size: 12.5,
                    weight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? WBColors.indigoInk
                        : (isWordDefault ? WBColors.indigoText : WBColors.textA(.74)),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLengthSegmentedBar({required bool isLight}) {
    const filters = HintLengthFilter.values;
    final activeIndex = filters.indexOf(widget.selectedLength);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isLight ? WBColors.textA(.045) : WBColors.whiteA(.04),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WBColors.whiteA(.08)),
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
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: isLight ? .35 : .18)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: WBColors.indigo.withValues(alpha: isLight ? .20 : .28),
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
                      child: Semantics(
                        selected: filter == widget.selectedLength,
                        button: true,
                        label: filter.semanticDescription,
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
                                        : WBColors.textA(.70),
                                  ),
                                ),
                                if (filter.rangeBadge != null)
                                  Text(
                                    filter.rangeBadge!,
                                    style: WBText.mono(
                                      size: 9,
                                      weight: FontWeight.w600,
                                      color: filter == widget.selectedLength
                                          ? WBColors.indigoInk.withValues(alpha: .84)
                                          : WBColors.textA(.46),
                                    ),
                                  ),
                              ],
                            ),
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
