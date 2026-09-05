import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/chain_bubble.dart';
import '../widgets/primary_button.dart';
import '../widgets/progress_ring.dart';
import '../widgets/stroke_glyph.dart';

/// The live 2v2 duel board — [DuelScreen]'s team sibling: the same chain,
/// timer ring and word field, with a four-participant header instead of one
/// opponent and a chain that has to say *which* of the four spoke each word.
/// No chat, no reactions — the backend does not carry either for a team duel.
class TeamDuelScreen extends StatefulWidget {
  const TeamDuelScreen({
    super.key,
    required this.duel,
    required this.me,
    required this.error,
    required this.scrollController,
    required this.onSubmit,
  });

  final TeamDuelView? duel;
  final UserDto? me;

  /// Set by a `team_duel.rejected` frame: shown without losing the turn.
  final String error;
  final ScrollController scrollController;
  final ValueChanged<String> onSubmit;

  @override
  State<TeamDuelScreen> createState() => _TeamDuelScreenState();
}

class _TeamDuelScreenState extends State<TeamDuelScreen> {
  // Held for the whole duel, same as `DuelScreen._focus` — see its own note
  // for why disabling the field on a turn that is not this player's would
  // take the keyboard down with it.
  final _focus = FocusNode();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.duel?.yourTurn != true) return;
    final word = _controller.text.trim();
    if (word.isEmpty) return;
    widget.onSubmit(word);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final duel = widget.duel;
    if (duel == null) {
      // Between leaving a team duel and the next screen there is nothing to
      // draw — see `DuelScreen.build` for the same gap.
      return const SizedBox.shrink();
    }

    final pct = (duel.timeLeftMs / (duel.turnSeconds * 1000)).clamp(0.0, 1.0);
    final low = duel.secondsLeft <= 5;
    final ringColor = low ? WBColors.red : WBColors.accent;
    final timeText = duel.secondsLeft.ceil().toString().padLeft(2, '0');
    final turnLabel = duel.yourTurn
        ? 'SENING NAVBATING'
        : duel.partnerTurn
            ? 'SHERIGING NAVBATI'
            : 'RAQIB YOZMOQDA';

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
                    _TeamMiniBadge(
                      initial: widget.me?.initial ?? '?',
                      label: 'Sen',
                      words: duel.yourWords,
                      gradient: wbPurpleGradient,
                      textColor: WBColors.purpleText,
                      onTurn: duel.yourTurn,
                      alignEnd: false,
                    ),
                    const SizedBox(height: 8),
                    _TeamMiniBadge(
                      initial: duel.partner.initial,
                      label: duel.partner.label,
                      words: duel.partnerWords,
                      gradient: wbTealGradient,
                      textColor: WBColors.tealText,
                      onTurn: duel.partnerTurn,
                      alignEnd: false,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
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
                            decoration: const BoxDecoration(color: WBColors.bgPanel, shape: BoxShape.circle),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: WBColors.whiteA(.06),
                        border: Border.all(color: WBColors.whiteA(.1)),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        turnLabel,
                        style: WBText.mono(
                          size: 9,
                          weight: FontWeight.w500,
                          color: WBColors.textA(.6),
                          letterSpacing: .12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _TeamMiniBadge(
                      initial: duel.opponentOne.initial,
                      label: duel.opponentOne.label,
                      words: duel.opponentOneWords,
                      gradient: wbRoseGradient,
                      textColor: WBColors.roseText,
                      onTurn: duel.opponentOneTurn,
                      alignEnd: true,
                    ),
                    const SizedBox(height: 8),
                    _TeamMiniBadge(
                      initial: duel.opponentTwo.initial,
                      label: duel.opponentTwo.label,
                      words: duel.opponentTwoWords,
                      gradient: wbAmber8Gradient,
                      textColor: WBColors.amber8Text,
                      onTurn: duel.opponentTwoTurn,
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
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            children: [
              if (duel.seedWord.isNotEmpty) ...[
                _SeedWordChip(word: duel.seedWord),
                const SizedBox(height: 10),
              ],
              for (final word in duel.chain) ...[
                TeamChainBubble(
                  word: word.word,
                  side: word.mine
                      ? TeamBubbleSide.mine
                      : word.ally
                          ? TeamBubbleSide.ally
                          : TeamBubbleSide.foe,
                  ms: word.spentLabel,
                  speakerLabel: word.mine
                      ? null
                      : word.ally
                          ? duel.partner.label
                          : (word.playerId == duel.opponentOne.id ? duel.opponentOne.label : duel.opponentTwo.label),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      duel.needLetter,
                      style: WBText.mono(size: 13, weight: FontWeight.w700, color: WBColors.accent),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text('bilan boshlansin', style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5))),
                ],
              ),
              if (duel.substitutedFrom != null) ...[
                const SizedBox(height: 7),
                _SubstitutionNote(skipped: duel.substitutedFrom!, needLetter: duel.needLetter),
              ],
              if (widget.error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: WBColors.redA(.12),
                    border: Border.all(color: WBColors.redA(.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.error,
                    style: WBText.grotesk(size: 12.5, weight: FontWeight.w500, color: WBColors.redSoft),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        autofocus: true,
                        onSubmitted: (_) => _submit(),
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [],
                        textInputAction: TextInputAction.send,
                        style: WBText.grotesk(size: 19, weight: FontWeight.w600),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: WBColors.whiteA(.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                          hintText: duel.yourTurn ? "so'zni yoz…" : "navbat kutilmoqda…",
                          hintStyle: WBText.grotesk(
                            size: 19,
                            weight: FontWeight.w600,
                            color: WBColors.textA(.3),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(19),
                            borderSide: BorderSide(color: WBColors.whiteA(.13)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(19),
                            borderSide: BorderSide(color: WBColors.whiteA(.13)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(19),
                            borderSide: BorderSide(
                              color: duel.yourTurn ? WBColors.accentA(.6) : WBColors.whiteA(.13),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Pressable(
                    onTap: duel.yourTurn ? _submit : null,
                    pressScale: .95,
                    child: Opacity(
                      opacity: duel.yourTurn ? 1 : .45,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: wbAccentGradient,
                          borderRadius: BorderRadius.circular(19),
                          boxShadow: [
                            BoxShadow(
                              color: WBColors.accentA(.26),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const StrokeGlyph.chevronRight(
                          size: 15,
                          thickness: 3,
                          color: WBColors.accentInk,
                          offset: Offset(-4, 0),
                        ),
                      ),
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
}

/// One side's avatar, name and word count, sized for four participants where
/// [DuelScreen]'s own header only ever has two. Mirrors
/// `SpectateDuelScreen._PlayerBadge`, smaller and always paired with a second
/// one stacked below it.
class _TeamMiniBadge extends StatelessWidget {
  const _TeamMiniBadge({
    required this.initial,
    required this.label,
    required this.words,
    required this.gradient,
    required this.textColor,
    required this.onTurn,
    required this.alignEnd,
  });

  final String initial;
  final String label;
  final int words;
  final Gradient gradient;
  final Color textColor;

  /// Rings the avatar the same accent the countdown uses, naming whoever is
  /// about to answer a second time — once here, once in the turn pill.
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
      child: Text(initial, style: WBText.grotesk(size: 12.5, weight: FontWeight.w700, color: textColor)),
    );

    final info = Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
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

/// The chain's opening word — mirrors `SpectateDuelScreen._SeedWordChip`,
/// drawn centred and muted rather than attributed to any of the four.
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

/// Why the required letter is not the last letter of the last word — mirrors
/// `DuelScreen._SubstitutionNote` exactly.
class _SubstitutionNote extends StatelessWidget {
  const _SubstitutionNote({required this.skipped, required this.needLetter});

  final String skipped;
  final String needLetter;

  @override
  Widget build(BuildContext context) {
    final letter = WBText.mono(size: 11.5, weight: FontWeight.w600, color: WBColors.accentA(.8));
    return Text.rich(
      TextSpan(
        style: WBText.grotesk(size: 11.5, color: WBColors.textA(.45)),
        children: [
          TextSpan(text: '«$skipped»', style: letter),
          const TextSpan(text: ' kam uchraydi — '),
          TextSpan(text: '«$needLetter»', style: letter),
          const TextSpan(text: ' harfidan davom et'),
        ],
      ),
    );
  }
}
