import 'package:flutter/material.dart';
import '../theme.dart';

/// One word in the duel chain, rendered as a chat bubble. Ports the two
/// `sc-if` branches (`w.me` / `w.bot`) from the duel screen template,
/// including the `wbRise` fade+slide-in entrance animation.
class ChainBubble extends StatefulWidget {
  const ChainBubble({super.key, required this.word, required this.isMe, required this.ms});

  final String word;
  final bool isMe;
  final String ms;

  @override
  State<ChainBubble> createState() => _ChainBubbleState();
}

class _ChainBubbleState extends State<ChainBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final head = widget.word.substring(0, widget.word.length - 1);
    final last = widget.word.substring(widget.word.length - 1);

    final bubble = Container(
      // design: max-width:74% of the chain column (412 − 2×20 padding)
      constraints: const BoxConstraints(maxWidth: 275),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: widget.isMe
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [WBColors.accentA(.22), WBColors.accentA(.1)],
              )
            : null,
        color: widget.isMe ? null : WBColors.whiteA(.05),
        border: Border.all(color: widget.isMe ? WBColors.accentA(.34) : WBColors.whiteA(.1)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isMe ? 18 : 6),
          bottomRight: Radius.circular(widget.isMe ? 6 : 18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          RichText(
            text: TextSpan(
              style: WBText.grotesk(
                size: 19,
                weight: FontWeight.w600,
                color: widget.isMe ? WBColors.text : WBColors.textA(.9),
                letterSpacing: .01,
              ),
              children: [
                TextSpan(text: head),
                TextSpan(text: last, style: const TextStyle(color: WBColors.accent)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(widget.ms, style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(widget.isMe ? .4 : .35))),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return Opacity(
          opacity: _c.value,
          child: Transform.translate(offset: Offset(0, 10 * (1 - _c.value)), child: child),
        );
      },
      child: Align(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      ),
    );
  }
}

/// Who said a word in a team duel's chain, relative to the player looking at
/// it — [ChainBubble]'s `mine`/opponent split, with the third side a 2v2 chain
/// needs.
enum TeamBubbleSide { mine, ally, foe }

/// One word in a team duel's chain, rendered as a chat bubble. Mirrors
/// [ChainBubble] — same shape, same `wbRise` entrance — with a third side
/// ([TeamBubbleSide.ally]) for a partner's word, and a small caption over
/// anyone's bubble but the player's own: a chain with four possible speakers
/// cannot rely on side alone to say who is talking, the way a 1v1 chain can.
class TeamChainBubble extends StatefulWidget {
  const TeamChainBubble({
    super.key,
    required this.word,
    required this.side,
    required this.ms,
    this.speakerLabel,
  });

  final String word;
  final TeamBubbleSide side;
  final String ms;

  /// Shown above the bubble for [TeamBubbleSide.ally] and [TeamBubbleSide.foe]
  /// — null for [TeamBubbleSide.mine], which needs no caption for the same
  /// reason [ChainBubble]'s own words never get one.
  final String? speakerLabel;

  @override
  State<TeamChainBubble> createState() => _TeamChainBubbleState();
}

class _TeamChainBubbleState extends State<TeamChainBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final head = word.substring(0, word.length - 1);
    final last = word.substring(word.length - 1);
    final onRight = widget.side != TeamBubbleSide.foe;

    final Color washTop;
    final Color washBottom;
    final Color border;
    final Color textColor;
    switch (widget.side) {
      case TeamBubbleSide.mine:
        washTop = WBColors.accentA(.22);
        washBottom = WBColors.accentA(.1);
        border = WBColors.accentA(.34);
        textColor = WBColors.text;
      case TeamBubbleSide.ally:
        washTop = WBColors.tealA(.24);
        washBottom = WBColors.tealA(.1);
        border = WBColors.tealA(.4);
        textColor = WBColors.text;
      case TeamBubbleSide.foe:
        washTop = WBColors.whiteA(.05);
        washBottom = WBColors.whiteA(.05);
        border = WBColors.whiteA(.1);
        textColor = WBColors.textA(.9);
    }

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 275),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [washTop, washBottom],
        ),
        border: Border.all(color: border),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(onRight ? 18 : 6),
          bottomRight: Radius.circular(onRight ? 6 : 18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          RichText(
            text: TextSpan(
              style: WBText.grotesk(size: 19, weight: FontWeight.w600, color: textColor, letterSpacing: .01),
              children: [
                TextSpan(text: head),
                TextSpan(text: last, style: const TextStyle(color: WBColors.accent)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(widget.ms, style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(onRight ? .4 : .35))),
        ],
      ),
    );

    final speakerLabel = widget.speakerLabel;
    final column = Column(
      crossAxisAlignment: onRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (speakerLabel != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              speakerLabel,
              style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.4)),
            ),
          ),
        ],
        bubble,
      ],
    );

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return Opacity(
          opacity: _c.value,
          child: Transform.translate(offset: Offset(0, 10 * (1 - _c.value)), child: child),
        );
      },
      child: Align(
        alignment: onRight ? Alignment.centerRight : Alignment.centerLeft,
        child: column,
      ),
    );
  }
}
