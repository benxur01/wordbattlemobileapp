import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/practice_test_input.dart';
import '../widgets/primary_button.dart';
import '../widgets/stroke_glyph.dart';

/// The practice screen: the server's word of the day, its meaning, hints on
/// demand, and an interactive test input field with real-time soft glow
/// validation and elastic shake feedback on invalid input.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    required this.word,
    required this.hints,
    required this.onHint,
    required this.onBack,
    this.onCheckWord,
  });

  /// Null while the request is in flight.
  final PracticeWordDto? word;
  final List<String> hints;
  final VoidCallback onHint;
  final VoidCallback onBack;

  /// Optional async dictionary check against the server.
  final Future<PracticeCheckDto> Function(String word)? onCheckWord;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final GlobalKey<PracticeTestInputState> _inputKey = GlobalKey<PracticeTestInputState>();
  final List<String> _testedWords = [];

  @override
  void didUpdateWidget(covariant PracticeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word?.word != widget.word?.word) {
      _testedWords.clear();
      _inputKey.currentState?.resetInput();
    }
  }

  String? get _needLetter {
    final raw = widget.word?.word;
    if (raw == null || raw.isEmpty) return null;
    return raw.substring(raw.length - 1).toLowerCase();
  }

  void _onAcceptedWord(String word) {
    setState(() {
      if (!_testedWords.contains(word)) {
        _testedWords.insert(0, word);
      }
    });
  }

  void _clearTestedWords() {
    setState(() => _testedWords.clear());
  }

  int get _totalTestedCharacters => _testedWords.fold(0, (sum, w) => sum + w.length);

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final needUpper = _needLetter?.toUpperCase() ?? '·';

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: WBColors.whiteA(.07))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Pressable(
                onTap: widget.onBack,
                borderRadius: BorderRadius.circular(12),
                semanticLabel: 'Orqaga',
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: WBColors.whiteA(.05),
                    border: Border.all(color: WBColors.whiteA(.1)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: StrokeGlyph.chevronLeft(
                    size: 11,
                    thickness: 2,
                    color: WBColors.textA(.8),
                    offset: const Offset(2, 0),
                  ),
                ),
              ),
              Column(
                children: [
                  Text('Mashq rejimi', style: WBText.grotesk(size: 15, weight: FontWeight.w600)),
                  Text(
                    'REYTINGSIZ · TAYMERSIZ',
                    style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(.4)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: WBColors.indigoA(.11),
                  border: Border.all(color: WBColors.indigoA(.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  word == null ? '…' : '${word.word.length}',
                  style: WBText.mono(size: 13, weight: FontWeight.w700, color: WBColors.indigoText),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [WBColors.indigoA(.14), WBColors.indigoA(.04)],
                  ),
                  border: Border.all(color: WBColors.indigoA(.26)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "YANGI SO'Z",
                          style: WBText.mono(
                            size: 10,
                            weight: FontWeight.w500,
                            color: WBColors.indigoText.withValues(alpha: .85),
                            letterSpacing: .14,
                          ),
                        ),
                        if (word != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: WBColors.indigoA(.16),
                              border: Border.all(color: WBColors.indigoA(.32)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'OXIRGI HARF: $needUpper',
                              style: WBText.mono(
                                size: 9.5,
                                weight: FontWeight.w700,
                                color: WBColors.indigoText,
                                letterSpacing: .08,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            word?.word ?? '…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WBText.grotesk(size: 27, weight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Text(word?.ipa ?? '', style: WBText.mono(size: 13, color: WBColors.textA(.45))),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      word?.meaning ?? '',
                      style: WBText.grotesk(size: 14.5, height: 1.5, color: WBColors.textA(.72)),
                    ),
                  ],
                ),
              ),
              if (_testedWords.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      "SINALGAN SO'ZLAR",
                      style: WBText.mono(
                        size: 10,
                        weight: FontWeight.w600,
                        color: WBColors.green,
                        letterSpacing: .12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: WBColors.greenA(.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_testedWords.length} · +$_totalTestedCharacters harf',
                        style: WBText.mono(size: 10.5, weight: FontWeight.w700, color: WBColors.green),
                      ),
                    ),
                    const Spacer(),
                    Pressable(
                      onTap: _clearTestedWords,
                      pressScale: .94,
                      borderRadius: BorderRadius.circular(8),
                      semanticLabel: "Sinalgan so'zlarni tozalash",
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          'Tozalash',
                          style: WBText.grotesk(
                            size: 11.5,
                            weight: FontWeight.w500,
                            color: WBColors.textA(.45),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final tested in _testedWords) _testedChip(tested)],
                ),
              ],
              const SizedBox(height: 16),
              if (widget.hints.isEmpty)
                Text(
                  "Bu so'z bilan boshlanadigan so'zlarni ko'rish uchun «?» tugmasini bosing",
                  style: WBText.grotesk(size: 13, height: 1.5, color: WBColors.textA(.5)),
                )
              else ...[
                Text(
                  "MASLAHAT SO'ZLAR",
                  style: WBText.mono(
                    size: 10,
                    weight: FontWeight.w500,
                    color: WBColors.textA(.45),
                    letterSpacing: .12,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [for (final hint in widget.hints) _hintChip(hint)],
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          decoration: BoxDecoration(
            color: WBColors.bg.withValues(alpha: .94),
            border: Border(top: BorderSide(color: WBColors.whiteA(.07))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: WBColors.indigoA(.16),
                      border: Border.all(color: WBColors.indigoA(.4)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      needUpper,
                      style: WBText.mono(size: 13, weight: FontWeight.w700, color: WBColors.indigoText),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      "harfi bilan boshlanadigan so'zlar",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: widget.onHint,
                    pressScale: .95,
                    borderRadius: BorderRadius.circular(11),
                    semanticLabel: "Maslahat so'zlarni olish",
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: wbIndigoGradient,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: WBColors.indigo.withValues(alpha: .22),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '?',
                            style: WBText.mono(size: 12.5, weight: FontWeight.w700, color: WBColors.indigoInk),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Maslahat',
                            style: WBText.grotesk(size: 12, weight: FontWeight.w600, color: WBColors.indigoInk),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PracticeTestInput(
                key: _inputKey,
                needLetter: _needLetter,
                triedWords: _testedWords.toSet(),
                enabled: word != null,
                onCheckWord: widget.onCheckWord,
                onAcceptedWord: _onAcceptedWord,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _testedChip(String word) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('tested_$word'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.86 + (0.14 * value),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: WBColors.greenA(.10),
          border: Border.all(color: WBColors.green.withValues(alpha: .42)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 14, color: WBColors.green),
            const SizedBox(width: 6),
            Text(
              word,
              style: WBText.grotesk(size: 15, weight: FontWeight.w600, color: WBColors.text),
            ),
            const SizedBox(width: 6),
            Text(
              '${word.length}',
              style: WBText.mono(size: 11, weight: FontWeight.w600, color: WBColors.green),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintChip(String word) {
    final head = word.substring(0, word.length - 1);
    final last = word.substring(word.length - 1);
    return Pressable(
      onTap: () => _inputKey.currentState?.fillWord(word),
      pressScale: .96,
      borderRadius: BorderRadius.circular(14),
      semanticLabel: "$word so'zini sinov maydoniga kiritish",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: WBColors.whiteA(.05),
          border: Border.all(color: WBColors.whiteA(.1)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: RichText(
          text: TextSpan(
            style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: WBColors.textA(.85)),
            children: [
              TextSpan(text: head),
              TextSpan(
                text: last,
                style: TextStyle(color: WBColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
