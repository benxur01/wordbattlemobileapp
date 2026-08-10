import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/chain_bubble.dart';
import '../widgets/flame_badge.dart';
import '../widgets/primary_button.dart';
import '../widgets/progress_ring.dart';
import '../widgets/stroke_glyph.dart';

/// The live duel. Every value here comes from the server's duel state — the
/// timer, whose turn it is, the chain and the required letter. The screen only
/// sends the typed word back.
class DuelScreen extends StatefulWidget {
  const DuelScreen({
    super.key,
    required this.duel,
    required this.me,
    required this.error,
    required this.scrollController,
    required this.onSubmit,
  });

  final DuelView? duel;
  final UserDto? me;

  /// Set by a `duel.rejected` frame: shown without losing the turn.
  final String error;
  final ScrollController scrollController;
  final ValueChanged<String> onSubmit;

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> {
  // Typing is the whole game loop, so the field holds focus for the entire
  // duel — including the seconds the opponent is answering in.
  //
  // It used to carry `enabled: duel.yourTurn`, which read well and cost the
  // player a second of every fifteen. A field that may no longer request focus
  // is unfocused by the framework the moment it is disabled, and Android takes
  // the keyboard down with the focus: every word sent closed the keyboard, and
  // the next one could not be typed until the field had been tapped again.
  // Swapping in `readOnly` does not help — that closes the input connection
  // too, so the keyboard flaps shut and open on every turn instead.
  //
  // So the field is simply never disabled while a duel is live. Whose turn it
  // is is said in words and colour — the turn pill, the hint, the border and
  // the dimmed send button — and [_submit] is what enforces it.
  final _focus = FocusNode();
  final _controller = TextEditingController();

  /// How much of the screen the keyboard covered at the last layout, so one
  /// coming back up can be told from one going away. See [didChangeDependencies].
  double _keyboardInset = 0;

  /// Keeps the newest word in view when the keyboard eats the chain.
  ///
  /// A keyboard sliding up takes about 380 design-pixels — six chain bubbles —
  /// out of the chain, because the canvas is laid out over the window minus its
  /// insets. Nothing re-anchors a `ListView` when its viewport shrinks: the
  /// offset stays exactly where it was and the newest words slide out of sight
  /// below the fold. That is how the opponent's answer went missing and had to
  /// be scrolled back to by hand — the auto-scroll in `AppRoot` had put it at
  /// the bottom correctly, and then the bottom moved.
  ///
  /// Only a player already at the newest word is followed down; one who has
  /// scrolled up to read the chain is left where they put themselves.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final rising = inset > _keyboardInset;
    _keyboardInset = inset;
    if (!rising) return;

    // This runs before the frame that applies the new size, so the position
    // still describes the viewport the player was looking at.
    final chain = widget.scrollController;
    if (!chain.hasClients || chain.position.extentAfter > 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !chain.hasClients) return;
      // Jumped rather than animated: the keyboard resizes the viewport frame by
      // frame, and an animation aimed at one of those frames lands on a bottom
      // that has moved by the time it arrives.
      chain.jumpTo(chain.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // Refusing the turn here, instead of by disabling the field, is what keeps
    // the keyboard up (see the note on [_focus]). The server refuses
    // out-of-turn words too; this stops the app from asking in the first place.
    if (widget.duel?.yourTurn != true) return;
    final word = _controller.text.trim();
    if (word.isEmpty) return;
    widget.onSubmit(word);
    _controller.clear();
    // Insurance for the one way focus can still be lost: the player dismissed
    // the keyboard themselves and then reached for the send button.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final duel = widget.duel;
    if (duel == null) {
      // Between leaving a duel and the next screen there is nothing to draw.
      return const SizedBox.shrink();
    }

    final pct = (duel.timeLeftMs / (duel.turnSeconds * 1000)).clamp(0.0, 1.0);
    final low = duel.secondsLeft <= 5;
    final ringColor = low ? WBColors.red : WBColors.amber;
    final timeText = duel.secondsLeft.ceil().toString().padLeft(2, '0');
    final turnLabel = duel.yourTurn ? 'SENING NAVBATING' : 'RAQIB YOZMOQDA';

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
                width: 112,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: wbPurpleGradient,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.me?.initial ?? '?',
                        style: WBText.grotesk(size: 16, weight: FontWeight.w700, color: WBColors.purpleText),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sen', style: WBText.grotesk(size: 13, weight: FontWeight.w600)),
                        Text(
                          '${widget.me?.rating ?? 0}',
                          style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.amber),
                        ),
                      ],
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
                width: 112,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            duel.opponent.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WBText.grotesk(size: 13, weight: FontWeight.w600),
                          ),
                          Text(
                            '${duel.opponent.rating}',
                            style: WBText.mono(
                              size: 11.5,
                              weight: FontWeight.w500,
                              color: WBColors.textA(.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: wbRoseGradient,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        duel.opponent.initial,
                        style: WBText.grotesk(size: 16, weight: FontWeight.w700, color: WBColors.roseText),
                      ),
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
              for (final word in duel.chain) ...[
                ChainBubble(word: word.word, isMe: word.mine, ms: word.spentLabel),
                const SizedBox(height: 10),
              ],
              if (duel.opponentThinking)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: WBColors.whiteA(.05),
                      border: Border.all(color: WBColors.whiteA(.1)),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                        bottomLeft: Radius.circular(6),
                      ),
                    ),
                    child: const _TypingDots(),
                  ),
                ),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text("So'z", style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5))),
                      const SizedBox(width: 7),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: WBColors.amberA(.16),
                          border: Border.all(color: WBColors.amberA(.4)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          duel.needLetter,
                          style: WBText.mono(size: 13, weight: FontWeight.w700, color: WBColors.amber),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text('bilan boshlansin', style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5))),
                    ],
                  ),
                  Row(
                    children: [
                      const FlameIcon(),
                      const SizedBox(width: 6),
                      Text(
                        '${duel.yourWords}',
                        style: WBText.mono(size: 13, weight: FontWeight.w700, color: WBColors.flameText),
                      ),
                    ],
                  ),
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
                        // The chain only accepts [a-z]; Android's auto-capitalisation
                        // and autocorrect would otherwise turn nearly every word into
                        // a rejected one.
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
                          hintText: duel.yourTurn ? "so'zni yoz…" : "raqib o'ylayapti…",
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
                          // The field is focused all duel long, so the amber
                          // ring can no longer mean "focused" — it means the
                          // turn is yours, which is the job `enabled:` used to
                          // do. There is no disabled border any more because
                          // there is no disabled state to draw.
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(19),
                            borderSide: BorderSide(
                              color: duel.yourTurn ? WBColors.amberA(.6) : WBColors.whiteA(.13),
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
                          gradient: wbAmberGradient,
                          borderRadius: BorderRadius.circular(19),
                          boxShadow: [
                            BoxShadow(
                              color: WBColors.amberA(.26),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const StrokeGlyph.chevronRight(
                          size: 15,
                          thickness: 3,
                          color: WBColors.amberInk,
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

/// Why the required letter is not the last letter of the last word.
///
/// The rule fires perhaps once in a few duels, which is exactly why it needs
/// saying: a player who meets it unannounced reads it as the server getting the
/// letter wrong. It sits under the letter chip it explains, one muted line, and
/// leaves with the turn — anything larger would be a banner about a detail.
class _SubstitutionNote extends StatelessWidget {
  const _SubstitutionNote({required this.skipped, required this.needLetter});

  /// The rare letter the chain skipped, and the one handed over instead.
  final String skipped;
  final String needLetter;

  @override
  Widget build(BuildContext context) {
    // Both letters are drawn like the amber chip above, so the eye connects
    // the sentence to the letter it is talking about.
    final letter = WBText.mono(size: 11.5, weight: FontWeight.w600, color: WBColors.amberA(.8));
    return Text.rich(
      TextSpan(
        style: WBText.grotesk(size: 11.5, color: WBColors.textA(.45)),
        children: [
          TextSpan(text: '«$skipped»', style: letter),
          const TextSpan(text: ' kam uchraydi — '),
          TextSpan(text: '«$needLetter»', style: letter),
          // "harfidan" rather than a case suffix hung off the quotes: it is
          // how the rejection message already talks about a letter.
          const TextSpan(text: ' harfidan davom et'),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = (_c.value + i * .15) % 1.0;
              final o = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
              return Opacity(
                opacity: o.clamp(0.0, 1.0),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: WBColors.textA(.5), shape: BoxShape.circle),
                ),
              );
            },
          ),
        );
      }),
    );
  }
}
