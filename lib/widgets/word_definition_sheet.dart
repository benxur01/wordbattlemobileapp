import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sound_effects.dart';
import '../theme.dart';
import '../utils/word_definition_service.dart';
import 'primary_button.dart';

/// Modal bottom sheet displaying dictionary definition, word class, syllables,
/// and usage examples for a word played in a duel or viewed in the app.
class WordDefinitionSheet extends StatefulWidget {
  const WordDefinitionSheet({
    super.key,
    required this.word,
    this.meaning,
    this.partOfSpeech,
    this.example,
    this.syllables,
    this.ipa,
  });

  final String word;
  final String? meaning;
  final String? partOfSpeech;
  final String? example;
  final String? syllables;
  final String? ipa;

  /// Opens [WordDefinitionSheet] as a frosted glass spring modal sheet.
  static Future<void> show(
    BuildContext context, {
    required String word,
    String? meaning,
    String? partOfSpeech,
    String? example,
    String? syllables,
    String? ipa,
  }) {
    HapticFeedback.lightImpact();
    SoundEffects.instance.playTap();

    final def = WordDefinitionService.getDefinition(word);

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => WordDefinitionSheet(
        word: word,
        meaning: meaning ?? def.meaning,
        partOfSpeech: partOfSpeech ?? def.partOfSpeech,
        example: example ?? def.example,
        syllables: syllables ?? def.syllables,
        ipa: ipa ?? def.ipa,
      ),
    );
  }

  @override
  State<WordDefinitionSheet> createState() => _WordDefinitionSheetState();
}

class _WordDefinitionSheetState extends State<WordDefinitionSheet> {
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  String get _normalizedWord => widget.word.trim().toUpperCase();

  int get _vowelCount {
    const vowels = 'AEIOU\u0410\u0415\u0418\u041E\u0423\u040E\u042D\u042E\u042F';
    int count = 0;
    for (final char in _normalizedWord.runes) {
      final s = String.fromCharCode(char);
      if (vowels.contains(s) || s == "O'" || s == "O’" || s == "G'") {
        count++;
      }
    }
    return count;
  }

  int get _consonantCount {
    final len = _normalizedWord.length;
    final v = _vowelCount;
    return (len - v) < 0 ? 0 : (len - v);
  }

  int get _wordScore {
    // Calculates scrabble-style score based on length and rare letters
    int score = _normalizedWord.length * 2;
    for (final char in _normalizedWord.runes) {
      final c = String.fromCharCode(char);
      if (c == 'F' || c == 'H' || c == 'J' || c == 'Q' || c == 'X' || c == 'V') {
        score += 3;
      }
    }
    return score;
  }

  Future<void> _copyWord() async {
    await Clipboard.setData(ClipboardData(text: _normalizedWord));
    HapticFeedback.selectionClick();
    SoundEffects.instance.playTap();
    if (mounted) {
      setState(() => _copied = true);
      _copyTimer?.cancel();
      _copyTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.85;

    final wordUpper = _normalizedWord;
    final def = WordDefinitionService.getDefinition(wordUpper);
    final effectiveMeaning = widget.meaning ?? def.meaning;
    final effectivePartOfSpeech = widget.partOfSpeech ?? def.partOfSpeech;
    final effectiveExample = widget.example ?? def.example;
    final effectiveSyllables = widget.syllables ?? def.syllables;
    final effectiveIpa = widget.ipa ?? def.ipa;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: const Color(0xFF131722).withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: WBColors.whiteA(.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 36,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: WBColors.whiteA(.24),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Top Bar with Tag and Close button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: WBColors.accentA(.14),
                        border: Border.all(color: WBColors.accentA(.32)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_rounded, size: 13, color: WBColors.accent),
                          const SizedBox(width: 5),
                          Text(
                            "SO'Z IZOHI",
                            style: WBText.mono(
                              size: 10.5,
                              weight: FontWeight.w700,
                              color: WBColors.accent,
                              letterSpacing: .12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Pressable(
                      onTap: () => Navigator.of(context).pop(),
                      pressScale: .92,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: WBColors.whiteA(.06),
                          border: Border.all(color: WBColors.whiteA(.12)),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '✕',
                          style: TextStyle(
                            fontSize: 13,
                            color: WBColors.textA(.65),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable Body
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Word Header & Badges Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: WBColors.whiteA(.045),
                          border: Border.all(color: WBColors.whiteA(.09)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        wordUpper,
                                        style: WBText.grotesk(
                                          size: 28,
                                          weight: FontWeight.w800,
                                          letterSpacing: .5,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        effectiveSyllables,
                                        style: WBText.mono(
                                          size: 13,
                                          weight: FontWeight.w500,
                                          color: WBColors.accent,
                                          letterSpacing: .3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Pressable(
                                  onTap: _copyWord,
                                  pressScale: .94,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _copied ? WBColors.greenA(.2) : WBColors.whiteA(.07),
                                      border: Border.all(
                                        color: _copied ? WBColors.greenA(.4) : WBColors.whiteA(.12),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                                          size: 13,
                                          color: _copied ? WBColors.green : WBColors.textA(.75),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          _copied ? 'Nusxa olindi' : 'Nusxa',
                                          style: WBText.grotesk(
                                            size: 11.5,
                                            weight: FontWeight.w600,
                                            color: _copied ? WBColors.green : WBColors.textA(.75),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Badges Row
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildBadge(
                                  label: effectivePartOfSpeech,
                                  color: WBColors.indigoText,
                                  bgColor: WBColors.indigoA(.18),
                                  borderColor: WBColors.indigoA(.35),
                                ),
                                _buildBadge(
                                  label: '${wordUpper.length} harf',
                                  color: WBColors.textA(.8),
                                  bgColor: WBColors.whiteA(.06),
                                  borderColor: WBColors.whiteA(.12),
                                ),
                                _buildBadge(
                                  label: '+$_wordScore ball',
                                  color: WBColors.green,
                                  bgColor: WBColors.greenA(.14),
                                  borderColor: WBColors.greenA(.3),
                                ),
                                if (effectiveIpa != null && effectiveIpa.isNotEmpty)
                                  _buildBadge(
                                    label: effectiveIpa,
                                    color: WBColors.textA(.65),
                                    bgColor: WBColors.whiteA(.05),
                                    borderColor: WBColors.whiteA(.1),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Meaning Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: WBColors.whiteA(.04),
                          border: Border.all(color: WBColors.whiteA(.08)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 14, color: WBColors.accent),
                                const SizedBox(width: 7),
                                Text(
                                  "MA'NOSI",
                                  style: WBText.mono(
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color: WBColors.textA(.5),
                                    letterSpacing: .12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              effectiveMeaning,
                              style: WBText.grotesk(
                                size: 15,
                                height: 1.55,
                                weight: FontWeight.w400,
                                color: WBColors.textA(.92),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Example Sentence Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: WBColors.whiteA(.035),
                          border: Border.all(color: WBColors.whiteA(.07)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.format_quote_rounded, size: 15, color: WBColors.green),
                                const SizedBox(width: 6),
                                Text(
                                  "MISOL VA QO'LLANISHI",
                                  style: WBText.mono(
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color: WBColors.textA(.5),
                                    letterSpacing: .12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            Text(
                              effectiveExample,
                              style: WBText.grotesk(
                                size: 14,
                                height: 1.5,
                                color: WBColors.textA(.75),
                              ).copyWith(fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Word Statistics Bar
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: WBColors.whiteA(.025),
                          border: Border.all(color: WBColors.whiteA(.06)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildMiniStat(
                              label: 'Bosh / Oxir',
                              value: '${wordUpper[0]} → ${wordUpper[wordUpper.length - 1]}',
                            ),
                            Container(width: 1, height: 26, color: WBColors.whiteA(.08)),
                            _buildMiniStat(
                              label: 'Unlilar',
                              value: '$_vowelCount ta',
                            ),
                            Container(width: 1, height: 26, color: WBColors.whiteA(.08)),
                            _buildMiniStat(
                              label: 'Undoshlar',
                              value: '$_consonantCount ta',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      // Action Button
                      Pressable(
                        onTap: () {
                          SoundEffects.instance.playTap();
                          Navigator.of(context).pop();
                        },
                        pressScale: .98,
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: wbAccentGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: WBColors.accentA(.2),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Tushunarli',
                            style: WBText.grotesk(
                              size: 16,
                              weight: FontWeight.w700,
                              color: WBColors.accentInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: WBText.mono(
          size: 11,
          weight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMiniStat({required String label, required String value}) {
    return Column(
      children: [
        Text(
          value,
          style: WBText.mono(
            size: 13.5,
            weight: FontWeight.w700,
            color: WBColors.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: WBText.grotesk(
            size: 10.5,
            color: WBColors.textA(.45),
          ),
        ),
      ],
    );
  }
}
