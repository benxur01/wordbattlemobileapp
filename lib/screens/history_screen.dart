import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/spinner_ring.dart';
import '../widgets/stroke_glyph.dart';
import 'board_screen.dart';

/// Finished duels, newest first. The server decides every value shown here —
/// who the opponent was, who won, what the rating did — so the screen only
/// turns the wire codes into Uzbek and lays them out.
///
/// Deliberately list-only: the server also serves each match's full chain
/// (`GET /api/matches/{id}`), but a replay view needs its own screen, its own
/// loading state and its own navigation, and none of that earns its place until
/// there is something to do with a replay.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.matches, required this.onBack});

  /// Null while the request is in flight.
  final List<MatchSummaryDto>? matches;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final data = matches;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: WBColors.whiteA(.07))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  child: StrokeGlyph.chevronLeft(
                    size: 11,
                    thickness: 2,
                    color: WBColors.textA(.8),
                    offset: const Offset(2, 0),
                  ),
                ),
              ),
              Column(
                children: [
                  Text('Janglar tarixi', style: WBText.grotesk(size: 15, weight: FontWeight.w600)),
                  Text(
                    'OXIRGI JANGLAR',
                    style: WBText.mono(
                      size: 10.5,
                      weight: FontWeight.w500,
                      color: WBColors.textA(.4),
                      letterSpacing: .12,
                    ),
                  ),
                ],
              ),
              // Wins out of the battles actually listed — a record for this
              // page, not the lifetime one the profile already shows. A player
              // with no battles is told so by the empty state; a green "0/0"
              // beside it would only rub it in.
              if (data != null && data.isEmpty)
                const SizedBox(width: 38)
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: WBColors.greenA(.11),
                    border: Border.all(color: WBColors.greenA(.28)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    data == null ? '…' : '${data.where((m) => m.won).length}/${data.length}',
                    style: WBText.mono(size: 13, weight: FontWeight.w700, color: WBColors.green),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: data == null
              ? const Center(
                  child: SpinnerRing(
                    size: 26,
                    trackColor: Color.fromRGBO(244, 243, 248, .15),
                    activeColor: WBColors.amber,
                    strokeWidth: 2.5,
                  ),
                )
              : data.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hali jang qilmagansiz',
                          style: WBText.grotesk(size: 16, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Birinchi jangdan keyin har bir zanjir, raqib va reyting o'zgarishi shu "
                          "yerda saqlanadi",
                          textAlign: TextAlign.center,
                          style: WBText.grotesk(size: 14, height: 1.5, color: WBColors.textA(.45)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
                  children: [
                    for (final match in data) ...[_row(match), const SizedBox(height: 9)],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _row(MatchSummaryDto match) {
    final accent = match.won ? WBColors.green : WBColors.redSoft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.045),
        border: Border.all(color: WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  // The leaderboard's palette, keyed by user id, so an opponent
                  // wears the same tint here as in every other list.
                  gradient: BoardScreen.gradientFor(match.opponent.id),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  match.opponent.initial,
                  style: WBText.grotesk(
                    size: 16,
                    weight: FontWeight.w700,
                    color: BoardScreen.textColorFor(match.opponent.id),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  match.opponent.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              // A duel against the bot never moves the rating; printing "+0"
              // would read as a bug, so the slot says why it is empty — the
              // same call the win screen makes.
              if (match.rated)
                Text(
                  '${match.delta >= 0 ? '+' : ''}${match.delta}',
                  style: WBText.mono(size: 16, weight: FontWeight.w700, color: accent),
                )
              else
                Text(
                  'Mashq jangi · reytingsiz',
                  style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(.4)),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(.45)),
                    children: [
                      // Short on purpose: with the longest end reason and a
                      // battle old enough to carry its year, "Mag'lubiyat"
                      // pushed the line past the card and it ellipsised.
                      TextSpan(
                        text: match.won ? 'Yutdi' : 'Yutqazdi',
                        style: TextStyle(color: accent),
                      ),
                      TextSpan(
                        text: ' · ${_endReason(match.endReason)} · ${match.chainLength} zanjir',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _dateLabel(match.finishedAt),
                style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(.35)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// `MatchEntity.EndReason`, lowercased by the server. `words_limit` names no
  /// number on purpose: the target that applied to *this* battle is not stored
  /// with it, so any number printed here would be today's `duel.words-to-win`
  /// pinned onto a battle that may have been won under another one. An unknown
  /// code means the server grew a reason this build has no word for — better a
  /// plain sentence than a raw enum name.
  static String _endReason(String code) => switch (code) {
        'words_limit' => "So'z chegarasi",
        'timeout' => 'Vaqt tugadi',
        'forfeit' => 'Taslim',
        'no_moves' => "So'z topolmadi",
        _ => 'Jang tugadi',
      };

  static const _months = [
    'yanvar',
    'fevral',
    'mart',
    'aprel',
    'may',
    'iyun',
    'iyul',
    'avgust',
    'sentabr',
    'oktabr',
    'noyabr',
    'dekabr',
  ];

  /// `finishedAt` arrives as a UTC instant, so the day has to be compared in
  /// local time or a late-evening battle shows up as tomorrow's. Today and
  /// yesterday are named — that is how a player remembers a recent duel — and
  /// the year appears only when it is not the current one.
  static String _dateLabel(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
    if (days == 0) return 'bugun';
    if (days == 1) return 'kecha';
    final date = '${local.day} ${_months[local.month - 1]}';
    return local.year == now.year ? date : '$date ${local.year}';
  }
}
