import 'dart:ui';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../utils/word_share_service.dart';

/// High-resolution frosted glass card showcasing the Word of the Day, IPA
/// pronunciation, Uzbek translation, and daily practice count for social sharing.
class WordShareCard extends StatelessWidget {
  const WordShareCard({
    super.key,
    required this.word,
    this.style = WordShareStyle.indigoGlass,
    this.practicedCount = 0,
  });

  final PracticeWordDto word;
  final WordShareStyle style;
  final int practicedCount;

  static const double cardWidth = 360;
  static const double cardHeight = 450;

  String get _endingLetter {
    final clean = word.word.trim();
    if (clean.isEmpty) return '·';
    return clean.substring(clean.length - 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final accent = style.accent;
    final secondary = style.secondaryAccent;

    return Container(
      width: cardWidth,
      height: cardHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [style.backgroundStart, style.backgroundEnd],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: .14),
          width: 1.4,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -54,
            right: -42,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: .32),
                    accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -64,
            left: -48,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    secondary.withValues(alpha: .28),
                    secondary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withValues(alpha: .14)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .18),
                              border: Border.all(color: accent.withValues(alpha: .42)),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'WORD OF THE DAY',
                              style: WBText.mono(
                                size: 10,
                                weight: FontWeight.w700,
                                color: accent,
                                letterSpacing: .12,
                              ),
                            ),
                          ),
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .20),
                              border: Border.all(color: accent.withValues(alpha: .45)),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              _endingLetter,
                              style: WBText.mono(
                                size: 14,
                                weight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(flex: 2),
                      Text(
                        word.word,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WBText.grotesk(
                          size: 36,
                          weight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                      if (word.ipa.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          word.ipa,
                          style: WBText.mono(
                            size: 15,
                            weight: FontWeight.w500,
                            color: accent.withValues(alpha: .95),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        word.meaning,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: WBText.grotesk(
                          size: 16,
                          height: 1.48,
                          color: Colors.white.withValues(alpha: .84),
                        ),
                      ),
                      const Spacer(flex: 3),
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: .12),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [accent, secondary],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'W',
                              style: WBText.grotesk(
                                size: 13,
                                weight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Word Battle',
                              style: WBText.grotesk(
                                size: 13.5,
                                weight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: .92),
                              ),
                            ),
                          ),
                          if (practicedCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: WBColors.green.withValues(alpha: .18),
                                border: Border.all(color: WBColors.green.withValues(alpha: .45)),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                "+$practicedCount so'z",
                                style: WBText.mono(
                                  size: 10.5,
                                  weight: FontWeight.w700,
                                  color: WBColors.green,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
