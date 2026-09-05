import 'package:flutter/material.dart';

import '../api/tournament_models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

/// The lobby's "Barchasini ko'rish": every tournament worth discovering,
/// paginated — every `open` one a stranger may still self-join, and every
/// tournament already live or finished, open to spectate either way. Never
/// shows an `open` + private row; those are still waiting on their
/// organizer's own friends, which `TournamentService#browse` already leaves
/// out of what it sends down.
class TournamentsBrowseScreen extends StatelessWidget {
  const TournamentsBrowseScreen({
    super.key,
    required this.tournaments,
    required this.loading,
    required this.loadingMore,
    required this.busy,
    required this.meRating,
    required this.onBack,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onSpectate,
    required this.onJoin,
  });

  final List<TournamentSummary> tournaments;

  /// True only while the very first page is loading — the rest of the list
  /// stays on screen while a later page loads instead of flashing a spinner.
  final bool loading;

  /// True while a further page is on its way.
  final bool loadingMore;

  /// True while a join is in flight — every row's "Qo'shilish" is disabled
  /// together, the same single flag every other screen in the app gates its
  /// own busy button on.
  final bool busy;

  /// This player's own rating, so a global tournament's floor can be shown
  /// ahead of the server's own refusal. Null only in the moment before the
  /// first profile load.
  final int? meRating;

  final VoidCallback onBack;
  final VoidCallback onRefresh;

  /// Null once there is no further page to ask for, or while one is already
  /// loading — the row that fires this hides itself behind that null rather
  /// than drawing disabled.
  final VoidCallback? onLoadMore;

  final void Function(int tournamentId) onSpectate;
  final void Function(int tournamentId) onJoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _header() {
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
            child: Text(
              'Turnirlar',
              textAlign: TextAlign.center,
              style: WBText.grotesk(size: 15, weight: FontWeight.w600),
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

  Widget _body() {
    if (tournaments.isEmpty) {
      if (loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Text("Hozircha ko'radigan turnir yo'q", style: WBText.grotesk(size: 14, color: WBColors.textA(.5))),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
      children: [
        for (final t in tournaments) ...[_row(t), const SizedBox(height: 9)],
        if (onLoadMore != null || loadingMore) _loadMoreButton(),
      ],
    );
  }

  Widget _loadMoreButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Pressable(
        onTap: onLoadMore,
        pressScale: .98,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: double.infinity,
          height: 46,
          decoration: BoxDecoration(
            color: WBColors.whiteA(.05),
            border: Border.all(color: WBColors.whiteA(.1)),
            borderRadius: BorderRadius.circular(15),
          ),
          alignment: Alignment.center,
          child: loadingMore
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(
                  "Yana ko'rsatish",
                  style: WBText.grotesk(size: 13.5, weight: FontWeight.w600, color: WBColors.textA(.7)),
                ),
        ),
      ),
    );
  }

  Widget _row(TournamentSummary t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.045),
        border: Border.all(color: WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _kindBadge(t.kind),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  '${t.statusLabel} · ${t.acceptedCount}/${t.size}',
                  style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.textA(.5)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _action(t),
        ],
      ),
    );
  }

  Widget _kindBadge(String kind) {
    final (label, color) = switch (kind) {
      'global' => ('Global', WBColors.amber),
      'admin' => ('Ommaviy', WBColors.blue),
      _ => ("Do'stlar", WBColors.purple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        border: Border.all(color: color.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: WBText.mono(size: 9.5, weight: FontWeight.w600, color: color, letterSpacing: .04)),
    );
  }

  /// "Kirish" to spectate a live or finished bracket; "Qo'shilish" to
  /// self-join an open public/global one, greyed with the rating floor
  /// itself as its label when this player falls short of it — never a raw
  /// error after the tap for a case the row could already see coming.
  Widget _action(TournamentSummary t) {
    if (t.status == 'in_progress' || t.status == 'completed') {
      return _pillButton(label: 'Kirish', onTap: () => onSpectate(t.id));
    }
    if (t.status != 'open' || !t.isJoinable) return const SizedBox.shrink();

    final floor = t.minRating;
    final ratingTooLow = t.isGlobal && floor != null && meRating != null && meRating! < floor;
    if (ratingTooLow) {
      return _pillButton(label: "Kamida ${_formatRating(floor)} reyting kerak", onTap: null, muted: true);
    }
    return _pillButton(
      label: busy ? 'Yuborilmoqda…' : "Qo'shilish",
      onTap: busy ? null : () => onJoin(t.id),
    );
  }

  Widget _pillButton({required String label, required VoidCallback? onTap, bool muted = false}) {
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      pressScale: .96,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 108),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          gradient: enabled && !muted ? wbAccentGradient : null,
          color: enabled && !muted ? null : WBColors.whiteA(.06),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: WBText.grotesk(
            size: 12.5,
            weight: FontWeight.w600,
            color: enabled && !muted ? WBColors.accentInk : WBColors.textA(.4),
          ),
        ),
      ),
    );
  }

  String _formatRating(double value) => value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
}
