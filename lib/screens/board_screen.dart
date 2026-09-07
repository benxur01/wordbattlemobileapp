import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/provisional_badge.dart';
import '../widgets/spinner_ring.dart';

class BoardScreen extends StatelessWidget {
  const BoardScreen({
    super.key,
    required this.board,
    required this.tabGlobal,
    required this.onGlobalTab,
    required this.onClassTab,
    required this.onHome,
    required this.onFriends,
    required this.onProfile,
    required this.friendRequestCount,
    this.previousTab,
  });

  /// Null while the request is in flight.
  final LeaderboardDto? board;
  final bool tabGlobal;
  final VoidCallback onGlobalTab;
  final VoidCallback onClassTab;
  final VoidCallback onHome;
  final VoidCallback onFriends;
  final VoidCallback onProfile;
  final int friendRequestCount;

  /// Which tab the previous screen highlighted, so the bar can animate.
  final WBTab? previousTab;

  /// Avatar tint, picked from the player id so the same person keeps the same
  /// colour everywhere. The design hand-picked one per row; with live data the
  /// palette has to be derived from something stable.
  static List<Gradient> get _gradients => [
        wbRoseGradient,
        wbTealGradient,
        wbPurpleGradient,
        wbAmber8Gradient,
        wbBlueGradient,
        wbGreyGradient,
      ];
  static List<Color> get _textColors => [
        WBColors.roseText,
        WBColors.tealText,
        WBColors.purpleText,
        WBColors.amber8Text,
        WBColors.blueText,
        WBColors.greyText,
      ];

  static int paletteIndex(int userId) => userId.abs() % _gradients.length;

  static Gradient gradientFor(int userId) => _gradients[paletteIndex(userId)];

  static Color textColorFor(int userId) => _textColors[paletteIndex(userId)];

  @override
  Widget build(BuildContext context) {
    final data = board;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Liderlar taxtasi',
                style: WBText.grotesk(size: 26, weight: FontWeight.w700, letterSpacing: -.01),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: WBColors.whiteA(.05),
                  border: Border.all(color: WBColors.whiteA(.08)),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    _Tab(label: 'Global', active: tabGlobal, onTap: onGlobalTab),
                    _Tab(label: "Do'stlar", active: !tabGlobal, onTap: onClassTab),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: data == null
              ? Center(
                  child: SpinnerRing(
                    size: 26,
                    trackColor: WBColors.textA(.15),
                    activeColor: WBColors.accent,
                    strokeWidth: 2.5,
                  ),
                )
              : data.rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      tabGlobal ? "Hali hech kim jang qilmagan" : "Do'stlaringiz yo'q — avval do'st qo'shing",
                      textAlign: TextAlign.center,
                      style: WBText.grotesk(size: 14, height: 1.5, color: WBColors.textA(.45)),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
                  children: [
                    for (final row in data.rows) ...[_row(row), const SizedBox(height: 8)],
                  ],
                ),
        ),
        if (data?.me != null)
          Container(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
            decoration: BoxDecoration(
              color: WBColors.bg.withValues(alpha: .92),
              border: Border(top: BorderSide(color: WBColors.whiteA(.08))),
            ),
            child: _row(data!.me!, pinned: true),
          ),
        BottomNav(
          active: WBTab.board,
          previous: previousTab,
          friendRequestCount: friendRequestCount,
          onHome: onHome,
          onFriends: onFriends,
          onBoard: () {},
          onProfile: onProfile,
        ),
      ],
    );
  }

  Widget _row(LeaderboardRow row, {bool pinned = false}) {
    final podium = row.rank <= 3;
    final highlight = row.rank == 1;
    final dim = !podium && !row.self;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        gradient: highlight
            ? LinearGradient(
                colors: [WBColors.amberA(.16), WBColors.amberA(.04)],
              )
            : null,
        // The player's own row carries a faint amber tint in the design.
        color: highlight
            ? null
            : (row.self
                  ? WBColors.accentA(pinned ? .11 : .07)
                  : (dim ? WBColors.whiteA(.03) : WBColors.whiteA(.045))),
        border: Border.all(
          color: highlight
              ? WBColors.accentA(.32)
              : (row.self
                    ? WBColors.accentA(pinned ? .34 : .22)
                    : (dim ? WBColors.whiteA(.07) : WBColors.whiteA(.09))),
        ),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          SizedBox(
            width: pinned ? 34 : 26,
            child: Text(
              '${row.rank}',
              // A three-digit rank is wider than the column; CSS lets it run into
              // the gap rather than wrap onto a second line.
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: WBText.mono(
                size: dim ? 15 : 16,
                weight: dim ? FontWeight.w500 : FontWeight.w700,
                color: highlight || (row.self && pinned) ? WBColors.accent : WBColors.textA(dim ? .45 : .8),
              ),
            ),
          ),
          Container(
            width: pinned ? 38 : 40,
            height: pinned ? 38 : 40,
            decoration: BoxDecoration(
              gradient: gradientFor(row.user.id),
              borderRadius: BorderRadius.circular(pinned ? 12 : 13),
            ),
            alignment: Alignment.center,
            child: Text(
              row.user.initial,
              style: WBText.grotesk(
                size: pinned ? 14 : 15,
                weight: FontWeight.w700,
                color: textColorFor(row.user.id),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.self ? '${row.user.label} · sen' : row.user.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: pinned ? 14.5 : 15, weight: FontWeight.w600),
                ),
                if (row.user.city != null)
                  Text(row.user.city!, style: WBText.grotesk(size: 11.5, color: WBColors.textA(.45))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (row.user.provisional) ...[
            ProvisionalBadge(size: 10),
            const SizedBox(width: 6),
          ],
          Text(
            '${row.user.rating}',
            style: WBText.mono(
              size: 16,
              weight: dim ? FontWeight.w600 : FontWeight.w700,
              color: highlight || (row.self && pinned)
                  ? WBColors.accent
                  : (row.self ? WBColors.text : WBColors.textA(dim ? .7 : .8)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: active ? null : onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: active ? WBColors.accentA(.16) : Colors.transparent,
            border: Border.all(color: active ? WBColors.accentA(.34) : Colors.transparent),
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: WBText.grotesk(
              size: 14,
              weight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? WBColors.accent : WBColors.textA(.55),
            ),
          ),
        ),
      ),
    );
  }
}
