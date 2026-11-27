import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'nav_icons.dart';
import 'primary_button.dart';

enum WBTab { home, friends, board, profile }

/// The floating pill tab bar shown on lobby/board/profile/friends screens.
///
/// The design swaps the highlighted tab instantly (it is a static mockup). On
/// a phone that reads as a glitch, so the amber tile slides from the previous
/// tab to the new one and the icon/label colours cross-fade with it. Each
/// screen builds its own `BottomNav`, so the animation cannot rely on state
/// surviving the swap — [previous] tells the freshly-mounted bar where the
/// highlight is coming from.
class BottomNav extends StatefulWidget {
  const BottomNav({
    super.key,
    required this.active,
    required this.friendRequestCount,
    required this.onHome,
    required this.onFriends,
    required this.onBoard,
    required this.onProfile,
    this.previous,
    this.horizontalMargin = 36,
  });

  final WBTab active;

  /// The tab that was highlighted on the screen we came from, or null when the
  /// bar appears from somewhere outside the tab bar (duel, onboarding, …) and
  /// should simply start in place.
  final WBTab? previous;

  final int friendRequestCount;
  final VoidCallback onHome;
  final VoidCallback onFriends;
  final VoidCallback onBoard;
  final VoidCallback onProfile;

  /// Board/profile/friends put the bar at the screen edge with a 36px margin.
  /// The lobby nests it inside a 22px-padded column and only adds 14px, so it
  /// must be told about that or it ends up 22px narrower than everywhere else.
  final double horizontalMargin;

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> with SingleTickerProviderStateMixin {
  static const _itemHeight = 54.0;
  static const _gap = 4.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.previous != null && widget.previous != widget.active) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (WBTab.home, WBNavIcon.home, 'Bosh', widget.onHome, null),
      (WBTab.friends, WBNavIcon.friends, "Do'stlar", widget.onFriends,
          widget.friendRequestCount > 0 ? widget.friendRequestCount : null),
      (WBTab.board, WBNavIcon.board, 'Reyting', widget.onBoard, null),
      (WBTab.profile, WBNavIcon.profile, 'Profil', widget.onProfile, null),
    ];

    final isLight = WBTheme.isLight;
    final glassColor = isLight
        ? const Color.fromRGBO(255, 255, 255, 0.90)
        : const Color.fromRGBO(21, 23, 28, 0.90);
    final borderColor = WBColors.hairlineStrong;

    return Padding(
      padding: EdgeInsets.fromLTRB(widget.horizontalMargin, 0, widget.horizontalMargin, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: isLight
                  ? const Color.fromRGBO(0, 0, 0, 0.10)
                  : const Color.fromRGBO(0, 0, 0, 0.42),
              blurRadius: 24,
              spreadRadius: -2,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: isLight
                  ? const Color.fromRGBO(0, 0, 0, 0.04)
                  : const Color.fromRGBO(0, 0, 0, 0.22),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: glassColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: isLight ? 0.25 : 0.04),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const [0, 0.24],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemWidth = (constraints.maxWidth - _gap * 3) / 4;
                        return AnimatedBuilder(
                          animation: _c,
                          builder: (context, _) {
                            final t = Curves.easeOutCubic.transform(_c.value);
                            final from = (widget.previous ?? widget.active).index.toDouble();
                            // Fractional tab index the highlight currently sits on.
                            final position = from + (widget.active.index - from) * t;

                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: position * (itemWidth + _gap),
                                  width: itemWidth,
                                  top: 0,
                                  height: _itemHeight,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      color: isLight
                                          ? Colors.black.withValues(alpha: 0.065)
                                          : Colors.white.withValues(alpha: 0.085),
                                      border: Border.all(
                                        color: WBColors.hairline,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    for (var i = 0; i < tabs.length; i++) ...[
                                      if (i > 0) const SizedBox(width: _gap),
                                      _NavItem(
                                        icon: tabs[i].$2,
                                        label: tabs[i].$3,
                                        // 1 when the highlight is fully on this tab, 0 when it
                                        // has moved a whole slot away — the colours travel with
                                        // the tile instead of snapping at the end.
                                        selection: (1 - (position - i).abs()).clamp(0.0, 1.0),
                                        width: itemWidth,
                                        height: _itemHeight,
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          tabs[i].$4();
                                        },
                                        badge: tabs[i].$5,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selection,
    required this.width,
    required this.height,
    required this.onTap,
    this.badge,
  });

  final WBNavIcon icon;
  final String label;
  final double selection; // 0 → inactive, 1 → active
  final double width;
  final double height;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final isLight = WBTheme.isLight;
    final color = Color.lerp(WBColors.textA(.46), WBColors.text, selection)!;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NavIcon(icon: icon, size: 19, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: WBText.grotesk(
                    size: 10.5,
                    weight: selection > .5 ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                    letterSpacing: .01,
                  ),
                ),
              ],
            ),
            if (badge != null)
              Positioned(
                top: 7,
                right: 20,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 4.5),
                  decoration: BoxDecoration(
                    color: WBColors.red,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: isLight ? Colors.white : const Color(0xFF16181E),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text('$badge', style: WBText.mono(size: 9, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
