import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api/tournament_models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

const _gradients = [
  wbTealGradient,
  wbPurpleGradient,
  wbBlueGradient,
  wbRoseGradient,
  wbAmber8Gradient,
  wbGreyGradient,
];
const _textColors = [
  WBColors.tealText,
  WBColors.purpleText,
  WBColors.blueText,
  WBColors.roseText,
  WBColors.amber8Text,
  WBColors.greyText,
];

/// The organizer's own view of a tournament they just created: who has
/// answered so far, the button that seeds the bracket once everyone has, and
/// the way out of one that got stuck — the friends-screen equivalent of the
/// admin panel's tournament detail screen, without an admin role or an audit
/// log behind it.
class OrganizeTournamentManageScreen extends StatefulWidget {
  const OrganizeTournamentManageScreen({
    super.key,
    required this.tournament,
    required this.participants,
    required this.busy,
    required this.onBack,
    required this.onRefresh,
    required this.onStart,
    required this.onCancel,
  });

  final TournamentSummary? tournament;

  /// Null while still loading.
  final List<TournamentParticipantView>? participants;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onStart;

  /// Calls the tournament off for good — confirmed in place before it fires,
  /// the same way the profile screen's "Akkauntni o'chirish" is.
  final VoidCallback onCancel;

  @override
  State<OrganizeTournamentManageScreen> createState() => _OrganizeTournamentManageScreenState();
}

class _OrganizeTournamentManageScreenState extends State<OrganizeTournamentManageScreen> {
  /// Cancelling cannot be undone, so the button asks once more in place
  /// rather than acting on the first tap. Inline instead of a dialog: the
  /// whole UI is a scaled fixed-width canvas, and a system dialog would land
  /// outside it at a different size.
  bool _confirmingCancel = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final rows = widget.participants;
    final accepted = rows?.where((p) => p.accepted).length ?? 0;
    final ready = t != null && rows != null && accepted == t.size;
    final cancellable = t != null && (t.status == 'open' || t.status == 'in_progress');

    return Column(
      children: [
        _header(t),
        Expanded(
          child: t == null || rows == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
                  children: [
                    Text('$accepted/${t.size} qabul qildi', style: WBText.grotesk(size: 14, color: WBColors.textA(.6))),
                    const SizedBox(height: 14),
                    for (final row in rows) ...[_row(row), const SizedBox(height: 9)],
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
          child: Pressable(
            onTap: !ready || widget.busy ? null : widget.onStart,
            pressScale: .98,
            child: Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                gradient: ready ? wbAccentGradient : null,
                color: ready ? null : WBColors.whiteA(.06),
                borderRadius: BorderRadius.circular(19),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.busy ? 'Boshlanmoqda…' : 'Turnirni boshlash',
                style: WBText.grotesk(size: 16, weight: FontWeight.w600, color: ready ? WBColors.accentInk : WBColors.textA(.4)),
              ),
            ),
          ),
        ),
        if (cancellable)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
            child: _cancelSection(),
          ),
      ],
    );
  }

  Widget _cancelSection() {
    if (!_confirmingCancel) {
      return _FlatActionButton(
        label: 'Turnirni bekor qilish',
        color: WBColors.redSoft,
        border: WBColors.redA(.28),
        onTap: widget.busy ? null : () => setState(() => _confirmingCancel = true),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: WBColors.redA(.08),
        border: Border.all(color: WBColors.redA(.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Turnir butunlay bekor qilinadi va uni qayta boshlab bo'lmaydi. Barcha qatnashchilarga xabar beriladi.",
            style: WBText.grotesk(size: 12, height: 1.45, color: WBColors.textA(.72)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FlatActionButton(
                  label: 'Bekor qilish',
                  color: WBColors.textA(.75),
                  border: WBColors.whiteA(.12),
                  onTap: widget.busy ? null : () => setState(() => _confirmingCancel = false),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _FlatActionButton(
                  label: widget.busy ? 'Bekor qilinmoqda…' : 'Ha, bekor qilish',
                  color: WBColors.redSoft,
                  border: WBColors.redA(.45),
                  fill: WBColors.redA(.14),
                  onTap: widget.busy ? null : widget.onCancel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(TournamentSummary? t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 13),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color.fromRGBO(255, 255, 255, .07)))),
      child: Row(
        children: [
          Pressable(
            onTap: widget.onBack,
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
              child: const Icon(Icons.arrow_back_ios_new, size: 14, color: Colors.white70),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  t?.name ?? 'Turnir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                ),
                if (t != null)
                  Text(
                    "${t.size} o'yinchi · yagona eliminatsiya",
                    style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.4), letterSpacing: .1),
                  ),
              ],
            ),
          ),
          Pressable(
            onTap: t == null ? null : () => _share(t),
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
              child: const Icon(Icons.ios_share, size: 15, color: Colors.white70),
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: widget.onRefresh,
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
              child: const Icon(Icons.refresh, size: 16, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  /// `wordbattle.example.uz` is a placeholder for the real production domain
  /// — swap it here once one exists (see backend/README.md's "Turnirlar"
  /// section for the Android App Links half of this link).
  void _share(TournamentSummary t) {
    SharePlus.instance.share(
      ShareParams(text: "${t.name} turniriga qo'shil! https://wordbattle.example.uz/t/${t.id}"),
    );
  }

  Widget _row(TournamentParticipantView p) {
    final color = switch (p.status) {
      'accepted' => WBColors.green,
      'declined' => WBColors.red,
      _ => WBColors.textA(.5),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.045),
        border: Border.all(color: WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          _avatar(p),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.user?.label ?? '#${p.userId}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WBText.grotesk(size: 15, weight: FontWeight.w600),
            ),
          ),
          Text(p.statusLabel, style: WBText.grotesk(size: 12.5, weight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _avatar(TournamentParticipantView p) {
    final gradient = _gradients[p.userId.abs() % _gradients.length];
    final color = _textColors[p.userId.abs() % _textColors.length];
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: Text(p.user?.initial ?? '?', style: WBText.grotesk(size: 16, weight: FontWeight.w700, color: color)),
    );
  }
}

/// A flat, bordered row button — quieter than the accent-coloured calls to
/// action elsewhere on this screen, the same tone the profile screen uses
/// for its own account actions.
class _FlatActionButton extends StatelessWidget {
  const _FlatActionButton({
    required this.label,
    required this.color,
    required this.border,
    required this.onTap,
    this.fill,
  });

  final String label;
  final Color color;
  final Color border;
  final Color? fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: fill ?? WBColors.whiteA(.04),
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(15),
          ),
          alignment: Alignment.center,
          child: Text(label, style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: color)),
        ),
      ),
    );
  }
}
