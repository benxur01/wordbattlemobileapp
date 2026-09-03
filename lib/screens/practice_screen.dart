import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/stroke_glyph.dart';

/// The practice screen: the server's word of the day, its meaning, and hints
/// on demand. The design left the input unwired and so does this — practice
/// duels are not a backend feature yet, so a text box that swallowed words
/// would be worse than none.
class PracticeScreen extends StatelessWidget {
  const PracticeScreen({
    super.key,
    required this.word,
    required this.hints,
    required this.onHint,
    required this.onBack,
  });

  /// Null while the request is in flight.
  final PracticeWordDto? word;
  final List<String> hints;
  final VoidCallback onHint;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
                onTap: onBack,
                borderRadius: BorderRadius.circular(12),
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
                  word == null ? '…' : '${word!.word.length}',
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
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.fromRGBO(124, 138, 255, .14), Color.fromRGBO(124, 138, 255, .04)],
                  ),
                  border: Border.all(color: WBColors.indigoA(.26)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 14),
              if (hints.isEmpty)
                Text(
                  "Bu so'z bilan boshlanadigan so'zlarni ko'rish uchun «?» tugmasini bosing",
                  style: WBText.grotesk(size: 13, height: 1.5, color: WBColors.textA(.5)),
                )
              else
                for (var i = 0; i < hints.length; i++) ...[
                  _hintBubble(hints[i], me: i.isOdd),
                  const SizedBox(height: 9),
                ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: WBColors.whiteA(.07))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text("So'z", style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5))),
                  const SizedBox(width: 7),
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
                      word == null ? '·' : word!.word.substring(word!.word.length - 1).toUpperCase(),
                      style: WBText.mono(size: 13, weight: FontWeight.w700, color: WBColors.indigoText),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'bilan boshlansin · maslahat olish mumkin',
                      style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: WBColors.whiteA(.05),
                        border: Border.all(color: WBColors.whiteA(.13)),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "so'zni yoz…",
                        style: WBText.grotesk(size: 18, weight: FontWeight.w600, color: WBColors.textA(.3)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Pressable(
                    onTap: onHint,
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: WBColors.whiteA(.06),
                        border: Border.all(color: WBColors.whiteA(.13)),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '?',
                        style: WBText.mono(size: 17, weight: FontWeight.w700, color: WBColors.textA(.7)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: wbIndigoGradient,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    alignment: Alignment.center,
                    child: const StrokeGlyph.chevronRight(
                      size: 14,
                      thickness: 3,
                      color: Color(0xFF0B0B16),
                      offset: Offset(-4, 0),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _hintBubble(String word, {required bool me}) {
    final head = word.substring(0, word.length - 1);
    final last = word.substring(word.length - 1);
    return _bubble(head, last, me: me);
  }

  static Widget _bubble(String head, String last, {required bool me}) {
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: me ? WBColors.accentA(.16) : WBColors.whiteA(.05),
          border: Border.all(color: me ? WBColors.accentA(.32) : WBColors.whiteA(.1)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(me ? 16 : 5),
            bottomRight: Radius.circular(me ? 5 : 16),
          ),
        ),
        child: RichText(
          text: TextSpan(
            style: WBText.grotesk(
              size: 17,
              weight: FontWeight.w600,
              color: me ? WBColors.text : WBColors.textA(.85),
            ),
            children: [
              TextSpan(text: head),
              TextSpan(
                text: last,
                style: const TextStyle(color: WBColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
