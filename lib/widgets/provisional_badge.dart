import 'package:flutter/material.dart';
import '../theme.dart';

/// The "?" chess.com puts beside a rating it does not trust yet, drawn once so
/// the lobby, the leaderboard, the duel header and the profile all mark an
/// unsettled rating the same way.
///
/// Deliberately quiet: a tinted pill a few points shorter than the number it
/// follows, close enough to read as part of it rather than as a second stat.
/// Whether it shows at all is the server's call — `UserDto.provisional`.
class ProvisionalBadge extends StatelessWidget {
  const ProvisionalBadge({super.key, this.size = 9});

  /// Type size of the "?" itself; the pill is padded around it. Given roughly
  /// two-thirds of the rating's own size at each call site, so the mark keeps
  /// its proportions from the 11.5px duel header up to the 24px profile total.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * .44, vertical: size * .16),
      decoration: BoxDecoration(
        color: WBColors.amberA(.13),
        border: Border.all(color: WBColors.amberA(.32)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '?',
        style: WBText.mono(size: size, weight: FontWeight.w700, color: WBColors.amber, height: 1.2),
      ),
    );
  }
}
