import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

    return Padding(
      padding: EdgeInsets.fromLTRB(widget.horizontalMargin, 0, widget.horizontalMargin, 12),
      // The blur has to be clipped to the pill's rounded rect, but clipping also
      // crops the outer drop shadow — so the shadow lives on this unclipped box
      // and the glass lives on the clipped one nested inside it.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: WBColors.shadow, blurRadius: 28, offset: const Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: WBColors.glass,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: WBColors.whiteA(.18)),
              ),
              child: Stack(
                children: [
                  // Thin top-to-bottom sheen so the glass reads as lit from
                  // above, on top of the shared blur/tint but under the tabs.
                  // This has to sit at the container's own bounds rather than
                  // inside the padded tab row below — nested in that instead,
                  // it only fills the area 6px in from the pill's real edge,
                  // which reads as a hard-edged darker box under the icons. It
                  // stays white in both palettes — a highlight taken through
                  // `whiteA` would be drawn as a shadow over the light one.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white.withValues(alpha: .14), Colors.white.withValues(alpha: 0)],
                          stops: const [0, .5],
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
                                      color: WBColors.accentA(.13),
                                      border: Border.all(color: WBColors.accentA(.28)),
                                      borderRadius: BorderRadius.circular(18),
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
                                        onTap: tabs[i].$4,
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
    final color = Color.lerp(WBColors.textA(.5), WBColors.accent, selection)!;
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
                  constraints: const BoxConstraints(minWidth: 15),
                  height: 15,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: WBColors.red, borderRadius: BorderRadius.circular(99)),
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
