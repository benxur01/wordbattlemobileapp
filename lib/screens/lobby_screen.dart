import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/duel_models.dart';
import '../api/models.dart';
import '../api/tournament_models.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/flame_badge.dart';
import '../widgets/primary_button.dart';
import '../widgets/provisional_badge.dart';
import '../widgets/streak_milestone_tracker.dart';

/// Top-tier AAA Mobile Game Lobby Screen for Word Battle.
///
/// Features rich layered cosmic ambient lighting, modern player profile header,
/// 3D battle energy portal CTA, gamified 7-day streak quest teaser, and action
/// tiles for Bot Battle, Friends Duel, and Solo Practice.
class LobbyScreen extends StatelessWidget {
  const LobbyScreen({
    super.key,
    required this.user,
    required this.onlineCount,
    required this.friendRequestCount,
    required this.friendsOnlineCount,
    required this.incoming,
    required this.onStartMatch,
    required this.onBotBattle,
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
    this.teamPartner,
    this.onStartTeamQueue,
    this.onCancelTeam,
    this.incomingTeam,
    this.onIncomingTeam,
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

  /// The other way into a duel: a bot, at a strength the player picks.
  final VoidCallback onBotBattle;

  final VoidCallback onFriends;
  final VoidCallback onPractice;
  final VoidCallback onIncoming;
  final VoidCallback onBoard;
  final VoidCallback onProfile;
  final VoidCallback? onOpenTournamentInvite;
  final VoidCallback? onStartTournamentMatch;
  final VoidCallback? onOpenTournamentBracket;

  /// The lobby's own entry point into the full paginated tournament list.
  final VoidCallback? onOpenTournamentsBrowse;

  /// The friend this player has formed a 2v2 team with.
  final UserDto? teamPartner;
  final VoidCallback? onStartTeamQueue;
  final VoidCallback? onCancelTeam;

  /// A team-duel invite waiting for action.
  final PendingTeamInvite? incomingTeam;
  final VoidCallback? onIncomingTeam;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. Clean Neutral Dark Background (no colored glows)
        Positioned.fill(
          child: ColoredBox(color: WBColors.bg),
        ),

        // 2. Main Foreground Content (Scrollable for zero overflow on any phone)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            children: [
              _buildHeader(context),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _buildHeroArenaCard(),
                      const SizedBox(height: 12),
                      _buildStreakQuestCard(context),
                      const SizedBox(height: 12),
                      _buildModeCards(),
                      if (incoming != null) ...[
                        const SizedBox(height: 12),
                        _buildIncomingInvite(),
                      ],
                      if (incomingTeam != null) ...[
                        const SizedBox(height: 12),
                        _buildIncomingTeamInvite(),
                      ],
                      if (teamPartner != null) ...[
                        const SizedBox(height: 12),
                        _TeamReadyBanner(
                          partner: teamPartner!,
                          onQueue: onStartTeamQueue,
                          onCancel: onCancelTeam,
                        ),
                      ],
                      if (tournamentInvite != null) ...[
                        const SizedBox(height: 12),
                        _TournamentInviteBanner(
                          invite: tournamentInvite!,
                          onTap: onOpenTournamentInvite,
                        ),
                      ] else if (tournamentMatchReady != null) ...[
                        const SizedBox(height: 12),
                        _TournamentReadyBanner(
                          prompt: tournamentMatchReady!,
                          onTap: onStartTournamentMatch,
                        ),
                      ] else if (activeTournament != null) ...[
                        const SizedBox(height: 12),
                        _TournamentDiscoveryBanner(
                          tournament: activeTournament!,
                          onTap: onOpenTournamentBracket,
                        ),
                      ],
                      _TournamentsBrowseLink(onTap: onOpenTournamentsBrowse),
                      const SizedBox(height: 85), // Padding for floating bottom nav
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 4. Floating Bottom Navigation Bar
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: BottomNav(
            active: WBTab.home,
            previous: previousTab,
            horizontalMargin: 36,
            friendRequestCount: friendRequestCount,
            onHome: () {},
            onFriends: onFriends,
            onBoard: onBoard,
            onProfile: onProfile,
          ),
        ),
      ],
    );
  }

  /// Upgraded Player Profile Header with glowing avatar frame, rank title, and stats pills.
  Widget _buildHeader(BuildContext context) {
    final label = user?.label ?? '…';
    final initial = user?.initial ?? '?';
    final rating = user?.rating ?? 0;
    final streak = user?.streakDays ?? 0;
    final city = user?.city;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Matte obsidian avatar with subtle presence indicator
          Pressable(
            onTap: onProfile,
            pressScale: 0.94,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: WBColors.bgSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: WBColors.hairlineStrong),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: WBText.grotesk(
                      size: 17,
                      weight: FontWeight.w700,
                      color: WBColors.text,
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: WBColors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: WBColors.bg,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // User Name & City / Rank
          Expanded(
            child: GestureDetector(
              onTap: onProfile,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WBText.grotesk(
                      size: 16,
                      weight: FontWeight.w700,
                      letterSpacing: -0.02,
                    ),
                  ),
                  const SizedBox(height: 1.5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (city != null) ...[
                        Icon(
                          Icons.location_on_outlined,
                          size: 11.5,
                          color: WBColors.textA(0.45),
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WBText.mono(
                              size: 11,
                              weight: FontWeight.w500,
                              color: WBColors.textA(0.5),
                            ),
                          ),
                        ),
                      ] else
                        Text(
                          'Jangchi',
                          style: WBText.mono(
                            size: 11,
                            weight: FontWeight.w500,
                            color: WBColors.textA(0.48),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Compact neutral stat chips
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rating chip (calm obsidian surface — no loud blue halo)
              _StatChip(
                color: WBColors.text,
                bg: WBColors.bgSurface,
                border: WBColors.hairline,
                icon: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: WBColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  transform: Matrix4.rotationZ(math.pi / 4),
                  transformAlignment: Alignment.center,
                ),
                value: '$rating',
                trailing: (user?.provisional ?? false) ? const ProvisionalBadge(size: 8.5) : null,
                onTap: onProfile,
              ),
              const SizedBox(width: 7),
              // Streak Flame Badge (calm obsidian surface)
              _StatChip(
                color: WBColors.text,
                bg: WBColors.bgSurface,
                border: (streak > 0 && streak % 7 == 0)
                    ? WBColors.amber.withValues(alpha: 0.45)
                    : WBColors.hairline,
                icon: FlameIcon(
                  width: 12.5,
                  height: 14.5,
                  tier: StreakFlameTier.fromDays(streak),
                ),
                value: '$streak',
                onTap: () => StreakMilestoneTracker.show(
                  context,
                  streakDays: streak,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tactile Hero Arena Card unifying live online presence and primary 1v1 CTA.
  Widget _buildHeroArenaCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: WBColors.bgSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: WBColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: WBColors.bgElevated,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: WBColors.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6.5,
                      height: 6.5,
                      decoration: BoxDecoration(
                        color: WBColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ONLAYN · $onlineCount',
                      style: WBText.mono(
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: WBColors.textA(0.72),
                        letterSpacing: 0.04,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '1v1 TEZKOR DUEL',
                style: WBText.mono(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: WBColors.textA(0.42),
                  letterSpacing: 0.05,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "So'z jangiga kiring",
            style: WBText.grotesk(
              size: 22,
              weight: FontWeight.w700,
              color: WBColors.text,
              letterSpacing: -0.025,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Teng darajali raqib bilan jonli 15 soniyali navbat',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WBText.grotesk(
              size: 13,
              color: WBColors.textA(0.54),
            ),
          ),
          const SizedBox(height: 18),
          Pressable(
            onTap: onStartMatch,
            pressScale: 0.975,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: wbCtaGradient,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
                boxShadow: [
                  BoxShadow(
                    color: WBColors.ctaLip,
                    offset: const Offset(0, 3),
                    blurRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    color: WBColors.ctaInk,
                    size: 20,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'JANG BOSHLASH',
                    style: WBText.grotesk(
                      size: 15,
                      weight: FontWeight.w700,
                      color: WBColors.ctaInk,
                      letterSpacing: 0.03,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Restrained 7-Day Streak & Milestone Quest Card.
  Widget _buildStreakQuestCard(BuildContext context) {
    final streak = user?.streakDays ?? 0;
    final progressInTier = streak > 0 ? (streak % 7 == 0 ? 7 : streak % 7) : 0;

    return Pressable(
      onTap: () => StreakMilestoneTracker.show(
        context,
        streakDays: streak,
      ),
      pressScale: 0.98,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: WBColors.bgSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WBColors.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: WBColors.bgElevated,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: WBColors.hairline),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.local_fire_department_rounded,
                color: WBColors.flameTop,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '7 KUNLIK SERIYA',
                        style: WBText.mono(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: WBColors.textA(0.55),
                          letterSpacing: 0.04,
                        ),
                      ),
                      Text(
                        '$progressInTier / 7 KUN',
                        style: WBText.mono(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: WBColors.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(7, (i) {
                      final isDone = i < progressInTier;
                      final isRewardDay = i == 6;
                      return Expanded(
                        child: Container(
                          height: 4.5,
                          margin: EdgeInsets.only(right: i < 6 ? 4 : 0),
                          decoration: BoxDecoration(
                            color: isDone
                                ? (isRewardDay ? WBColors.amber : WBColors.flameTop)
                                : WBColors.bgPressed,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: WBColors.textA(0.34),
            ),
          ],
        ),
      ),
    );
  }

  /// Modern Game Mode Cards (Bot Battle, Friends Duel, Solo Practice).
  Widget _buildModeCards() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Bot Battle Action Tile (Full Width Matte Card)
        Pressable(
          onTap: onBotBattle,
          hoverColor: WBColors.bgPressed,
          pressScale: 0.98,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: WBColors.bgSurface,
              border: Border.all(color: WBColors.hairline),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: WBColors.bgElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WBColors.hairline),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.smart_toy_rounded,
                    size: 20,
                    color: WBColors.amber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Bot bilan jang',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WBText.grotesk(
                          size: 15,
                          weight: FontWeight.w700,
                          color: WBColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Sun'iy intellekt darajasini tanlang",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WBText.grotesk(
                          size: 12,
                          color: WBColors.textA(0.52),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: WBColors.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: WBColors.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tanlash',
                        style: WBText.grotesk(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: WBColors.textA(0.8),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: WBColors.textA(0.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 2. Split Row: Friends Duel & Solo Practice
        Row(
          children: [
            Expanded(
              child: _SplitModeCard(
                icon: Icons.people_alt_rounded,
                iconColor: WBColors.green,
                title: "Do'stlar",
                subtitleLeading: Container(
                  width: 5.5,
                  height: 5.5,
                  decoration: BoxDecoration(
                    color: WBColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                subtitle: '$friendsOnlineCount onlayn',
                onTap: onFriends,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SplitModeCard(
                icon: Icons.menu_book_rounded,
                iconColor: WBColors.indigoText,
                title: 'Mashq',
                subtitle: 'Solo rejim',
                onTap: onPractice,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Incoming 1v1 Challenge Banner.
  Widget _buildIncomingInvite() {
    return _LobbyBannerCard(
      onTap: onIncoming,
      avatar: _BannerAvatar.initial(incoming!.user.initial, accent: WBColors.green),
      title: '${incoming!.user.label} seni chaqirmoqda',
      subtitle: "do'stlik jangi · javob ber",
      trailing: _BannerActionPill(
        label: "Ko'rish",
        bg: WBColors.green,
        fg: WBColors.greenInk,
      ),
    );
  }

  /// Incoming 2v2 Team Challenge Banner.
  Widget _buildIncomingTeamInvite() {
    return _LobbyBannerCard(
      onTap: onIncomingTeam,
      avatar: _BannerAvatar.initial(incomingTeam!.user.initial, accent: WBColors.cta),
      title: '${incomingTeam!.user.label} jamoaga taklif qilmoqda',
      subtitle: '2v2 jamoa taklifi · javob ber',
      trailing: _BannerActionPill(
        label: "Ko'rish",
        bg: WBColors.cta,
        fg: WBColors.ctaInk,
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
    this.trailing,
    this.onTap,
  });
  final Color color;
  final Color bg;
  final Color border;
  final Widget icon;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(
            value,
            style: WBText.mono(size: 13.5, weight: FontWeight.w700, color: color),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 5),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return chip;
    return Pressable(
      onTap: onTap,
      pressScale: 0.95,
      borderRadius: BorderRadius.circular(12),
      child: chip,
    );
  }
}

class _SplitModeCard extends StatelessWidget {
  const _SplitModeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.subtitleLeading,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? subtitleLeading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      hoverColor: WBColors.bgPressed,
      pressScale: 0.975,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        decoration: BoxDecoration(
          color: WBColors.bgSurface,
          border: Border.all(color: WBColors.hairline),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: WBColors.bgElevated,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: WBColors.hairline),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WBText.grotesk(
                      size: 14.5,
                      weight: FontWeight.w700,
                      color: WBColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (subtitleLeading != null) ...[
                        subtitleLeading!,
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WBText.mono(
                            size: 11,
                            weight: FontWeight.w500,
                            color: WBColors.textA(0.52),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LobbyBannerCard extends StatelessWidget {
  const _LobbyBannerCard({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.extraLine,
    this.onTap,
  });

  final Widget avatar;
  final String title;
  final String subtitle;
  final String? extraLine;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WBColors.bgSurface,
        border: Border.all(color: WBColors.hairline),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 13.5, weight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 11.5, color: WBColors.textA(.5)),
                ),
                if (extraLine != null)
                  Text(
                    extraLine!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WBText.grotesk(size: 11.5, color: WBColors.textA(.42)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );

    if (onTap == null) return content;
    return Pressable(
      onTap: onTap,
      hoverColor: WBColors.bgPressed,
      pressScale: 0.98,
      borderRadius: BorderRadius.circular(18),
      child: content,
    );
  }
}

class _BannerAvatar extends StatelessWidget {
  const _BannerAvatar._({required this.child});

  factory _BannerAvatar.initial(String text, {required Color accent}) => _BannerAvatar._(
        child: Text(
          text,
          style: WBText.grotesk(size: 15, weight: FontWeight.w700, color: accent),
        ),
      );

  factory _BannerAvatar.icon(IconData icon, {required Color accent}) => _BannerAvatar._(
        child: Icon(icon, size: 18, color: accent),
      );

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: WBColors.bgElevated,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: WBColors.hairline),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _BannerActionPill extends StatelessWidget {
  const _BannerActionPill({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        label,
        style: WBText.grotesk(size: 12.5, weight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// "You've formed a 2v2 team" banner.
class _TeamReadyBanner extends StatelessWidget {
  const _TeamReadyBanner({required this.partner, required this.onQueue, required this.onCancel});

  final UserDto partner;
  final VoidCallback? onQueue;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return _LobbyBannerCard(
      avatar: _BannerAvatar.initial(partner.initial, accent: WBColors.cta),
      title: '${partner.label} bilan jamoa tayyor',
      subtitle: '2v2 raqib jamoa qidirasiz',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pressable(
            onTap: onCancel,
            hoverColor: WBColors.bgPressed,
            borderRadius: BorderRadius.circular(10),
            semanticLabel: 'Jamoani bekor qilish',
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WBColors.bgElevated,
                border: Border.all(color: WBColors.hairline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('×', style: WBText.grotesk(size: 16, color: WBColors.textA(.55))),
            ),
          ),
          const SizedBox(width: 7),
          Pressable(
            onTap: onQueue,
            pressScale: .96,
            borderRadius: BorderRadius.circular(10),
            child: _BannerActionPill(label: 'Navbat', bg: WBColors.cta, fg: WBColors.ctaInk),
          ),
        ],
      ),
    );
  }
}

/// "You've been invited to a tournament" banner.
class _TournamentInviteBanner extends StatelessWidget {
  const _TournamentInviteBanner({required this.invite, required this.onTap});

  final TournamentInvite invite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _LobbyBannerCard(
      onTap: onTap,
      avatar: _BannerAvatar.icon(Icons.emoji_events_outlined, accent: WBColors.amber),
      title: invite.name,
      subtitle: invite.isTeam
          ? '2v2 turnir taklifi · ${invite.size} jamoa'
          : "turnir taklifi · ${invite.size} o'yinchi",
      trailing: _BannerActionPill(label: "Ko'rish", bg: WBColors.cta, fg: WBColors.ctaInk),
    );
  }
}

/// "Your tournament match is ready" banner.
class _TournamentReadyBanner extends StatelessWidget {
  const _TournamentReadyBanner({required this.prompt, required this.onTap});

  final TournamentMatchPrompt prompt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final opponent = prompt.opponent;
    final opponentPartner = prompt.opponentPartner;
    final partner = prompt.partner;
    final opponentLabel = opponent == null
        ? null
        : opponentPartner == null
            ? opponent.label
            : '${opponent.label} + ${opponentPartner.label}';
    return _LobbyBannerCard(
      onTap: onTap,
      avatar: _BannerAvatar.initial(opponent?.initial ?? '?', accent: WBColors.green),
      title: opponentLabel == null ? 'Turnir jangi tayyor' : '$opponentLabel bilan turnir jangi tayyor',
      subtitle: '${prompt.tournamentName} · ${prompt.roundLabel}',
      extraLine: partner == null ? null : 'juftingiz: ${partner.label}',
      trailing: _BannerActionPill(label: 'Boshlash', bg: WBColors.green, fg: WBColors.greenInk),
    );
  }
}

/// "A tournament is being played" spectator banner.
class _TournamentDiscoveryBanner extends StatelessWidget {
  const _TournamentDiscoveryBanner({required this.tournament, required this.onTap});

  final TournamentSummary tournament;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      hoverColor: WBColors.bgPressed,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: WBColors.bgSurface,
          border: Border.all(color: WBColors.hairline),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined, size: 17, color: WBColors.textA(.55)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${tournament.name} · jonli bracket',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WBText.grotesk(size: 12.5, weight: FontWeight.w500, color: WBColors.textA(.76)),
              ),
            ),
            Text(
              "Ko'rish",
              style: WBText.grotesk(size: 12, weight: FontWeight.w600, color: WBColors.textA(.55)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "See every tournament" link button.
class _TournamentsBrowseLink extends StatelessWidget {
  const _TournamentsBrowseLink({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Pressable(
        onTap: onTap,
        hoverColor: WBColors.bgPressed,
        pressScale: 0.985,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: WBColors.bgSurface,
            border: Border.all(color: WBColors.hairline),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.emoji_events_outlined, size: 18, color: WBColors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Barchasini ko'rish",
                  style: WBText.grotesk(size: 14, weight: FontWeight.w600, color: WBColors.text),
                ),
              ),
              Text(
                'Turnirlar',
                style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(.44)),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: WBColors.textA(.38)),
            ],
          ),
        ),
      ),
    );
  }
}
