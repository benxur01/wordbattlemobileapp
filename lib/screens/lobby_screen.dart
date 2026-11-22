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
                      const SizedBox(height: 4),
                      _buildOnlineCapsule(),
                      const SizedBox(height: 16),
                      _buildBattlePortal(),
                      const SizedBox(height: 20),
                      _buildStreakQuestCard(context),
                      const SizedBox(height: 14),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: WBColors.whiteA(0.04),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: WBColors.whiteA(0.09),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar with neon rim and online beacon
          Pressable(
            onTap: onProfile,
            pressScale: 0.94,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: wbPurpleGradient,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: WBColors.purpleText.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: WBColors.purple.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: WBText.grotesk(
                      size: 18,
                      weight: FontWeight.w700,
                      color: WBColors.purpleText,
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: WBColors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: WBColors.bgDeep,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: WBColors.green.withValues(alpha: 0.8),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // User Name & Location / Rank
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
                      size: 15.5,
                      weight: FontWeight.w700,
                      letterSpacing: -0.01,
                    ),
                  ),
                  const SizedBox(height: 2),
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
                              color: WBColors.textA(0.55),
                            ),
                          ),
                        ),
                      ] else
                        Text(
                          'Jangchi',
                          style: WBText.mono(
                            size: 11,
                            weight: FontWeight.w500,
                            color: WBColors.accent.withValues(alpha: 0.85),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Stat Badges
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rating Badge
              _StatChip(
                color: WBColors.blueText,
                bg: WBColors.blueDark.withValues(alpha: 0.45),
                border: WBColors.blue.withValues(alpha: 0.5),
                icon: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: WBColors.accent,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: WBColors.accent.withValues(alpha: 0.75),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  transform: Matrix4.rotationZ(math.pi / 4),
                  transformAlignment: Alignment.center,
                ),
                value: '$rating',
                onTap: onProfile,
              ),
              if (user?.provisional ?? false) ...[
                const SizedBox(width: 5),
                ProvisionalBadge(size: 9),
              ],
              const SizedBox(width: 7),
              // Streak Flame Badge
              _StatChip(
                color: WBColors.flameText,
                bg: (streak > 0 && streak % 7 == 0)
                    ? WBColors.amber.withValues(alpha: 0.2)
                    : WBColors.flameTop.withValues(alpha: 0.12),
                border: (streak > 0 && streak % 7 == 0)
                    ? WBColors.amber
                    : WBColors.flameTop.withValues(alpha: 0.38),
                icon: FlameIcon(
                  width: 13,
                  height: 15,
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

  /// Live Online Players Capsule Pill.
  Widget _buildOnlineCapsule() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
      decoration: BoxDecoration(
        color: WBColors.whiteA(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: WBColors.whiteA(0.09),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: WBColors.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: WBColors.green.withValues(alpha: 0.8),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'ONLAYN · $onlineCount O\'YINCHI',
            style: WBText.mono(
              size: 10.5,
              weight: FontWeight.w600,
              color: WBColors.textA(0.58),
              letterSpacing: 0.05,
            ),
          ),
        ],
      ),
    );
  }

  /// 3D Energy Battle Portal CTA Button ("JANG BOSHLASH").
  Widget _buildBattlePortal() {
    return Pressable(
      onTap: onStartMatch,
      pressScale: 0.96,
      child: Container(
        width: 224,
        height: 224,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.25, -0.3),
            radius: 0.95,
            colors: [
              Color(0xFF00F5D4), // Vibrant electric cyan
              Color(0xFF00B4D8), // Electric teal
              Color(0xFF0077B6), // Deep oceanic sapphire
              Color(0xFF03045E), // Cosmic dark base
            ],
            stops: [0.0, 0.4, 0.78, 1.0],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.48),
            width: 3.5,
          ),
          boxShadow: [
            // Deep ambient drop shadow
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
            // Soft localized rim glow (does not bleed into background)
            BoxShadow(
              color: const Color(0xFF00F5D4).withValues(alpha: 0.28),
              blurRadius: 18,
              spreadRadius: 0,
            ),
          ],
        ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Concentric specular glass ring
              Container(
                width: 196,
                height: 196,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 1.5,
                  ),
                ),
              ),
              // Button content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 3D Duel Emblem with specular sheen
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(bottom: 9),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.95),
                          Colors.white.withValues(alpha: 0.6),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    transform: Matrix4.rotationZ(math.pi / 4),
                    transformAlignment: Alignment.center,
                    child: Center(
                      child: Transform.rotate(
                        angle: -math.pi / 4,
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Color(0xFF03045E),
                          size: 25,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'JANG BOSHLASH',
                    textAlign: TextAlign.center,
                    style: WBText.grotesk(
                      size: 22,
                      weight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.01,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00F5D4),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '1v1 TEZKOR DUEL',
                          style: WBText.mono(
                            size: 10.5,
                            weight: FontWeight.w600,
                            color: const Color(0xFFE0FAFF),
                            letterSpacing: 0.04,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

  /// Gamified 7-Day Streak & Milestone Quest Teaser Card.
  Widget _buildStreakQuestCard(BuildContext context) {
    final streak = user?.streakDays ?? 0;
    final progressInTier = streak > 0 ? (streak % 7 == 0 ? 7 : streak % 7) : 0;

    return Pressable(
      onTap: () => StreakMilestoneTracker.show(
        context,
        streakDays: streak,
      ),
      pressScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              WBColors.amber.withValues(alpha: 0.12),
              WBColors.flameTop.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: WBColors.amber.withValues(alpha: 0.28),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: wbFlameGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: WBColors.flameTop.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
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
                          size: 10,
                          weight: FontWeight.w700,
                          color: WBColors.amber,
                          letterSpacing: 0.04,
                        ),
                      ),
                      Text(
                        '$progressInTier / 7 KUN',
                        style: WBText.mono(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: WBColors.textA(0.85),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // 7-day dot/step progress bar
                  Row(
                    children: List.generate(7, (i) {
                      final isDone = i < progressInTier;
                      final isRewardDay = i == 6;
                      return Expanded(
                        child: Container(
                          height: 5,
                          margin: EdgeInsets.only(right: i < 6 ? 4 : 0),
                          decoration: BoxDecoration(
                            color: isDone
                                ? (isRewardDay ? WBColors.amber : WBColors.flameTop)
                                : WBColors.whiteA(0.1),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: isDone
                                ? [
                                    BoxShadow(
                                      color: (isRewardDay ? WBColors.amber : WBColors.flameTop)
                                          .withValues(alpha: 0.6),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
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
              Icons.card_giftcard_rounded,
              size: 20,
              color: WBColors.amber,
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
        // 1. Bot Battle Action Tile (Full Width Hero Card)
        Pressable(
          onTap: onBotBattle,
          hoverColor: WBColors.whiteA(0.08),
          pressScale: 0.98,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: WBColors.whiteA(0.045),
              border: Border.all(
                color: WBColors.amber.withValues(alpha: 0.25),
                width: 1.2,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: wbAmberGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: WBColors.amber.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    size: 20,
                    color: Colors.black87,
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
                        style: WBText.grotesk(
                          size: 14.5,
                          weight: FontWeight.w700,
                          color: WBColors.text,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      Text(
                        'Sun\'iy intellekt · kuch darajasini tanlang',
                        style: WBText.grotesk(
                          size: 11.5,
                          weight: FontWeight.w400,
                          color: WBColors.textA(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: WBColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: WBColors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Tanlash',
                    style: WBText.grotesk(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: WBColors.amber,
                    ),
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
            // Friends Duel Card
            Expanded(
              child: Pressable(
                onTap: onFriends,
                hoverColor: WBColors.whiteA(0.08),
                pressScale: 0.97,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: WBColors.whiteA(0.045),
                    border: Border.all(
                      color: WBColors.green.withValues(alpha: 0.25),
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: wbTealGradient,
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                              color: WBColors.green.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.people_alt_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Do\'stlar',
                              style: WBText.grotesk(
                                size: 14,
                                weight: FontWeight.w700,
                                color: WBColors.text,
                              ),
                            ),
                            const SizedBox(height: 1.5),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: WBColors.green,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: WBColors.green.withValues(alpha: 0.8),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '$friendsOnlineCount onlayn',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: WBText.mono(
                                      size: 11,
                                      weight: FontWeight.w500,
                                      color: WBColors.textA(0.6),
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
              ),
            ),
            const SizedBox(width: 10),
            // Solo Practice Card
            Expanded(
              child: Pressable(
                onTap: onPractice,
                hoverColor: WBColors.whiteA(0.08),
                pressScale: 0.97,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: WBColors.whiteA(0.045),
                    border: Border.all(
                      color: WBColors.indigo.withValues(alpha: 0.25),
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: wbIndigoGradient,
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                              color: WBColors.indigo.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.psychology_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Mashq',
                              style: WBText.grotesk(
                                size: 14,
                                weight: FontWeight.w700,
                                color: WBColors.text,
                              ),
                            ),
                            const SizedBox(height: 1.5),
                            Text(
                              'Solo rejim',
                              style: WBText.mono(
                                size: 11,
                                weight: FontWeight.w500,
                                color: WBColors.textA(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Incoming 1v1 Challenge Banner.
  Widget _buildIncomingInvite() {
    return Pressable(
      onTap: onIncoming,
      hoverColor: WBColors.greenA(.14),
      borderRadius: BorderRadius.circular(20),
      child: Container(
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
    );
  }

  /// Incoming 2v2 Team Challenge Banner.
  Widget _buildIncomingTeamInvite() {
    return Pressable(
      onTap: onIncomingTeam,
      hoverColor: WBColors.accentA(.14),
      borderRadius: BorderRadius.circular(20),
      child: Container(
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
              decoration: BoxDecoration(
                gradient: wbTealGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                incomingTeam!.user.initial,
                style: WBText.grotesk(size: 15, weight: FontWeight.w700, color: WBColors.tealText),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${incomingTeam!.user.label} jamoaga taklif qilmoqda',
                    style: WBText.grotesk(size: 13.5, weight: FontWeight.w600),
                  ),
                  Text(
                    "2v2 jamoa taklifi · javob ber",
                    style: WBText.grotesk(size: 11.5, color: WBColors.textA(.5)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: WBColors.accent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                "Ko'rish",
                style: WBText.grotesk(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: WBColors.accentInk,
                ),
              ),
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
    this.onTap,
  });
  final Color color;
  final Color bg;
  final Color border;
  final Widget icon;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
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

    if (onTap == null) return chip;
    return Pressable(
      onTap: onTap,
      pressScale: 0.95,
      borderRadius: BorderRadius.circular(13),
      child: chip,
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
    return Container(
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
            decoration: BoxDecoration(gradient: wbTealGradient, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(
              partner.initial,
              style: WBText.grotesk(size: 15, weight: FontWeight.w700, color: WBColors.tealText),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${partner.label} bilan jamoa tayyor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 13.5, weight: FontWeight.w600),
                ),
                Text(
                  '2v2 raqib jamoa qidirasiz',
                  style: WBText.grotesk(size: 11.5, color: WBColors.textA(.5)),
                ),
              ],
            ),
          ),
          Pressable(
            onTap: onCancel,
            hoverColor: WBColors.whiteA(.08),
            borderRadius: BorderRadius.circular(11),
            semanticLabel: 'Jamoani bekor qilish',
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.12)),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text('×', style: WBText.grotesk(size: 16, color: WBColors.textA(.5))),
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: onQueue,
            pressScale: .96,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(color: WBColors.accent, borderRadius: BorderRadius.circular(11)),
              child: Text(
                'Navbat',
                style: WBText.grotesk(size: 12.5, weight: FontWeight.w600, color: WBColors.accentInk),
              ),
            ),
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
    return Pressable(
      onTap: onTap,
      hoverColor: WBColors.accentA(.14),
      borderRadius: BorderRadius.circular(20),
      child: Container(
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
                    invite.isTeam
                        ? "2v2 turnir taklifi · ${invite.size} jamoa"
                        : "turnir taklifi · ${invite.size} o'yinchi",
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
    return Pressable(
      onTap: onTap,
      hoverColor: WBColors.greenA(.14),
      borderRadius: BorderRadius.circular(20),
      child: Container(
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
                    opponentLabel == null ? 'Turnir jangi tayyor' : '$opponentLabel bilan turnir jangi tayyor',
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
                  if (partner != null)
                    Text(
                      'juftingiz: ${partner.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.grotesk(size: 11.5, color: WBColors.textA(.4)),
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

/// "A tournament is being played" spectator banner.
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

/// "See every tournament" link button.
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
