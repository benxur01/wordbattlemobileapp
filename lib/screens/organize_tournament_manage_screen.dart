import 'package:flutter/material.dart';

import '../api/tournament_models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

/// The organizer's own view of a tournament they just created: who has
/// answered so far, and the button that seeds the bracket once everyone has —
/// the friends-screen equivalent of the admin panel's tournament detail
/// screen, without an admin role or an audit log behind it.
class OrganizeTournamentManageScreen extends StatelessWidget {
  const OrganizeTournamentManageScreen({
    super.key,
    required this.tournament,
    required this.participants,
    required this.busy,
    required this.onBack,
    required this.onRefresh,
    required this.onStart,
  });

  final TournamentSummary? tournament;

  /// Null while still loading.
  final List<TournamentParticipantView>? participants;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onStart;

  static const _gradients = [
    wbTealGradient,
    wbPurpleGradient,
    wbBlueGradient,
    wbRoseGradient,
    wbAmber8Gradient,
    wbGreyGradient,
  ];
  static const _textColors = [
    WBColors.tealText,
    WBColors.purpleText,
    WBColors.blueText,
    WBColors.roseText,
    WBColors.amber8Text,
    WBColors.greyText,
  ];

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final rows = participants;
    final accepted = rows?.where((p) => p.accepted).length ?? 0;
    final ready = t != null && rows != null && accepted == t.size;

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
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
          child: Pressable(
            onTap: !ready || busy ? null : onStart,
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
                busy ? 'Boshlanmoqda…' : 'Turnirni boshlash',
                style: WBText.grotesk(size: 16, weight: FontWeight.w600, color: ready ? WBColors.accentInk : WBColors.textA(.4)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(TournamentSummary? t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 13),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color.fromRGBO(255, 255, 255, .07)))),
      child: Row(
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
            onTap: onRefresh,
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
