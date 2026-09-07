import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/chain_bubble.dart';
import '../widgets/flame_badge.dart';
import '../widgets/primary_button.dart';
import '../widgets/progress_ring.dart';

/// A friend's live duel, watched rather than played: the read-only sibling of
/// `DuelScreen`. Every value here comes from the server's own
/// `duel.spectate_state` frame — both players named outright, not split into
/// "mine"/"opponent" — and there is nothing on this screen a spectator could
/// act with: no word field, no chat, no reactions. The backend already
/// refuses all three from a spectator; the point of leaving them off is that
/// the UI never offers what would only ever come back rejected.
class SpectateDuelScreen extends StatelessWidget {
  const SpectateDuelScreen({
    super.key,
    required this.state,
    required this.scrollController,
    required this.onBack,
  });

  /// Null only for the frame between the watched duel ending and landing back
  /// on the friends screen — see `DuelScreen.duel` for the same gap.
  final SpectateState? state;
  final ScrollController scrollController;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final state = this.state;
    if (state == null) return const SizedBox.shrink();

    final pct = (state.timeLeftMs / (state.turnSeconds * 1000)).clamp(0.0, 1.0);
    final low = state.secondsLeft <= 5;
    final ringColor = low ? WBColors.red : WBColors.accent;
    final timeText = state.secondsLeft.ceil().toString().padLeft(2, '0');
    final turnPlayer = state.playerOneTurn ? state.playerOne : state.playerTwo;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: WBColors.whiteA(.07))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Pressable(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: WBColors.whiteA(.05),
                        border: Border.all(color: WBColors.whiteA(.1)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.arrow_back_ios_new, size: 13, color: WBColors.textA(.7)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PlayerBadge(
                    user: state.playerOne,
                    words: state.playerOneWords,
                    gradient: wbPurpleGradient,
                    textColor: WBColors.purpleText,
                    onTurn: state.playerOneTurn,
                    alignEnd: false,
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: WBColors.whiteA(.06),
                        border: Border.all(color: WBColors.whiteA(.1)),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'KUZATISH',
                        style: WBText.mono(
                          size: 9,
                          weight: FontWeight.w500,
                          color: WBColors.textA(.6),
                          letterSpacing: .12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 92,
                      height: 92,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ProgressRing(
                            progress: pct,
                            color: ringColor,
                            trackColor: WBColors.whiteA(.09),
                            strokeWidth: 7,
                          ),
                          Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(color: WBColors.bgPanel, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text(
                              timeText,
                              style: WBText.mono(
                                size: 30,
                                weight: FontWeight.w700,
                                color: low ? WBColors.red : WBColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${turnPlayer.label} yozmoqda',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.grotesk(size: 11.5, weight: FontWeight.w600, color: WBColors.textA(.6)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(height: 42),
                  _PlayerBadge(
                    user: state.playerTwo,
                    words: state.playerTwoWords,
                    gradient: wbRoseGradient,
                    textColor: WBColors.roseText,
                    onTurn: !state.playerOneTurn,
                    alignEnd: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            children: [
              for (final word in state.chain) ...[
                if (word.isSeed)
                  _SeedWordChip(word: word.word)
                else
                  ChainBubble(
                    word: word.word,
                    isMe: word.playerId == state.playerOne.id,
                    ms: word.spentLabel,
                  ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          decoration: BoxDecoration(
            color: WBColors.bg.withValues(alpha: .9),
            border: Border(top: BorderSide(color: WBColors.whiteA(.07))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("So'z", style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5))),
              const SizedBox(width: 7),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: WBColors.accentA(.16),
                  border: Border.all(color: WBColors.accentA(.4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  state.needLetter,
                  style: WBText.mono(size: 13, weight: FontWeight.w700, color: WBColors.accent),
                ),
              ),
              const SizedBox(width: 7),
              Text('bilan boshlansin', style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5))),
              if (state.substitutedFrom != null) ...[
                const SizedBox(width: 10),
                Text(
                  '(«${state.substitutedFrom}» o\'rniga)',
                  style: WBText.grotesk(size: 11.5, color: WBColors.textA(.45)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One side's avatar, name and word count — [onTurn] rings the avatar the
/// same accent the countdown uses, so whoever is about to answer is named
/// twice: once in the pill under the clock, once here.
class _PlayerBadge extends StatelessWidget {
  const _PlayerBadge({
    required this.user,
    required this.words,
    required this.gradient,
    required this.textColor,
    required this.onTurn,
    required this.alignEnd,
  });

  final UserDto user;
  final int words;
  final Gradient gradient;
  final Color textColor;
  final bool onTurn;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(13),
        border: onTurn ? Border.all(color: WBColors.accent, width: 2) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        user.initial,
        style: WBText.grotesk(size: 16, weight: FontWeight.w700, color: textColor),
      ),
    );

    final label = Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          user.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WBText.grotesk(size: 13, weight: FontWeight.w600),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: alignEnd
              ? [
                  Text('$words', style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.flameText)),
                  const SizedBox(width: 4),
                  FlameIcon(width: 7, height: 9),
                ]
              : [
                  FlameIcon(width: 7, height: 9),
                  const SizedBox(width: 4),
                  Text('$words', style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.flameText)),
                ],
        ),
      ],
    );

    return SizedBox(
      width: 96,
      child: Row(
        mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: alignEnd
            ? [Flexible(child: label), const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), Flexible(child: label)],
      ),
    );
  }
}

/// The chain's opening word, seeded by nobody — drawn centred and muted
/// rather than attributed to either side, unlike every [ChainBubble] after it.
class _SeedWordChip extends StatelessWidget {
  const _SeedWordChip({required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: WBColors.whiteA(.04),
          border: Border.all(color: WBColors.whiteA(.09)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          word,
          style: WBText.grotesk(size: 16, weight: FontWeight.w600, color: WBColors.textA(.6)),
        ),
      ),
    );
  }
}
