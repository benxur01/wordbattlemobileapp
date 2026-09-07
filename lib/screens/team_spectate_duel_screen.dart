import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/chain_bubble.dart';
import '../widgets/primary_button.dart';
import '../widgets/progress_ring.dart';

/// A friend's live 2v2 duel, watched rather than played: [SpectateDuelScreen]
/// with four participants on it instead of two. Every value comes from the
/// server's `team_duel.spectate_state` frame — all four named by their roster
/// slot, and each word in the chain captioned with whoever said it, since a
/// spectator has no "mine" to tell the sides apart by. Nothing here can be
/// acted with: no word field, no chat, no reactions, exactly as the 1v1
/// spectate screen offers none.
class TeamSpectateDuelScreen extends StatelessWidget {
  const TeamSpectateDuelScreen({
    super.key,
    required this.state,
    required this.scrollController,
    required this.onBack,
  });

  /// Null only for the frame between the watched duel ending and landing back
  /// on the friends screen — see `SpectateDuelScreen.state` for the same gap.
  final TeamSpectateState? state;
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
              SizedBox(
                width: 104,
                child: Column(
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
                    _SpectatorBadge(
                      user: state.teamAOne,
                      words: state.teamAOneWords,
                      gradient: wbPurpleGradient,
                      textColor: WBColors.purpleText,
                      onTurn: state.teamAOneTurn,
                      alignEnd: false,
                    ),
                    const SizedBox(height: 8),
                    _SpectatorBadge(
                      user: state.teamATwo,
                      words: state.teamATwoWords,
                      gradient: wbTealGradient,
                      textColor: WBColors.tealText,
                      onTurn: state.teamATwoTurn,
                      alignEnd: false,
                    ),
                  ],
                ),
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
                        'KUZATISH · 2v2',
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
                      '${state.labelOf(state.turnPlayerId)} yozmoqda',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.grotesk(size: 11.5, weight: FontWeight.w600, color: WBColors.textA(.6)),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(height: 42),
                    _SpectatorBadge(
                      user: state.teamBOne,
                      words: state.teamBOneWords,
                      gradient: wbRoseGradient,
                      textColor: WBColors.roseText,
                      onTurn: state.teamBOneTurn,
                      alignEnd: true,
                    ),
                    const SizedBox(height: 8),
                    _SpectatorBadge(
                      user: state.teamBTwo,
                      words: state.teamBTwoWords,
                      gradient: wbAmber8Gradient,
                      textColor: WBColors.amber8Text,
                      onTurn: state.teamBTwoTurn,
                      alignEnd: true,
                    ),
                  ],
                ),
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
                  TeamChainBubble(
                    word: word.word,
                    // From a spectator's chair the two sides are only sides:
                    // team A takes the accent half, the way `playerOne` takes
                    // it on the watched 1v1 board.
                    side: state.isTeamA(word.playerId) ? TeamBubbleSide.mine : TeamBubbleSide.foe,
                    ms: word.spentLabel,
                    speakerLabel: state.labelOf(word.playerId),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                ],
              ),
              // On a line of its own rather than tacked onto the row above, as
              // `TeamDuelScreen` puts its own substitution note: the row is
              // already the widest thing on this screen.
              if (state.substitutedFrom != null) ...[
                const SizedBox(height: 7),
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

/// One participant's avatar, name and word count — `SpectateDuelScreen`'s own
/// badge at the size four of them fit in, the way `TeamDuelScreen` sizes its
/// header down for the same reason. [onTurn] rings the avatar the accent the
/// countdown uses, so whoever is about to answer is named twice.
class _SpectatorBadge extends StatelessWidget {
  const _SpectatorBadge({
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
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(10),
        border: onTurn ? Border.all(color: WBColors.accent, width: 2) : null,
      ),
      alignment: Alignment.center,
      child: Text(user.initial, style: WBText.grotesk(size: 12.5, weight: FontWeight.w700, color: textColor)),
    );

    final info = Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          user.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WBText.grotesk(size: 11, weight: FontWeight.w600),
        ),
        Text('$words so\'z', style: WBText.mono(size: 9.5, weight: FontWeight.w500, color: WBColors.textA(.45))),
      ],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: alignEnd
          ? [Flexible(child: info), const SizedBox(width: 6), avatar]
          : [avatar, const SizedBox(width: 6), Flexible(child: info)],
    );
  }
}

/// The chain's opening word, seeded by nobody — drawn centred and muted rather
/// than attributed to either team, mirroring `SpectateDuelScreen._SeedWordChip`.
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
