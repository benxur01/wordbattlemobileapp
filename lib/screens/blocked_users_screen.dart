import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/spinner_ring.dart';
import '../widgets/stroke_glyph.dart';
import 'board_screen.dart';

/// Everyone this player has blocked, and the way to take a block back. Reached
/// from the profile, the only place a block can be undone: a blocked player is
/// hidden from search, so there is no other row to find them on.
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key, required this.users, required this.onUnblock, required this.onBack});

  /// Null while the request is in flight.
  final List<BlockedUserDto>? users;
  final ValueChanged<UserDto> onUnblock;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final data = users;

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
                semanticLabel: 'Orqaga',
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
                  Text("Bloklangan o'yinchilar", style: WBText.grotesk(size: 15, weight: FontWeight.w600)),
                  Text(
                    data == null ? '…' : '${data.length} TA',
                    style: WBText.mono(
                      size: 10.5,
                      weight: FontWeight.w500,
                      color: WBColors.textA(.4),
                      letterSpacing: .12,
                    ),
                  ),
                ],
              ),
              // Balances the back button, so the title sits in the middle.
              const SizedBox(width: 38),
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
              : data.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hech kim bloklanmagan',
                          style: WBText.grotesk(size: 16, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "O'yinchini do'stlar ro'yxatidagi yoki jangdagi menyudan bloklash mumkin. "
                          "Bloklanganlar shu yerda turadi va shu yerdan blokdan chiqariladi",
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
                    for (final blocked in data) ...[_row(blocked.user), const SizedBox(height: 9)],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _row(UserDto user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.045),
        border: Border.all(color: WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              // The leaderboard's palette, keyed by user id, so a player wears
              // the same tint here as in every other list.
              gradient: BoardScreen.gradientFor(user.id),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              user.initial,
              style: WBText.grotesk(size: 16, weight: FontWeight.w700, color: BoardScreen.textColorFor(user.id)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WBText.grotesk(size: 15, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Pressable(
            onTap: () => onUnblock(user),
            pressScale: .96,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.14)),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                'Blokdan chiqarish',
                style: WBText.grotesk(size: 12.5, weight: FontWeight.w600, color: WBColors.textA(.8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
