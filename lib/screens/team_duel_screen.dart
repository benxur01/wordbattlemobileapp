import 'dart:async';

import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/chain_bubble.dart';
import '../widgets/primary_button.dart';
import '../widgets/progress_ring.dart';
import '../widgets/stroke_glyph.dart';
import 'duel_screen.dart';

/// The live 2v2 duel board — [DuelScreen]'s team sibling: the same chain,
/// timer ring and word field, with a four-participant header instead of one
/// opponent and a chain that has to say *which* of the four spoke each word.
/// Chat and reactions work as they do in a 1v1 duel, except that every line
/// and every emoji is tagged with whichever of the other three sent it.
class TeamDuelScreen extends StatefulWidget {
  const TeamDuelScreen({
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
  });

  final TeamDuelView? duel;
  final UserDto? me;

  /// Set by a `team_duel.rejected` frame: shown without losing the turn.
  final String error;
  final ScrollController scrollController;
  final ValueChanged<String> onSubmit;

  /// This duel's chat, oldest first — never persisted, exactly as
  /// [DuelScreen.chatLog] is not.
  final List<TeamChatMessage> chatLog;
  final ValueChanged<String> onSendChat;
  final ValueChanged<String> onSendReaction;

  /// The latest reaction any of the other three sent, or null once none is
  /// showing — see [DuelScreen.reaction] for how [TeamReaction.id] replays the
  /// animation for the same emoji twice.
  final TeamReaction? reaction;

  @override
  State<TeamDuelScreen> createState() => _TeamDuelScreenState();
}

class _TeamDuelScreenState extends State<TeamDuelScreen> {
  // Held for the whole duel, same as `DuelScreen._focus` — see its own note
  // for why disabling the field on a turn that is not this player's would
  // take the keyboard down with it.
  final _focus = FocusNode();
  final _controller = TextEditingController();

  bool _chatOpen = false;
  final _chatFocus = FocusNode();
  final _chatController = TextEditingController();
  final _chatScroll = ScrollController();

  /// The reaction on screen and how far its fade has got — mirrors
  /// `DuelScreen`'s pair of the same name.
  TeamReaction? _shownReaction;
  bool _reactionVisible = false;
  Timer? _reactionFadeTimer;
  Timer? _reactionGoneTimer;

  @override
  void didUpdateWidget(TeamDuelScreen oldWidget) {
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
    if (text.trim().isEmpty) return;
    widget.onSendChat(text);
    _chatController.clear();
    _chatFocus.requestFocus();
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
        _SocialBar(
          chatOpen: _chatOpen,
          onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
          onReact: widget.onSendReaction,
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
                              : (word.playerId == duel.opponentOne.id
                                  ? duel.opponentOne.label
                                  : duel.opponentTwo.label),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
              if (_shownReaction != null)
                Positioned(
                  top: 8,
                  left: 12,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _reactionVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: _ReactionBubble(
                        emoji: _shownReaction!.emoji,
                        sender: _shownReaction!.sender,
                      ),
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

/// The quick-reaction row and the chat toggle — `DuelScreen._SocialBar` on a
/// board with three other people to send to instead of one.
class _SocialBar extends StatelessWidget {
  const _SocialBar({required this.chatOpen, required this.onToggleChat, required this.onReact});

  final bool chatOpen;
  final VoidCallback onToggleChat;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: WBColors.whiteA(.07))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                for (final emoji in kDuelReactions) ...[
                  Pressable(
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

/// The duel's chat log and the field that adds to it — `DuelScreen._ChatPanel`
/// with a name over every bubble that is not this player's own, since three
/// different people can be talking at once.
class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.messages,
    required this.scrollController,
    required this.textController,
    required this.focusNode,
    required this.onSend,
  });

  final List<TeamChatMessage> messages;
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (message.sender != null) ...[
                                  Text(
                                    message.sender!,
                                    style: WBText.mono(
                                      size: 9.5,
                                      weight: FontWeight.w600,
                                      color: WBColors.textA(.45),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                ],
                                Text(
                                  message.text,
                                  style: WBText.grotesk(size: 13, weight: FontWeight.w500),
                                ),
                              ],
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
                    child: const StrokeGlyph.chevronRight(
                      size: 12,
                      thickness: 2.5,
                      color: WBColors.accentInk,
                      offset: Offset(-3, 0),
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

/// A reaction floating briefly over the board, under the name of whoever sent
/// it — `DuelScreen._ReactionBubble` cannot say who, and here it has to.
class _ReactionBubble extends StatelessWidget {
  const _ReactionBubble({required this.emoji, required this.sender});

  final String emoji;
  final String sender;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WBColors.whiteA(.06),
            border: Border.all(color: WBColors.whiteA(.12)),
            shape: BoxShape.circle,
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 26)),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            sender,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: WBText.mono(size: 9.5, weight: FontWeight.w600, color: WBColors.textA(.5)),
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
