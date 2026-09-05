import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../api/tournament_models.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/flame_badge.dart';
import '../widgets/primary_button.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({
    super.key,
    required this.user,
    required this.onlineCount,
    required this.friendRequestCount,
    required this.friendsOnlineCount,
    required this.incoming,
    required this.onStartMatch,
    required this.onFriends,
    required this.onPractice,
    required this.onIncoming,
    required this.onBoard,
    required this.onProfile,
    this.tournamentInvite,
    this.tournamentMatchReady,
    this.activeTournament,
    this.onOpenTournamentInvite,
    this.onStartTournamentMatch,
    this.onOpenTournamentBracket,
    this.onOpenTournamentsBrowse,
    this.previousTab,
  });

  /// Null only in the moment between login and the first `hello` frame.
  final UserDto? user;
  final int onlineCount;
  final int friendRequestCount;
  final int friendsOnlineCount;

  /// A live challenge from a friend, shown as the green strip above the tab bar.
  final PendingInvite? incoming;

  /// A tournament invite waiting for Accept/Decline.
  final TournamentInvite? tournamentInvite;

  /// This player's own tournament match, filled and waiting for "Boshlash".
  final TournamentMatchPrompt? tournamentMatchReady;

  /// A tournament being played right now — the opt-in spectator card, shown
  /// only when neither of the two above applies.
  final TournamentSummary? activeTournament;

  /// Which tab the previous screen highlighted, so the bar can animate.
  final WBTab? previousTab;
  final VoidCallback onStartMatch;
  final VoidCallback onFriends;
  final VoidCallback onPractice;
  final VoidCallback onIncoming;
  final VoidCallback onBoard;
  final VoidCallback onProfile;
  final VoidCallback? onOpenTournamentInvite;
  final VoidCallback? onStartTournamentMatch;
  final VoidCallback? onOpenTournamentBracket;

  /// The lobby's own entry point into the full paginated tournament list —
  /// always reachable, whether or not any of the three banners above is
  /// showing.
  final VoidCallback? onOpenTournamentsBrowse;

  @override
  Widget build(BuildContext context) {
    final label = user?.label ?? '…';
    final initial = user?.initial ?? '?';
    final rating = user?.rating ?? 0;
    final streak = user?.streakDays ?? 0;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, .12),
          radius: 1,
          colors: [Color.fromRGBO(247, 183, 51, .13), Colors.transparent],
          stops: [0, .7],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: wbPurpleGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: WBText.grotesk(size: 17, weight: FontWeight.w700, color: WBColors.purpleText),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: WBText.grotesk(size: 15, weight: FontWeight.w600)),
                        if (user?.city != null)
                          Text(
                            user!.city!,
                            style: WBText.mono(
                              size: 11.5,
                              weight: FontWeight.w500,
                              color: WBColors.textA(.45),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    _StatChip(
                      color: WBColors.blue,
                      bg: WBColors.blueA(.1),
                      border: WBColors.blueA(.28),
                      icon: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: WBColors.blue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        transform: Matrix4.rotationZ(math.pi / 4),
                        // Without an explicit alignment the box turns around its
                        // top-left corner and the diamond drifts off-centre.
                        transformAlignment: Alignment.center,
                      ),
                      value: '$rating',
                    ),
                    const SizedBox(width: 7),
                    _StatChip(
                      color: WBColors.flameText,
                      bg: const Color.fromRGBO(255, 92, 60, .09),
                      border: const Color.fromRGBO(255, 120, 60, .26),
                      icon: const FlameIcon(),
                      value: '$streak',
                    ),
                  ],
                ),
              ],
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -24),
                    child: Text(
                      'HOZIR ONLAYN · $onlineCount',
                      style: WBText.mono(
                        size: 11,
                        weight: FontWeight.w500,
                        color: WBColors.textA(.35),
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Pressable(
                    onTap: onStartMatch,
                    pressScale: .97,
                    child: Container(
                      width: 232,
                      height: 232,
                      decoration: const BoxDecoration(gradient: wbAccentGradient, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // The margin has to sit outside the rotation: on the
                          // Container it turns with the diamond and the gap
                          // ends up pointing 45° off to the side.
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Transform.rotate(
                              angle: math.pi / 4,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: WBColors.accentInk.withValues(alpha: .75),
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Text(
                            'JANG BOSHLASH',
                            style: WBText.grotesk(
                              size: 24,
                              weight: FontWeight.w700,
                              color: WBColors.accentInk,
                              letterSpacing: -.01,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "~8 s kutish",
                            style: WBText.mono(
                              size: 12,
                              weight: FontWeight.w500,
                              color: WBColors.accentInk.withValues(alpha: .62),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Pressable(
                        onTap: onFriends,
                        hoverColor: WBColors.whiteA(.08),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                          decoration: BoxDecoration(
                            color: WBColors.whiteA(.05),
                            border: Border.all(color: WBColors.whiteA(.1)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: WBColors.green,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: WBColors.greenA(.8), blurRadius: 8)],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Do'stlar · $friendsOnlineCount onlayn",
                                style: WBText.grotesk(
                                  size: 14.5,
                                  weight: FontWeight.w500,
                                  color: WBColors.textA(.82),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Pressable(
                        onTap: onPractice,
                        hoverColor: WBColors.whiteA(.08),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                          decoration: BoxDecoration(
                            color: WBColors.whiteA(.05),
                            border: Border.all(color: WBColors.whiteA(.1)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: WBColors.indigo,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Mashq',
                                style: WBText.grotesk(
                                  size: 14.5,
                                  weight: FontWeight.w500,
                                  color: WBColors.textA(.82),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (incoming != null)
              Pressable(
                onTap: onIncoming,
                hoverColor: WBColors.greenA(.14),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: WBColors.greenA(.09),
                    border: Border.all(color: WBColors.greenA(.28)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: wbTealGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          incoming!.user.initial,
                          style: WBText.grotesk(size: 15, weight: FontWeight.w700, color: WBColors.tealText),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${incoming!.user.label} seni chaqirmoqda',
                              style: WBText.grotesk(size: 13.5, weight: FontWeight.w600),
                            ),
                            Text(
                              "do'stlik jangi · javob ber",
                              style: WBText.grotesk(size: 11.5, color: WBColors.textA(.5)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: WBColors.green,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          "Ko'rish",
                          style: WBText.grotesk(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: WBColors.greenInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (tournamentInvite != null)
              _TournamentInviteBanner(invite: tournamentInvite!, onTap: onOpenTournamentInvite)
            else if (tournamentMatchReady != null)
              _TournamentReadyBanner(prompt: tournamentMatchReady!, onTap: onStartTournamentMatch)
            else if (activeTournament != null)
              _TournamentDiscoveryBanner(tournament: activeTournament!, onTap: onOpenTournamentBracket),
            _TournamentsBrowseLink(onTap: onOpenTournamentsBrowse),
            BottomNav(
              active: WBTab.home,
              previous: previousTab,
              // The lobby column is already padded 22px, and the design only
              // adds 14px more here so the bar lines up with the other screens'
              // 36px edge margin.
              horizontalMargin: 14,
              friendRequestCount: friendRequestCount,
              onHome: () {},
              onFriends: onFriends,
              onBoard: onBoard,
              onProfile: onProfile,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.color,
    required this.bg,
    required this.border,
    required this.icon,
    required this.value,
  });
  final Color color;
  final Color bg;
  final Color border;
  final Widget icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 6),
          Text(
            value,
            style: WBText.mono(size: 14, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// "You've been invited to a tournament" — the same weight as the friend
/// challenge strip above, in the app's accent colour rather than green so the
/// two are never mistaken for each other.
class _TournamentInviteBanner extends StatelessWidget {
  const _TournamentInviteBanner({required this.invite, required this.onTap});

  final TournamentInvite invite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      hoverColor: WBColors.accentA(.14),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: WBColors.accentA(.09),
          border: Border.all(color: WBColors.accentA(.28)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(gradient: wbAccentGradient, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Icon(Icons.emoji_events_outlined, size: 18, color: WBColors.accentInk),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invite.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WBText.grotesk(size: 13.5, weight: FontWeight.w600),
                  ),
                  Text(
                    "turnir taklifi · ${invite.size} o'yinchi",
                    style: WBText.grotesk(size: 11.5, color: WBColors.textA(.5)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(color: WBColors.accent, borderRadius: BorderRadius.circular(11)),
              child: Text(
                "Ko'rish",
                style: WBText.grotesk(size: 12.5, weight: FontWeight.w600, color: WBColors.accentInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Your tournament match is ready" — tapping sends the start frame directly,
/// the same one-tap shape as accepting a friend's challenge.
class _TournamentReadyBanner extends StatelessWidget {
  const _TournamentReadyBanner({required this.prompt, required this.onTap});

  final TournamentMatchPrompt prompt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final opponent = prompt.opponent;
    return Pressable(
      onTap: onTap,
      hoverColor: WBColors.greenA(.14),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: WBColors.greenA(.09),
          border: Border.all(color: WBColors.greenA(.28)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(gradient: wbTealGradient, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text(
                opponent?.initial ?? '?',
                style: WBText.grotesk(size: 15, weight: FontWeight.w700, color: WBColors.tealText),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opponent == null ? 'Turnir jangi tayyor' : '${opponent.label} bilan turnir jangi tayyor',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WBText.grotesk(size: 13.5, weight: FontWeight.w600),
                  ),
                  Text(
                    '${prompt.tournamentName} · ${prompt.roundLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WBText.grotesk(size: 11.5, color: WBColors.textA(.5)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(color: WBColors.green, borderRadius: BorderRadius.circular(11)),
              child: Text(
                'Boshlash',
                style: WBText.grotesk(size: 12.5, weight: FontWeight.w600, color: WBColors.greenInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "A tournament is being played" — the opt-in spectator entry point, deliber-
/// ately quieter than the two banners above: nobody has to look at this.
class _TournamentDiscoveryBanner extends StatelessWidget {
  const _TournamentDiscoveryBanner({required this.tournament, required this.onTap});

  final TournamentSummary tournament;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      hoverColor: WBColors.whiteA(.08),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: WBColors.whiteA(.04),
          border: Border.all(color: WBColors.whiteA(.09)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined, size: 18, color: WBColors.textA(.5)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${tournament.name} · jonli bracket',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WBText.grotesk(size: 12.5, weight: FontWeight.w500, color: WBColors.textA(.7)),
              ),
            ),
            Text(
              "Ko'rish",
              style: WBText.grotesk(size: 12.5, weight: FontWeight.w600, color: WBColors.textA(.55)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "See every tournament" — unlike the discovery banner above it, it does not
/// depend on one being live to be worth tapping, since the browse list it
/// opens also shows every finished bracket and every one still open to join.
class _TournamentsBrowseLink extends StatelessWidget {
  const _TournamentsBrowseLink({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Pressable(
        onTap: onTap,
        hoverColor: WBColors.whiteA(.06),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events_outlined, size: 18, color: WBColors.accent),
              const SizedBox(width: 10),
              Text(
                'Barchasini ko\'rish',
                style: WBText.grotesk(size: 14, weight: FontWeight.w600, color: WBColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
