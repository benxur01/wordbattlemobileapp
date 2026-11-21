import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sound_effects.dart';
import '../theme.dart';
import 'animated_flame.dart';
import 'primary_button.dart';

/// Interactive modal sheet and gamification view displaying the player's
/// daily streak fire, 7-day milestone progression nodes, reward chest,
/// and streak freeze status.
class StreakMilestoneTracker extends StatefulWidget {
  const StreakMilestoneTracker({
    super.key,
    required this.streakDays,
    this.hasFreeze = false,
    this.onClaim,
    this.onClose,
  });

  /// Total consecutive days the user has maintained their streak.
  final int streakDays;

  /// Whether the user has an active streak freeze shield.
  final bool hasFreeze;

  /// Callback when the 7-day milestone reward is claimed.
  final VoidCallback? onClaim;

  /// Callback when the sheet is closed.
  final VoidCallback? onClose;

  /// Displays the [StreakMilestoneTracker] as a frosted glass bottom modal sheet.
  static Future<void> show(
    BuildContext context, {
    required int streakDays,
    bool hasFreeze = false,
    VoidCallback? onClaim,
  }) {
    HapticFeedback.lightImpact();
    SoundEffects.instance.playTap();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => StreakMilestoneTracker(
        streakDays: streakDays,
        hasFreeze: hasFreeze,
        onClaim: onClaim,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  State<StreakMilestoneTracker> createState() => _StreakMilestoneTrackerState();
}

class _StreakMilestoneTrackerState extends State<StreakMilestoneTracker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _glowPulse;
  bool _claimed = false;

  static const List<String> _dayNames = [
    'Dush',
    'Sesh',
    'Chor',
    'Pay',
    'Jum',
    'Shan',
    'Yak',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _glowPulse = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Calculates completed days in current 7-day cycle (0..7).
  int get _cycleCompleted {
    if (widget.streakDays <= 0) return 0;
    final mod = widget.streakDays % 7;
    return mod == 0 ? 7 : mod;
  }

  bool get _isMilestoneReady => _cycleCompleted == 7 && !_claimed;

  StreakFlameTier get _tier => StreakFlameTier.fromDays(widget.streakDays);

  String get _motivationalQuote {
    if (widget.streakDays == 0) {
      return "Bugun 1 ta o'yinda g'alaba qozoning va birinchi seriyangizni yoqing!";
    } else if (widget.streakDays < 3) {
      return "Ajoyib boshlanish! Olovni o'chirmaslik uchun har kuni o'ynang!";
    } else if (widget.streakDays < 7) {
      return "Olov alangalamoqda! 7 kunlik marraga oz qoldi!";
    } else {
      return "Afsonaviy olov! Siz haqiqiy so'z jangchisiz!";
    }
  }

  void _handleClaim() {
    if (!_isMilestoneReady) return;
    HapticFeedback.heavyImpact();
    SoundEffects.instance.playWordSuccess();
    setState(() {
      _claimed = true;
    });
    widget.onClaim?.call();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxHeight = mq.size.height * 0.88;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: WBColors.bgPanel.withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: WBColors.whiteA(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 38,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: WBColors.whiteA(0.24),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // Hero Flame & Streak Count
                  _buildHeroSection(),

                  const SizedBox(height: 22),

                  // 7-Day Nodes Track
                  _buildMilestoneNodesTrack(),

                  const SizedBox(height: 20),

                  // Milestone Reward Card
                  _buildMilestoneChestCard(),

                  const SizedBox(height: 16),

                  // Streak Freeze (Saver) Card
                  _buildFreezeCard(),

                  const SizedBox(height: 22),

                  // Close Button
                  _buildCloseButton(context),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _tier.primaryColor.withValues(alpha: 0.16 * _glowPulse.value),
                WBColors.whiteA(0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _tier.primaryColor.withValues(alpha: 0.28 * _glowPulse.value),
            ),
          ),
          child: Column(
            children: [
              // Flame Tier Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _tier.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _tier.primaryColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 14,
                      color: _tier.primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _tier == StreakFlameTier.blazing
                          ? 'ALANGALI SERIYA'
                          : (_tier == StreakFlameTier.vibrant
                              ? 'QIZG‘IN SERIYA'
                              : 'YANGI SERIYA'),
                      style: WBText.mono(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: _tier.primaryColor,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Animated Living Flame
              Transform.scale(
                scale: _pulseScale.value,
                child: LiveStreakFlame(
                  size: 68,
                  tier: _tier,
                ),
              ),

              const SizedBox(height: 12),

              // Streak Count
              Text(
                '${widget.streakDays}',
                style: WBText.grotesk(
                  size: 42,
                  weight: FontWeight.w800,
                  color: WBColors.text,
                  letterSpacing: -0.02,
                ),
              ),
              Text(
                'KUNLIK SERIYA',
                style: WBText.mono(
                  size: 12,
                  weight: FontWeight.w600,
                  color: WBColors.textA(0.65),
                  letterSpacing: 0.08,
                ),
              ),

              const SizedBox(height: 10),

              // Motivational text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _motivationalQuote,
                  textAlign: TextAlign.center,
                  style: WBText.grotesk(
                    size: 13,
                    weight: FontWeight.w400,
                    color: WBColors.textA(0.85),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMilestoneNodesTrack() {
    final completed = _cycleCompleted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WBColors.whiteA(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WBColors.whiteA(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '7 KUNLIK MARRA',
                style: WBText.mono(
                  size: 11,
                  weight: FontWeight.w700,
                  color: WBColors.textA(0.6),
                  letterSpacing: 0.06,
                ),
              ),
              Text(
                '$completed / 7 kun',
                style: WBText.mono(
                  size: 12,
                  weight: FontWeight.w700,
                  color: WBColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 7 visual nodes connected by lines
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final dayNum = index + 1;
              final isDone = dayNum <= completed;
              final isToday = dayNum == (widget.streakDays == 0 ? 1 : completed);
              final isMilestoneDay = dayNum == 7;

              return Expanded(
                child: Row(
                  children: [
                    // Node
                    _buildDayNode(
                      dayIndex: index,
                      dayNum: dayNum,
                      dayName: _dayNames[index],
                      isDone: isDone,
                      isToday: isToday,
                      isMilestone: isMilestoneDay,
                    ),

                    // Connector line between nodes (if not last)
                    if (index < 6)
                      Expanded(
                        child: Container(
                          height: 2.5,
                          color: isDone && (dayNum < completed || completed == 7)
                              ? WBColors.amber
                              : WBColors.whiteA(0.12),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDayNode({
    required int dayIndex,
    required int dayNum,
    required String dayName,
    required bool isDone,
    required bool isToday,
    required bool isMilestone,
  }) {
    Color nodeBg;
    Color nodeBorder;
    Widget icon;

    if (isDone) {
      nodeBg = WBColors.amber.withValues(alpha: 0.22);
      nodeBorder = WBColors.amber;
      icon = isMilestone
          ? const Icon(Icons.workspace_premium_rounded, size: 16, color: Colors.amber)
          : const Icon(Icons.check_rounded, size: 16, color: Colors.amber);
    } else if (isToday) {
      nodeBg = WBColors.flameTop.withValues(alpha: 0.16);
      nodeBorder = WBColors.flameTop;
      icon = const LiveStreakFlame(size: 16, tier: StreakFlameTier.gentle);
    } else {
      nodeBg = WBColors.whiteA(0.04);
      nodeBorder = WBColors.whiteA(0.12);
      icon = isMilestone
          ? Icon(Icons.lock_rounded, size: 14, color: WBColors.textA(0.35))
          : Text(
              '$dayNum',
              style: WBText.mono(
                size: 11,
                weight: FontWeight.w600,
                color: WBColors.textA(0.4),
              ),
            );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: nodeBg,
            border: Border.all(
              color: nodeBorder,
              width: isToday || isDone ? 1.8 : 1.0,
            ),
            boxShadow: isDone || isToday
                ? [
                    BoxShadow(
                      color: (isDone ? WBColors.amber : WBColors.flameTop)
                          .withValues(alpha: 0.35),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: icon,
        ),
        const SizedBox(height: 6),
        Text(
          dayName,
          style: WBText.mono(
            size: 9.5,
            weight: isDone || isToday ? FontWeight.w700 : FontWeight.w500,
            color: isDone || isToday ? WBColors.text : WBColors.textA(0.45),
          ),
        ),
      ],
    );
  }

  Widget _buildMilestoneChestCard() {
    final completed = _cycleCompleted;
    final progress = (completed / 7.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            WBColors.amber.withValues(alpha: 0.14),
            WBColors.flameBottom.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isMilestoneReady
              ? WBColors.amber.withValues(alpha: 0.6)
              : WBColors.amber.withValues(alpha: 0.25),
          width: _isMilestoneReady ? 1.8 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: WBColors.amber.withValues(alpha: 0.18),
                  border: Border.all(color: WBColors.amber.withValues(alpha: 0.45)),
                ),
                child: Icon(
                  Icons.military_tech_rounded,
                  size: 26,
                  color: WBColors.amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '7 Kunlik Chempion Sandig‘i',
                      style: WBText.grotesk(
                        size: 15,
                        weight: FontWeight.w700,
                        color: WBColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '+50 Reyting • Olovli Profil • Himoya',
                      style: WBText.grotesk(
                        size: 11.5,
                        weight: FontWeight.w400,
                        color: WBColors.textA(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Linear progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 6,
              width: double.infinity,
              color: WBColors.whiteA(0.08),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [WBColors.amber, WBColors.flameTop],
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Claim or Status Button
          if (_isMilestoneReady)
            Pressable(
              onTap: _handleClaim,
              pressScale: 0.97,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [WBColors.amber, WBColors.flameTop],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: WBColors.amber.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'MUKOFOTNI OLISH',
                  style: WBText.grotesk(
                    size: 13.5,
                    weight: FontWeight.w800,
                    color: Colors.black87,
                    letterSpacing: 0.04,
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: WBColors.whiteA(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WBColors.whiteA(0.08)),
              ),
              alignment: Alignment.center,
              child: Text(
                _claimed
                    ? 'Mukofot qabul qilindi'
                    : 'Yana ${7 - completed} kunlik seriya kerak',
                style: WBText.grotesk(
                  size: 12,
                  weight: FontWeight.w600,
                  color: _claimed ? WBColors.green : WBColors.textA(0.65),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFreezeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.hasFreeze
            ? WBColors.teal.withValues(alpha: 0.12)
            : WBColors.whiteA(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.hasFreeze
              ? WBColors.teal.withValues(alpha: 0.35)
              : WBColors.whiteA(0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.hasFreeze
                  ? WBColors.teal.withValues(alpha: 0.2)
                  : WBColors.whiteA(0.06),
            ),
            child: Icon(
              Icons.ac_unit_rounded,
              size: 20,
              color: widget.hasFreeze ? WBColors.tealText : WBColors.textA(0.4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Streak Muzlatgich (Himoya)',
                  style: WBText.grotesk(
                    size: 13,
                    weight: FontWeight.w600,
                    color: WBColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.hasFreeze
                      ? 'Faol: seriyangiz 1 kun o‘tkazib yuborilsa ham saqlanadi.'
                      : 'O‘tkazib yuborilgan kunlarda seriyani saqlab qoladi.',
                  style: WBText.grotesk(
                    size: 11,
                    weight: FontWeight.w400,
                    color: WBColors.textA(0.65),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.hasFreeze
                  ? WBColors.teal.withValues(alpha: 0.25)
                  : WBColors.whiteA(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.hasFreeze ? 'FAOL' : 'YO‘Q',
              style: WBText.mono(
                size: 9.5,
                weight: FontWeight.w700,
                color: widget.hasFreeze ? WBColors.tealText : WBColors.textA(0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return Pressable(
      onTap: () {
        HapticFeedback.lightImpact();
        SoundEffects.instance.playTap();
        widget.onClose != null ? widget.onClose!() : Navigator.of(context).pop();
      },
      pressScale: 0.98,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: WBColors.whiteA(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WBColors.whiteA(0.12)),
        ),
        alignment: Alignment.center,
        child: Text(
          'TUSHUNARLI',
          style: WBText.grotesk(
            size: 14,
            weight: FontWeight.w700,
            color: WBColors.text,
            letterSpacing: 0.04,
          ),
        ),
      ),
    );
  }
}
