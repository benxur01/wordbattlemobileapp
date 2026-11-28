import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../audio/sound_effects.dart';
import '../theme.dart';
import '../utils/rare_letter_drill.dart';
import 'circular_mastery_ring.dart';
import 'primary_button.dart';

/// Interactive X & Q rare-letter drill selector and active prompt card styled
/// cleanly with restrained obsidian surfaces.
class RareLetterDrillPanel extends StatelessWidget {
  const RareLetterDrillPanel({
    super.key,
    required this.drills,
    required this.activeLetter,
    required this.progressMap,
    required this.burstNonceMap,
    required this.onSelectLetter,
    this.onRotatePrompt,
    this.onResetProgress,
    this.onTapWordChip,
  });

  final List<RareLetterDrillDto> drills;
  final String activeLetter;
  final Map<String, RareLetterProgress> progressMap;
  final Map<String, int> burstNonceMap;
  final ValueChanged<String> onSelectLetter;
  final VoidCallback? onRotatePrompt;
  final VoidCallback? onResetProgress;
  final ValueChanged<String>? onTapWordChip;

  @override
  Widget build(BuildContext context) {
    final catalog = drills.isNotEmpty ? drills : RareLetterDrillHelper.fallbackDrills();
    final selectedKey = RareLetterDrillHelper.normalizeLetter(activeLetter) ?? 'x';
    final activeDrill = catalog.firstWhere(
      (d) => d.normalizedLetter == selectedKey,
      orElse: () => catalog.first,
    );
    final activeProgress = progressMap[activeDrill.normalizedLetter] ??
        RareLetterProgress(
          letter: activeDrill.normalizedLetter,
          solvedWords: const [],
          targetCount: activeDrill.targetCount,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Side-by-side X & Q Mastery Selector Tiles
        Row(
          children: [
            for (var i = 0; i < catalog.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _DrillSelectorTile(
                  drill: catalog[i],
                  progress: progressMap[catalog[i].normalizedLetter] ??
                      RareLetterProgress(
                        letter: catalog[i].normalizedLetter,
                        solvedWords: const [],
                        targetCount: catalog[i].targetCount,
                      ),
                  selected: catalog[i].normalizedLetter == activeDrill.normalizedLetter,
                  burstNonce: burstNonceMap[catalog[i].normalizedLetter] ?? 0,
                  accentColor: catalog[i].normalizedLetter == 'x' ? WBColors.cta : WBColors.amber,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    SoundEffects.instance.playTap();
                    onSelectLetter(catalog[i].normalizedLetter);
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        // 2. Active Drill Prompt Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: WBColors.bgSurface,
            border: Border.all(color: WBColors.hairline),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      activeDrill.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.mono(
                        size: 10,
                        weight: FontWeight.w600,
                        color: WBColors.textA(.5),
                        letterSpacing: .11,
                      ),
                    ),
                  ),
                  if (onRotatePrompt != null) ...[
                    const SizedBox(width: 8),
                    Pressable(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onRotatePrompt!();
                      },
                      pressScale: .94,
                      borderRadius: BorderRadius.circular(8),
                      semanticLabel: "Keyingi namuna so'zni ko'rsatish",
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: WBColors.bgElevated,
                          border: Border.all(color: WBColors.hairlineStrong),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 12.5, color: WBColors.textA(.72)),
                            const SizedBox(width: 4),
                            Text(
                              'Keyingi',
                              style: WBText.mono(
                                size: 10,
                                weight: FontWeight.w600,
                                color: WBColors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    activeDrill.promptWord,
                    style: WBText.grotesk(
                      size: 26,
                      weight: FontWeight.w700,
                      color: WBColors.text,
                      letterSpacing: -0.02,
                    ),
                  ),
                  if (activeDrill.promptIpa.isNotEmpty)
                    Text(
                      activeDrill.promptIpa,
                      style: WBText.mono(size: 12.5, color: WBColors.textA(.46)),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: WBColors.bgElevated,
                      border: Border.all(color: WBColors.hairlineStrong),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'MAQSAD: ${activeDrill.upperLetter}-SO\'Z',
                      style: WBText.mono(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: WBColors.text,
                        letterSpacing: .06,
                      ),
                    ),
                  ),
                ],
              ),
              if (activeDrill.promptMeaning.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  activeDrill.promptMeaning,
                  style: WBText.grotesk(size: 14, height: 1.45, color: WBColors.textA(.74)),
                ),
              ],
              if (activeDrill.tip.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: WBColors.bgElevated,
                    border: Border.all(color: WBColors.hairline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 15,
                          color: WBColors.amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          activeDrill.tip,
                          style: WBText.grotesk(
                            size: 12,
                            height: 1.42,
                            color: WBColors.textA(.68),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (activeProgress.solvedWords.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  "MAHORAT · ${activeProgress.solvedCount}/${activeProgress.targetCount} (${activeProgress.percentage}%)",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.mono(
                    size: 10,
                    weight: FontWeight.w600,
                    color: activeProgress.isMastered ? WBColors.green : WBColors.textA(.55),
                    letterSpacing: .1,
                  ),
                ),
              ),
              if (onResetProgress != null)
                Pressable(
                  onTap: onResetProgress,
                  pressScale: .94,
                  borderRadius: BorderRadius.circular(8),
                  semanticLabel: "${activeDrill.upperLetter} mashqini qayta boshlash",
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Qayta boshlash',
                      style: WBText.grotesk(
                        size: 11.5,
                        weight: FontWeight.w500,
                        color: WBColors.textA(.48),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final solved in activeProgress.solvedWords)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: WBColors.bgSurface,
                    border: Border.all(color: WBColors.green.withValues(alpha: .42)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 14, color: WBColors.green),
                      const SizedBox(width: 5),
                      Text(
                        solved,
                        style: WBText.grotesk(
                          size: 14,
                          weight: FontWeight.w600,
                          color: WBColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (activeDrill.hints.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            "NAMUNA ${activeDrill.upperLetter}-SO'ZLAR",
            style: WBText.mono(
              size: 10,
              weight: FontWeight.w600,
              color: WBColors.textA(.46),
              letterSpacing: .1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hint in activeDrill.hints)
                Pressable(
                  onTap: onTapWordChip == null ? null : () => onTapWordChip!(hint),
                  pressScale: .95,
                  borderRadius: BorderRadius.circular(12),
                  semanticLabel: "$hint namuna so'zini sinov maydoniga kiritish",
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: WBColors.bgSurface,
                      border: Border.all(color: WBColors.hairline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      hint,
                      style: WBText.grotesk(
                        size: 14.5,
                        weight: FontWeight.w600,
                        color: WBColors.textA(.86),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DrillSelectorTile extends StatelessWidget {
  const _DrillSelectorTile({
    required this.drill,
    required this.progress,
    required this.selected,
    required this.burstNonce,
    required this.accentColor,
    required this.onTap,
  });

  final RareLetterDrillDto drill;
  final RareLetterProgress progress;
  final bool selected;
  final int burstNonce;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? (progress.isMastered ? WBColors.green : WBColors.hairlineStrong)
        : WBColors.hairline;

    return Semantics(
      selected: selected,
      button: true,
      label: "${drill.upperLetter} harfi drilli, ${progress.solvedCount} dan ${progress.targetCount} ta so'z",
      child: Pressable(
        onTap: onTap,
        pressScale: .97,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? WBColors.bgElevated : WBColors.bgSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: selected ? 1.3 : 1.0),
          ),
          child: Row(
            children: [
              CircularMasteryRing(
                letter: drill.upperLetter,
                progress: progress.ratio,
                accentColor: accentColor,
                mastered: progress.isMastered,
                burstNonce: burstNonce,
                size: 46,
                strokeWidth: 3.8,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      progress.isMastered ? 'USTA · ${drill.upperLetter}' : drill.badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.mono(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: progress.isMastered ? WBColors.green : WBColors.textA(.54),
                        letterSpacing: .06,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${progress.solvedCount}/${progress.targetCount} so\'z',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.grotesk(
                        size: 14,
                        weight: FontWeight.w700,
                        color: WBColors.text,
                      ),
                    ),
                    Text(
                      '${progress.percentage}% mahorat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.mono(
                        size: 10,
                        color: WBColors.textA(.48),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
