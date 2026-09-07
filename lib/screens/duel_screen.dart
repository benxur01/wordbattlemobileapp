import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/chain_bubble.dart';
import '../widgets/flame_badge.dart';
import '../widgets/primary_button.dart';
import '../widgets/progress_ring.dart';
import '../widgets/provisional_badge.dart';
import '../widgets/stroke_glyph.dart';

/// The emoji a player can react with — fixed, same set the server accepts.
const List<String> kDuelReactions = ['🔥', '😂', '👏', '😮', '🤝', '😢'];

/// The live duel. Every value here comes from the server's duel state — the
/// timer, whose turn it is, the chain and the required letter. The screen only
/// sends the typed word back, plus whatever chat or reaction the player sends.
class DuelScreen extends StatefulWidget {
  const DuelScreen({
    super.key,
    required this.duel,
    required this.me,
    required this.error,
    required this.scrollController,
    required this.onSubmit,
    required this.chatLog,
    required this.onSendChat,
    required this.onSendReaction,
    required this.reaction,
    required this.powerUps,
    required this.onPowerUp,
    required this.onLeave,
  });

  final DuelView? duel;
  final UserDto? me;

  /// Set by a `duel.rejected` frame: shown without losing the turn.
  final String error;
  final ScrollController scrollController;
  final ValueChanged<String> onSubmit;

  /// This duel's chat, oldest first. Never persisted — it exists only as
  /// long as the duel and this screen do.
  final List<DuelChatMessage> chatLog;
  final ValueChanged<String> onSendChat;
  final ValueChanged<String> onSendReaction;

  /// The opponent's latest reaction, or null once none is showing. A new
  /// value (even the same emoji again) replays the float-and-fade animation —
  /// see [DuelReaction.id].
  final DuelReaction? reaction;

  /// What is left of the four power-ups, and the words the hint last offered.
  /// Only ever anything but empty in a duel against the bot, which is the only
  /// duel that draws the row at all.
  final DuelPowerUps powerUps;
  final ValueChanged<DuelPowerUp> onPowerUp;

  /// The exit button in [_SocialBar]. Walking out of a duel is a forfeit, so
  /// this only asks to leave — `AppRoot` puts the question and acts on the
  /// answer, the same way it does for the Android back gesture.
  final VoidCallback onLeave;

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

  bool _chatOpen = false;
  final _chatFocus = FocusNode();
  final _chatController = TextEditingController();
  final _chatScroll = ScrollController();

  /// The reaction currently on screen, and where its fade animation has got
  /// to. Both go back to nothing a couple of seconds after they are set — see
  /// [didUpdateWidget].
  DuelReaction? _shownReaction;
  bool _reactionVisible = false;
  Timer? _reactionFadeTimer;
  Timer? _reactionGoneTimer;

  @override
  void didUpdateWidget(DuelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final reaction = widget.reaction;
    if (reaction != null && reaction.id != oldWidget.reaction?.id) {
      _reactionFadeTimer?.cancel();
      _reactionGoneTimer?.cancel();
      setState(() {
        _shownReaction = reaction;
        _reactionVisible = true;
      });
      _reactionFadeTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _reactionVisible = false);
      });
      _reactionGoneTimer = Timer(const Duration(milliseconds: 2000), () {
        if (mounted) setState(() => _shownReaction = null);
      });
    }

    if (_chatOpen && widget.chatLog.length != oldWidget.chatLog.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_chatScroll.hasClients) return;
        _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
      });
    }
  }

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
    _chatFocus.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    _reactionFadeTimer?.cancel();
    _reactionGoneTimer?.cancel();
    super.dispose();
  }

  void _sendChat() {
    final text = _chatController.text;
    // A blank message never leaves the phone — the server would refuse it
    // too, but there is no reason to make a round trip for that.
    if (text.trim().isEmpty) return;
    widget.onSendChat(text);
    _chatController.clear();
    _chatFocus.requestFocus();
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
    final ringColor = low ? WBColors.red : WBColors.accent;
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.me?.rating ?? 0}',
                              style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.accent),
                            ),
                            if (widget.me?.provisional ?? false) ...[
                              const SizedBox(width: 5),
                              ProvisionalBadge(size: 8),
                            ],
                          ],
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
                    // Under the turn pill, and only in a themed duel: without
                    // it a player whose perfectly good word is refused has
                    // nothing on screen to tell them why.
                    if (duel.theme != null) ...[
                      const SizedBox(height: 5),
                      _ThemePill(name: duel.theme!),
                    ],
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (duel.opponent.provisional) ...[
                                ProvisionalBadge(size: 8),
                                const SizedBox(width: 5),
                              ],
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
        _SocialBar(
          chatOpen: _chatOpen,
          onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
          onReact: widget.onSendReaction,
          onLeave: widget.onLeave,
        ),
        if (_chatOpen)
          _ChatPanel(
            messages: widget.chatLog,
            scrollController: _chatScroll,
            textController: _chatController,
            focusNode: _chatFocus,
            onSend: _sendChat,
          ),
        Expanded(
          child: Stack(
            children: [
              ListView(
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
                        child: _TypingDots(),
                      ),
                    ),
                ],
              ),
              // The opponent's side of the board — see [ChainBubble], which
              // aligns their words the same way.
              if (_shownReaction != null)
                Positioned(
                  top: 8,
                  left: 12,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _reactionVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: _ReactionBubble(emoji: _shownReaction!.emoji),
                    ),
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
                  Row(
                    children: [
                      FlameIcon(),
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
                _SubstitutionNote(
                  skipped: duel.substitutedFrom!,
                  needLetter: duel.needLetter,
                  byPowerUp: duel.substitutionReason == 'power_up',
                ),
              ],
              // Bot practice only. `rated` is the server's own `!botOpponent`,
              // the same flag the ratings on this screen are drawn from, and
              // the server refuses every one of these frames in a duel with a
              // person on the other side of it.
              if (!duel.rated) ...[
                const SizedBox(height: 10),
                _PowerUpBar(
                  powerUps: widget.powerUps,
                  yourTurn: duel.yourTurn,
                  onUse: widget.onPowerUp,
                ),
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
                        child: StrokeGlyph.chevronRight(
                          size: 15,
                          thickness: 3,
                          color: WBColors.accentInk,
                          offset: const Offset(-4, 0),
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

/// The way out of the duel, the quick-reaction row and the chat toggle, in one
/// slim strip so none of them crowds the board above or the word field below.
class _SocialBar extends StatelessWidget {
  const _SocialBar({
    required this.chatOpen,
    required this.onToggleChat,
    required this.onReact,
    required this.onLeave,
  });

  final bool chatOpen;
  final VoidCallback onToggleChat;
  final ValueChanged<String> onReact;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: WBColors.whiteA(.07))),
      ),
      child: Row(
        children: [
          _LeaveButton(onTap: onLeave),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                for (final emoji in kDuelReactions) ...[
                  Pressable(
                    // Sends immediately — a reaction is not worth a confirmation.
                    onTap: () => onReact(emoji),
                    pressScale: .95,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: WBColors.whiteA(.05),
                        border: Border.all(color: WBColors.whiteA(.1)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Pressable(
            onTap: onToggleChat,
            pressScale: .95,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: chatOpen ? WBColors.accentA(.16) : WBColors.whiteA(.05),
                border: Border.all(color: chatOpen ? WBColors.accentA(.4) : WBColors.whiteA(.1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: chatOpen ? WBColors.accent : WBColors.textA(.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The board's own way out. Android's back gesture does the same thing, but
/// iOS has no gesture to intercept and this screen is not a page route, so
/// without this button a player there is stuck on the board until the duel
/// ends. Tinted red because the tap forfeits, which [DuelScreen.onLeave] asks
/// about before it happens.
class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressScale: .95,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: WBColors.redA(.1),
          border: Border.all(color: WBColors.redA(.28)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: StrokeGlyph.chevronLeft(
          size: 9,
          thickness: 2,
          color: WBColors.redSoft,
          offset: const Offset(2, 0),
        ),
      ),
    );
  }
}

/// The chat log for the duel now live, plus the field that adds to it. Opens
/// under [_SocialBar] and disappears with the duel — nothing here is ever
/// saved.
class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.messages,
    required this.scrollController,
    required this.textController,
    required this.focusNode,
    required this.onSend,
  });

  final List<DuelChatMessage> messages;
  final ScrollController scrollController;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.02),
        border: Border(bottom: BorderSide(color: WBColors.whiteA(.07))),
      ),
      child: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'Hali xabar yo\'q',
                      style: WBText.grotesk(size: 12.5, color: WBColors.textA(.35)),
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                    children: [
                      for (final message in messages) ...[
                        Align(
                          alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 240),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: message.mine ? WBColors.accentA(.16) : WBColors.whiteA(.05),
                              border: Border.all(
                                color: message.mine ? WBColors.accentA(.34) : WBColors.whiteA(.1),
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              message.text,
                              style: WBText.grotesk(size: 13, weight: FontWeight.w500),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: textController,
                      focusNode: focusNode,
                      onSubmitted: (_) => onSend(),
                      textInputAction: TextInputAction.send,
                      maxLength: 200,
                      buildCounter: (
                        BuildContext context, {
                        required int currentLength,
                        required bool isFocused,
                        required int? maxLength,
                      }) =>
                          null,
                      style: WBText.grotesk(size: 13.5),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: WBColors.whiteA(.05),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                        hintText: 'Xabar yoz…',
                        hintStyle: WBText.grotesk(size: 13.5, color: WBColors.textA(.3)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: WBColors.whiteA(.13)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: WBColors.whiteA(.13)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: WBColors.accentA(.6)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Pressable(
                  onTap: onSend,
                  pressScale: .95,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: wbAccentGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: StrokeGlyph.chevronRight(
                      size: 12,
                      thickness: 2.5,
                      color: WBColors.accentInk,
                      offset: const Offset(-3, 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The topic a themed duel is played inside, named where the player can see
/// it for the whole duel. Amber rather than the turn pill's grey: it is the
/// rule that makes this duel different from every other one.
class _ThemePill extends StatelessWidget {
  const _ThemePill({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: WBColors.accentA(.14),
        border: Border.all(color: WBColors.accentA(.34)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WBText.grotesk(size: 11, weight: FontWeight.w600, color: WBColors.accent),
      ),
    );
  }
}

/// The opponent's reaction, floating briefly over their side of the board.
class _ReactionBubble extends StatelessWidget {
  const _ReactionBubble({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WBColors.whiteA(.06),
        border: Border.all(color: WBColors.whiteA(.12)),
        shape: BoxShape.circle,
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 26)),
    );
  }
}

/// Why the required letter is not the last letter of the last word.
///
/// The rule fires perhaps once in a few duels, which is exactly why it needs
/// saying: a player who meets it unannounced reads it as the server getting the
/// letter wrong. It sits under the letter chip it explains, one muted line, and
/// leaves with the turn — anything larger would be a banner about a detail.
///
/// The same line covers a letter the player skipped themselves, in the words
/// that case wants: they know perfectly well why the letter changed, and being
/// told it was a rare one would be the screen contradicting them.
class _SubstitutionNote extends StatelessWidget {
  const _SubstitutionNote({
    required this.skipped,
    required this.needLetter,
    required this.byPowerUp,
  });

  /// The rare letter the chain skipped, and the one handed over instead.
  final String skipped;
  final String needLetter;

  /// Whether the player skipped it with [DuelPowerUp.skipLetter], rather than
  /// the chain stepping over a letter nobody can answer.
  final bool byPowerUp;

  @override
  Widget build(BuildContext context) {
    // Both letters are drawn like the amber chip above, so the eye connects
    // the sentence to the letter it is talking about.
    final letter = WBText.mono(size: 11.5, weight: FontWeight.w600, color: WBColors.accentA(.8));
    return Text.rich(
      TextSpan(
        style: WBText.grotesk(size: 11.5, color: WBColors.textA(.45)),
        children: [
          TextSpan(text: '«$skipped»', style: letter),
          TextSpan(text: byPowerUp ? " o'tkazib yuborildi — " : ' kam uchraydi — '),
          TextSpan(text: '«$needLetter»', style: letter),
          // "harfidan" rather than a case suffix hung off the quotes: it is
          // how the rejection message already talks about a letter.
          const TextSpan(text: ' harfidan davom et'),
        ],
      ),
    );
  }
}

/// The four power-ups of a bot practice, one charge each.
///
/// Above the word field rather than beside the reactions: they are part of
/// playing the turn, and the hand reaching for one is the hand about to type.
/// A spent charge stays on screen greyed out instead of disappearing — a row
/// that changes shape mid-duel is a row whose buttons move under the finger.
class _PowerUpBar extends StatelessWidget {
  const _PowerUpBar({required this.powerUps, required this.yourTurn, required this.onUse});

  static const _labels = {
    DuelPowerUp.addTime: '+10s',
    DuelPowerUp.skipLetter: "O'tkaz",
    DuelPowerUp.hint: 'Maslahat',
    DuelPowerUp.pressure: 'Shoshir',
  };

  static const _icons = {
    DuelPowerUp.addTime: Icons.more_time,
    DuelPowerUp.skipLetter: Icons.skip_next,
    DuelPowerUp.hint: Icons.lightbulb_outline,
    DuelPowerUp.pressure: Icons.bolt,
  };

  final DuelPowerUps powerUps;

  /// All four act on the turn being played, so all four wait for it — as the
  /// server does, which refuses every one of them on the bot's turn.
  final bool yourTurn;
  final ValueChanged<DuelPowerUp> onUse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final powerUp in DuelPowerUp.values) ...[
              Expanded(child: _button(powerUp)),
              if (powerUp != DuelPowerUp.values.last) const SizedBox(width: 6),
            ],
          ],
        ),
        if (powerUps.hints.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            powerUps.hints.join(' · '),
            textAlign: TextAlign.center,
            style: WBText.mono(size: 12, weight: FontWeight.w500, color: WBColors.accentA(.85)),
          ),
        ],
      ],
    );
  }

  Widget _button(DuelPowerUp powerUp) {
    final available = yourTurn && !powerUps.isSpent(powerUp);
    return Pressable(
      onTap: available ? () => onUse(powerUp) : null,
      pressScale: .95,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: available ? 1 : .35,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WBColors.whiteA(.05),
            border: Border.all(color: WBColors.whiteA(.1)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icons[powerUp], size: 13, color: WBColors.accentA(.9)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _labels[powerUp]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 11, weight: FontWeight.w600, color: WBColors.textA(.7)),
                ),
              ),
            ],
          ),
        ),
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
