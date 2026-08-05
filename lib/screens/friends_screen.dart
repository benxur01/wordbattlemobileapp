import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/primary_button.dart';
import '../widgets/stroke_glyph.dart';
import '../widgets/synced_text_field.dart';

/// Friends, requests and search — all live. Avatar colours are derived from the
/// user id so the same person keeps the same tint across every screen.
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({
    super.key,
    required this.search,
    required this.searchResults,
    required this.isRequestSent,
    required this.requests,
    required this.friends,
    required this.onSearchChanged,
    required this.onSendRequest,
    required this.onAccept,
    required this.onDecline,
    required this.onChallenge,
    required this.onHome,
    required this.onBoard,
    required this.onProfile,
    this.previousTab,
  });

  final String search;
  final List<UserDto> searchResults;

  /// Whether a request to this user was already sent in this session.
  final bool Function(int userId) isRequestSent;

  final List<FriendRequestDto> requests;
  final List<FriendDto> friends;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<UserDto> onSendRequest;
  final ValueChanged<FriendRequestDto> onAccept;
  final ValueChanged<FriendRequestDto> onDecline;
  final ValueChanged<FriendDto> onChallenge;
  final VoidCallback onHome;
  final VoidCallback onBoard;
  final VoidCallback onProfile;

  /// Which tab the previous screen highlighted, so the bar can animate.
  final WBTab? previousTab;

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

  static Gradient _gradientFor(int id) => _gradients[id.abs() % _gradients.length];

  static Color _textColorFor(int id) => _textColors[id.abs() % _textColors.length];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Do'stlar", style: WBText.grotesk(size: 26, weight: FontWeight.w700, letterSpacing: -.01)),
              const SizedBox(height: 12),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: WBColors.whiteA(.05),
                  border: Border.all(color: WBColors.whiteA(.11)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: WBColors.textA(.4), width: 2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SyncedTextField(
                        value: search,
                        onChanged: onSearchChanged,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.search,
                        style: WBText.grotesk(size: 14.5, weight: FontWeight.w500),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: "taxallus bo'yicha qidirish",
                          hintStyle: WBText.grotesk(
                            size: 14.5,
                            weight: FontWeight.w500,
                            color: WBColors.textA(.4),
                          ),
                        ),
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
            padding: const EdgeInsets.fromLTRB(22, 2, 22, 12),
            children: [
              if (search.trim().isNotEmpty) ...[
                const _SectionLabel('QIDIRUV NATIJASI'),
                const SizedBox(height: 9),
                if (searchResults.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Hech kim topilmadi',
                      style: WBText.grotesk(size: 13.5, color: WBColors.textA(.45)),
                    ),
                  )
                else
                  for (final user in searchResults) ...[_searchRow(user), const SizedBox(height: 9)],
                const SizedBox(height: 9),
              ],
              if (requests.isNotEmpty) ...[
                _SectionLabel("DO'STLIK TAKLIFLARI · ${requests.length}"),
                const SizedBox(height: 9),
                for (final request in requests) ...[_requestRow(request), const SizedBox(height: 9)],
                const SizedBox(height: 9),
              ],
              _SectionLabel('ONLAYN · ${friends.where((f) => f.online).length}'),
              const SizedBox(height: 9),
              if (friends.where((f) => f.online).isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    friends.isEmpty
                        ? "Hali do'stlaringiz yo'q — yuqoridan qidiring"
                        : "Hozir hech kim onlayn emas",
                    style: WBText.grotesk(size: 13.5, color: WBColors.textA(.45)),
                  ),
                )
              else
                for (final friend in friends.where((f) => f.online)) ...[
                  _friendRow(friend),
                  const SizedBox(height: 9),
                ],
              if (friends.any((f) => !f.online)) ...[
                const SizedBox(height: 9),
                const _SectionLabel('OFLAYN'),
                const SizedBox(height: 9),
                for (final friend in friends.where((f) => !f.online)) ...[
                  Opacity(opacity: .72, child: _friendRow(friend)),
                  const SizedBox(height: 9),
                ],
              ],
            ],
          ),
        ),
        BottomNav(
          active: WBTab.friends,
          previous: previousTab,
          friendRequestCount: requests.length,
          onHome: onHome,
          onFriends: () {},
          onBoard: onBoard,
          onProfile: onProfile,
        ),
      ],
    );
  }

  Widget _avatar(UserDto user, {bool onlineDot = false, double size = 42}) {
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: _gradientFor(user.id), borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: Text(
        user.initial,
        style: WBText.grotesk(size: 16, weight: FontWeight.w700, color: _textColorFor(user.id)),
      ),
    );
    if (!onlineDot) return tile;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: WBColors.green,
              shape: BoxShape.circle,
              border: Border.all(color: WBColors.bgDeep, width: 2.5),
            ),
          ),
        ),
      ],
    );
  }

  /// A stranger found by search: can be sent a friend request once.
  Widget _searchRow(UserDto user) {
    final sent = isRequestSent(user.id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.045),
        border: Border.all(color: WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          _avatar(user),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                ),
                Text(
                  [user.rating.toString(), if (user.city != null) user.city!].join(' · '),
                  style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.textA(.45)),
                ),
              ],
            ),
          ),
          if (sent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.12)),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text('Yuborildi', style: WBText.grotesk(size: 13, color: WBColors.textA(.5))),
            )
          else
            Pressable(
              onTap: () => onSendRequest(user),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: WBColors.amberA(.16),
                  border: Border.all(color: WBColors.amberA(.4)),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  "+ Do'stlik",
                  style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: WBColors.amber),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _requestRow(FriendRequestDto request) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WBColors.amberA(.07),
        border: Border.all(color: WBColors.amberA(.22)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          _avatar(request.user),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.user.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                ),
                Text(
                  request.meta,
                  style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.textA(.45)),
                ),
              ],
            ),
          ),
          Pressable(
            onTap: () => onAccept(request),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: WBColors.green, borderRadius: BorderRadius.circular(13)),
              alignment: Alignment.center,
              child: const StrokeGlyph.check(
                width: 13,
                height: 8,
                thickness: 3,
                color: WBColors.greenInk,
                offset: Offset(0, -1.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: () => onDecline(request),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.12)),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text(
                '×',
                style: WBText.grotesk(size: 18, weight: FontWeight.w500, color: WBColors.textA(.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _friendRow(FriendDto friend) {
    // Someone already in a duel cannot be challenged; the button says so
    // rather than firing a request the server would refuse.
    final challengeable = friend.online && !friend.inBattle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: friend.online ? WBColors.whiteA(.045) : WBColors.whiteA(.025),
        border: Border.all(color: friend.online ? WBColors.whiteA(.09) : WBColors.whiteA(.06)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          _avatar(friend.user, onlineDot: friend.online),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.user.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                ),
                Text(
                  friend.status,
                  style: WBText.mono(
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: friend.online ? WBColors.green : WBColors.textA(.4),
                  ),
                ),
              ],
            ),
          ),
          if (challengeable)
            Pressable(
              onTap: () => onChallenge(friend),
              pressScale: .96,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
                decoration: BoxDecoration(gradient: wbAmberGradient, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  'Jang',
                  style: WBText.grotesk(size: 13.5, weight: FontWeight.w600, color: WBColors.amberInk),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.1)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                friend.inBattle ? 'Jangda' : 'Oflayn',
                style: WBText.grotesk(size: 13, color: WBColors.textA(.5)),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.4), letterSpacing: .14),
    );
  }
}
