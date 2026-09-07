import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/primary_button.dart';
import '../widgets/provisional_badge.dart';
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
    required this.onSpectate,
    required this.onTeamInvite,
    required this.onHome,
    required this.onBoard,
    required this.onProfile,
    required this.onOrganizeTournament,
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

  /// Watches whichever live duel an `inBattle` friend is currently in — the
  /// slot the (disabled) challenge action occupies for everyone else.
  final ValueChanged<FriendDto> onSpectate;

  /// Invites a friend to form a 2v2 team — offered alongside the ordinary
  /// challenge for anyone online and not already busy.
  final ValueChanged<FriendDto> onTeamInvite;
  final VoidCallback onHome;
  final VoidCallback onBoard;
  final VoidCallback onProfile;

  /// The friends-screen entry point into organizing a tournament of your own.
  final VoidCallback onOrganizeTournament;

  /// Which tab the previous screen highlighted, so the bar can animate.
  final WBTab? previousTab;

  static List<Gradient> get _gradients => [
        wbTealGradient,
        wbPurpleGradient,
        wbBlueGradient,
        wbRoseGradient,
        wbAmber8Gradient,
        wbGreyGradient,
      ];
  static List<Color> get _textColors => [
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
              const SizedBox(height: 10),
              Pressable(
                onTap: onOrganizeTournament,
                pressScale: .98,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: WBColors.accentA(.1),
                    border: Border.all(color: WBColors.accentA(.3)),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events_outlined, size: 18, color: WBColors.accent),
                      const SizedBox(width: 10),
                      Text(
                        'Turnir tashkil qilish',
                        style: WBText.grotesk(size: 14, weight: FontWeight.w600, color: WBColors.accent),
                      ),
                    ],
                  ),
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
                _SectionLabel('QIDIRUV NATIJASI'),
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
                friends.isEmpty
                    ? _NoFriendsYet()
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          "Hozir hech kim onlayn emas",
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
                _SectionLabel('OFLAYN'),
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

  /// The line under a nickname that opens with a rating, in the two rows that
  /// carry one. [Flexible] rather than [Expanded] so a short line keeps the
  /// badge against the text instead of pushing it out to the button.
  Widget _metaLine(String text, bool provisional) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.textA(.45)),
    );
    if (!provisional) return label;
    return Row(
      children: [
        Flexible(child: label),
        const SizedBox(width: 6),
        ProvisionalBadge(size: 8),
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
                _metaLine(
                  [user.rating.toString(), if (user.city != null) user.city!].join(' · '),
                  user.provisional,
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
                  color: WBColors.accentA(.16),
                  border: Border.all(color: WBColors.accentA(.4)),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  "+ Do'stlik",
                  style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: WBColors.accent),
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
        color: WBColors.accentA(.07),
        border: Border.all(color: WBColors.accentA(.22)),
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
                _metaLine(request.meta, request.user.provisional),
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
              child: StrokeGlyph.check(
                width: 13,
                height: 8,
                thickness: 3,
                color: WBColors.greenInk,
                offset: const Offset(0, -1.5),
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
                    color: friend.online ? WBColors.green : WBColors.textA(.5),
                  ),
                ),
              ],
            ),
          ),
          if (challengeable) ...[
            Pressable(
              onTap: () => onChallenge(friend),
              pressScale: .96,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
                decoration: BoxDecoration(gradient: wbAccentGradient, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  'Jang',
                  style: WBText.grotesk(size: 13.5, weight: FontWeight.w600, color: WBColors.accentInk),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Pressable(
              onTap: () => onTeamInvite(friend),
              pressScale: .96,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: WBColors.accentA(.1),
                  border: Border.all(color: WBColors.accentA(.3)),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.group_add_outlined, size: 18, color: WBColors.accent),
              ),
            ),
          ] else if (friend.inBattle)
            Pressable(
              onTap: () => onSpectate(friend),
              pressScale: .96,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                decoration: BoxDecoration(
                  color: WBColors.accentA(.1),
                  border: Border.all(color: WBColors.accentA(.3)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Kuzatish',
                  style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: WBColors.accent),
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
                'Oflayn',
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

/// Shown the very first time a player opens the friends tab, before they have
/// ever added anyone — distinct from "nobody online right now", which just
/// reuses the plain text line below it.
class _NoFriendsYet extends StatelessWidget {
  const _NoFriendsYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: WBColors.whiteA(.05),
              border: Border.all(color: WBColors.whiteA(.1)),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.person_add_alt_1_outlined, size: 22, color: WBColors.textA(.4)),
          ),
          const SizedBox(height: 14),
          Text(
            "Hali do'stlaringiz yo'q",
            style: WBText.grotesk(size: 16, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            "Yuqoridagi qidiruvdan raqiblaringizni toping va do'stlik so'rovi yuboring",
            textAlign: TextAlign.center,
            style: WBText.grotesk(size: 14, height: 1.5, color: WBColors.textA(.5)),
          ),
        ],
      ),
    );
  }
}
