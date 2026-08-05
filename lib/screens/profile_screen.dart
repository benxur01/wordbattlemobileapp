import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme.dart';
import '../api/models.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/dashed_border.dart';
import '../widgets/flame_badge.dart';
import '../widgets/spinner_ring.dart';

/// The player's own profile, entirely server-driven: stats, the 30-day rating
/// chart and which badges are unlocked.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.onHome,
    required this.onFriends,
    required this.onBoard,
    required this.friendRequestCount,
    this.previousTab,
  });

  /// Null while the request is in flight.
  final ProfileDto? profile;
  final VoidCallback onHome;
  final VoidCallback onFriends;
  final VoidCallback onBoard;
  final int friendRequestCount;

  /// Which tab the previous screen highlighted, so the bar can animate.
  final WBTab? previousTab;

  @override
  Widget build(BuildContext context) {
    final data = profile;
    if (data == null) {
      return Column(
        children: [
          const Expanded(
            child: Center(
              child: SpinnerRing(
                size: 26,
                trackColor: Color.fromRGBO(244, 243, 248, .15),
                activeColor: WBColors.amber,
                strokeWidth: 2.5,
              ),
            ),
          ),
          BottomNav(
            active: WBTab.profile,
            previous: previousTab,
            friendRequestCount: friendRequestCount,
            onHome: onHome,
            onFriends: onFriends,
            onBoard: onBoard,
            onProfile: () {},
          ),
        ],
      );
    }

    final user = data.user;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
            children: [
              Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: wbPurpleGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      user.initial,
                      style: WBText.grotesk(size: 24, weight: FontWeight.w700, color: WBColors.purpleText),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WBText.grotesk(size: 21, weight: FontWeight.w700),
                        ),
                        Text(
                          [
                            '${data.battles} jang',
                            if (user.city != null) user.city!,
                            '№${data.globalRank}',
                          ].where((part) => part.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5)),
                        ),
                      ],
                    ),
                  ),
                  // The row's `gap:14px` applies here too — without it the meta
                  // line runs straight into the rating column.
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${user.rating}',
                        style: WBText.mono(size: 24, weight: FontWeight.w700, color: WBColors.amber),
                      ),
                      Text(
                        '${data.weeklyDelta >= 0 ? '+' : ''}${data.weeklyDelta} hafta',
                        style: WBText.mono(
                          size: 11,
                          weight: FontWeight.w500,
                          color: data.weeklyDelta >= 0 ? WBColors.green : WBColors.redSoft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                decoration: BoxDecoration(
                  color: WBColors.whiteA(.045),
                  border: Border.all(color: WBColors.whiteA(.09)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Reyting o'sishi", style: WBText.grotesk(size: 13.5, weight: FontWeight.w600)),
                        Text(
                          '30 KUN',
                          style: WBText.mono(
                            size: 10.5,
                            weight: FontWeight.w500,
                            color: WBColors.textA(.4),
                            letterSpacing: .12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 96,
                      width: double.infinity,
                      child: data.ratingHistory.length < 2
                          ? Center(
                              child: Text(
                                "Bir nechta jangdan keyin grafik paydo bo'ladi",
                                style: WBText.grotesk(size: 12, color: WBColors.textA(.35)),
                              ),
                            )
                          : CustomPaint(painter: _RatingChartPainter(data.ratingHistory)),
                    ),
                    const SizedBox(height: 4),
                    if (data.ratingHistory.length >= 2)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _dayLabel(data.ratingHistory.first.at),
                            style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.35)),
                          ),
                          Text(
                            _dayLabel(data.ratingHistory.last.at),
                            style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.35)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // `grid-template-columns:1fr 1fr` with auto row height. A
              // GridView would need a fixed childAspectRatio, and any guess
              // clipped the numbers by a few pixels — these rows size to their
              // content the way the CSS grid does.
              Row(
                children: [
                  Expanded(
                    child: _StatCard(value: '${data.battles}', label: 'jang'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      value: '${data.winPercent}%',
                      label: 'yutuq',
                      color: WBColors.green,
                      tint: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(value: '${data.longestChain}', label: 'eng uzun zanjir'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      value: '${data.streakDays}',
                      label: 'kunlik streak',
                      color: WBColors.flameText,
                      tint: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Nishonlar', style: WBText.grotesk(size: 13.5, weight: FontWeight.w600)),
                  Text(
                    '${data.badges.where((b) => b.unlocked).length} / ${data.badges.length}',
                    style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.textA(.4)),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
                // The server says which badges are unlocked; the mark for each
                // one stays a client-side detail keyed by its code.
                children: [for (final badge in data.badges) _badgeTile(badge)],
              ),
            ],
          ),
        ),
        BottomNav(
          active: WBTab.profile,
          previous: previousTab,
          friendRequestCount: friendRequestCount,
          onHome: onHome,
          onFriends: onFriends,
          onBoard: onBoard,
          onProfile: () {},
        ),
      ],
    );
  }

  static String _dayLabel(DateTime at) {
    const months = [
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
    return '${at.day} ${months[at.month - 1]}';
  }

  /// Each earned badge has its own mark — a diamond, a flame, a ring and a
  /// rounded square — not four identical dots. Locked ones are a dashed tile.
  Widget _badgeTile(BadgeDto badge) {
    if (!badge.unlocked) return _Badge(label: badge.label, locked: true);

    return switch (badge.code) {
      'first_battle' || 'rating_1500' => _Badge(
        label: badge.label,
        color: WBColors.amber,
        bg: WBColors.amberA(.13),
        border: WBColors.amberA(.34),
        mark: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: WBColors.amber, borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
      'streak_7' || 'streak_30' => _Badge(
        label: badge.label,
        color: WBColors.flameText,
        bg: const Color.fromRGBO(255, 138, 60, .11),
        border: const Color.fromRGBO(255, 138, 60, .3),
        mark: const FlameIcon(width: 14, height: 19, animate: false),
      ),
      'wins_50' || 'friend_top' => _Badge(
        label: badge.label,
        color: WBColors.green,
        bg: WBColors.greenA(.1),
        border: WBColors.greenA(.28),
        mark: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: WBColors.green, width: 3),
          ),
        ),
      ),
      _ => _Badge(
        label: badge.label,
        color: WBColors.indigoText,
        bg: WBColors.indigoA(.1),
        border: WBColors.indigoA(.28),
        mark: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: WBColors.indigo, borderRadius: BorderRadius.circular(5)),
        ),
      ),
    };
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, this.color, this.tint = false});
  final String value;
  final String label;
  final Color? color;
  final bool tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: tint ? (color ?? WBColors.text).withValues(alpha: .08) : WBColors.whiteA(.045),
        border: Border.all(
          color: tint ? (color ?? WBColors.text).withValues(alpha: .24) : WBColors.whiteA(.09),
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: WBText.mono(size: 24, weight: FontWeight.w700, color: color ?? WBColors.text),
          ),
          const SizedBox(height: 3),
          Text(label, style: WBText.grotesk(size: 12, color: WBColors.textA(.5))),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    this.color = const Color.fromRGBO(244, 243, 248, .28),
    this.bg = const Color.fromRGBO(255, 255, 255, .03),
    this.border = const Color.fromRGBO(255, 255, 255, .12),
    this.mark,
    this.locked = false,
  });

  final String label;
  final Color color;
  final Color bg;
  final Color border;
  final Widget? mark;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        mark ??
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: WBColors.textA(.2), width: 2),
              ),
            ),
        const SizedBox(height: 5),
        Text(
          label,
          style: WBText.grotesk(size: 9, weight: FontWeight.w500, color: color),
        ),
      ],
    );

    if (locked) {
      return CustomPaint(
        painter: DashedBorderPainter(color: border, radius: 17),
        child: Container(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(17)),
          alignment: Alignment.center,
          child: content,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: content,
    );
  }
}

/// The 30-day rating line. Points are spread evenly across the width and
/// scaled to the min/max of the range, so a flat stretch stays readable instead
/// of collapsing onto the baseline.
class _RatingChartPainter extends CustomPainter {
  _RatingChartPainter(this.points);

  final List<RatingPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final ratings = points.map((p) => p.rating).toList();
    final lowest = ratings.reduce((a, b) => a < b ? a : b);
    final highest = ratings.reduce((a, b) => a > b ? a : b);
    // A completely flat line would divide by zero; give it a nominal range.
    final span = (highest - lowest) == 0 ? 40.0 : (highest - lowest).toDouble();
    final top = 8.0;
    final bottom = size.height - 8;

    final scaled = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = size.width * (i / (points.length - 1));
      final normalised = (points[i].rating - lowest) / span;
      scaled.add(Offset(x, bottom - normalised * (bottom - top)));
    }

    final fillPath = Path()..moveTo(scaled.first.dx, scaled.first.dy);
    for (final p in scaled.skip(1)) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [WBColors.amberA(.34), WBColors.amberA(0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final linePath = Path()..moveTo(scaled.first.dx, scaled.first.dy);
    for (final p in scaled.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = WBColors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(scaled.last, 4.5, Paint()..color = WBColors.amber);
  }

  @override
  bool shouldRepaint(covariant _RatingChartPainter oldDelegate) => oldDelegate.points != points;
}
