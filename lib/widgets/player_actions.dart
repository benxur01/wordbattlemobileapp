import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import 'primary_button.dart';

/// Which of the two things the player asked to do about somebody.
enum PlayerAction { report, block }

/// What the report dialog collected.
typedef ReportDraft = ({ReportReason reason, String details});

/// The report-and-block sheet: one section per player in [players], each with
/// both buttons. One player when the tap was on a particular person — a
/// friend's row, a chat line — and several when it could have been about any
/// of them, the way a 2v2 duel's flag can.
///
/// Returns who, and which of the two, or null when the sheet was dismissed.
Future<(UserDto, PlayerAction)?> pickPlayerAction(BuildContext context, List<UserDto> players) {
  return showModalBottomSheet<(UserDto, PlayerAction)>(
    context: context,
    backgroundColor: WBColors.bgPanel,
    barrierColor: WBColors.scrim,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final player in players) ...[
              _PlayerSection(player: player),
              const SizedBox(height: 18),
            ],
            Text(
              "Shikoyatni moderator ko'rib chiqadi. Bloklangan o'yinchi bilan o'rtangizda chat, "
              "chaqiruv va do'stlik yopiladi.",
              style: WBText.grotesk(size: 12, height: 1.45, color: WBColors.textA(.5)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Asks why [player] is being reported, with room for the player's own words.
/// [details] starts the text off — the chat line being reported, when there is
/// one: the server keeps no duel chat, so the report is the only place it
/// survives for a moderator to read. Null when the player backed out.
Future<ReportDraft?> askReport(BuildContext context, UserDto player, {String details = ''}) {
  return showDialog<ReportDraft>(
    context: context,
    builder: (context) => _ReportDialog(player: player, initialDetails: details),
  );
}

/// Asks before blocking, and says what a block does — the last moment to
/// change one's mind, and the one place the player is told how to undo it.
/// False when the dialog is dismissed.
Future<bool> confirmBlock(BuildContext context, UserDto player) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: WBColors.bgPanel,
      title: Text('${player.label} bloklansinmi?', style: WBText.grotesk(size: 16, weight: FontWeight.w700)),
      content: Text(
        "O'rtangizda chat va reaksiyalar yetkazilmaydi, bir-biringizni jangga chaqira, jamoaga taklif "
        "qila va do'stlik so'rovi yubora olmaysiz, navbat sizni raqib qilib juftlamaydi. Do'stligingiz "
        "bekor qilinadi. Blokni Profil → «Bloklangan o'yinchilar» bo'limida olib tashlash mumkin.",
        style: WBText.grotesk(size: 13, height: 1.45, color: WBColors.textA(.72)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Bekor qilish',
            style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: WBColors.textA(.75)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(backgroundColor: WBColors.redA(.14)),
          child: Text(
            'Bloklash',
            style: WBText.grotesk(size: 13, weight: FontWeight.w700, color: WBColors.redSoft),
          ),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// The duel screens' way to report or block the people on the board: a flag
/// beside the chat toggle, the same size as every other button in that bar.
class PlayerReportButton extends StatelessWidget {
  const PlayerReportButton({super.key, required this.onTap});

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
          color: WBColors.whiteA(.05),
          border: Border.all(color: WBColors.whiteA(.1)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.flag_outlined,
          size: 16,
          color: WBColors.textA(.6),
          semanticLabel: 'Shikoyat qilish yoki bloklash',
        ),
      ),
    );
  }
}

class _PlayerSection extends StatelessWidget {
  const _PlayerSection({required this.player});

  final UserDto player;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          player.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WBText.grotesk(size: 16, weight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SheetButton(
                icon: Icons.flag_outlined,
                label: 'Shikoyat qilish',
                color: WBColors.textA(.85),
                border: WBColors.whiteA(.14),
                onTap: () => Navigator.of(context).pop((player, PlayerAction.report)),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _SheetButton(
                icon: Icons.block,
                label: 'Bloklash',
                color: WBColors.redSoft,
                border: WBColors.redA(.35),
                onTap: () => Navigator.of(context).pop((player, PlayerAction.block)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.border,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressScale: .97,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: WBColors.whiteA(.04),
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WBText.grotesk(size: 13.5, weight: FontWeight.w600, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The body of [askReport]. A widget of its own so the details field's
/// controller belongs to the dialog and goes when it does.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.player, required this.initialDetails});

  final UserDto player;
  final String initialDetails;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late final TextEditingController _details = TextEditingController(text: widget.initialDetails);

  /// Nothing is picked to begin with: a report sent on a default reason would
  /// say something the player never said.
  ReportReason? _reason;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: WBColors.whiteA(.13)),
    );
    return AlertDialog(
      backgroundColor: WBColors.bgPanel,
      title: Text(
        'Shikoyat: ${widget.player.label}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WBText.grotesk(size: 16, weight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in ReportReason.values)
              _ReasonOption(
                label: option.label,
                selected: option == reason,
                onTap: () => setState(() => _reason = option),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _details,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: WBText.grotesk(size: 13.5),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: WBColors.whiteA(.05),
                hintText: "Nima bo'ldi? (ixtiyoriy)",
                hintStyle: WBText.grotesk(size: 13.5, color: WBColors.textA(.35)),
                counterStyle: WBText.mono(size: 10, color: WBColors.textA(.4)),
                border: outline,
                enabledBorder: outline,
                focusedBorder: outline.copyWith(borderSide: BorderSide(color: WBColors.accentA(.6))),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Bekor qilish',
            style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: WBColors.textA(.75)),
          ),
        ),
        TextButton(
          onPressed: reason == null
              ? null
              : () => Navigator.of(context).pop((reason: reason, details: _details.text.trim())),
          style: TextButton.styleFrom(
            backgroundColor: WBColors.accentA(.16),
            disabledBackgroundColor: WBColors.whiteA(.04),
          ),
          child: Text(
            'Yuborish',
            style: WBText.grotesk(
              size: 13,
              weight: FontWeight.w700,
              color: reason == null ? WBColors.textA(.35) : WBColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// One reason in the report dialog, drawn as a radio button of the app's own
/// rather than Material's, so it takes the palette like everything else here.
class _ReasonOption extends StatelessWidget {
  const _ReasonOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? WBColors.accent : WBColors.textA(.35), width: 2),
                ),
                child: selected
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: WBColors.accent, shape: BoxShape.circle),
                      )
                    : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: WBText.grotesk(size: 14, weight: selected ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
