import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api/models.dart';
import '../api/tournament_models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

/// The live bracket: every round, every match, decided/live/pending/champion —
/// drawn as two mirrored halves that each play down to a finalist, meeting in
/// a Final/Champion column at the horizontal centre. Read-only for everyone,
/// participant or spectator alike: nothing on this screen assumes the viewer
/// is playing in it, because nothing here is interactive beyond scrolling and
/// going back.
///
/// The split is a pure rendering choice, not a server one: {@code
/// TournamentService.start} already lays a round's matches out so that the
/// first half of its slots (by slot number) feeds the left side of the next
/// round and the second half feeds the right — the ordinary shape of a
/// recursively-reseeded single-elimination tree — so this screen only ever
/// needs to bisect each round's match list down the middle.
class TournamentBracketScreen extends StatefulWidget {
  const TournamentBracketScreen({
    super.key,
    required this.detail,
    required this.onBack,
    required this.meId,
    required this.onCancel,
  });

  /// Null while the detail is still loading.
  final TournamentDetail? detail;
  final VoidCallback onBack;

  /// The signed-in player's own id — compared against `detail.organizer.id`
  /// to decide whether the cancel button below belongs to this viewer.
  final int? meId;

  /// Calls the tournament off for good. Null for a spectator or a
  /// participant who isn't its organizer — the cancel button never shows
  /// without it.
  final VoidCallback? onCancel;

  @override
  State<TournamentBracketScreen> createState() => _TournamentBracketScreenState();
}

class _TournamentBracketScreenState extends State<TournamentBracketScreen> {
  /// Cancelling cannot be undone, so the button asks once more in place
  /// rather than acting on the first tap — the same inline confirmation
  /// `OrganizeTournamentManageScreen` uses for its own "Turnirni bekor
  /// qilish".
  bool _confirmingCancel = false;

  static const _matchWidth = 132.0;
  // Tall enough for two player rows (avatar + name, each ~20dp with its own
  // padding) inside the card's border and padding — 60 clips a real two-line
  // card by a few pixels, invisible until real match content is rendered. A
  // 2v2 bracket stacks a second name under each side, so both its card and the
  // gap below it grow by that extra line.
  double get _matchHeight => _isTeam ? 86 : 68;
  double get _rowPitch => _isTeam ? 94 : 76;
  static const _connectorWidth = 28.0;
  static const _colLabelHeight = 30.0;
  static const _centerWidth = 152.0;
  static const _championHeight = 92.0;
  static const _championGap = 16.0;

  final ScrollController _hScroll = ScrollController();
  bool _centeredOnFinal = false;

  @override
  void initState() {
    super.initState();
    _maybeCenterOnFinal();
  }

  @override
  void didUpdateWidget(covariant TournamentBracketScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeCenterOnFinal();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  /// Centres the horizontal scroll on the Final/Champion column the first
  /// moment there is a bracket to show, rather than leaving a wide 32-player
  /// draw sitting at its far-left edge.
  ///
  /// Every column this screen draws is mirrored around that column, so the
  /// midpoint of the whole scrollable width is always exactly its midpoint
  /// too — centring the content is centring on it, with no column widths to
  /// add up by hand.
  void _maybeCenterOnFinal() {
    if (_centeredOnFinal) return;
    final rounds = widget.detail?.rounds;
    if (rounds == null || rounds.isEmpty || rounds.first.matches.isEmpty) return;
    _centeredOnFinal = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hScroll.hasClients) return;
      _hScroll.jumpTo(_hScroll.position.maxScrollExtent / 2);
    });
  }

  bool get _isTeam => widget.detail?.isTeam ?? false;

  /// Only the tournament's own organizer, and only while it is still live —
  /// a spectator or an ordinary participant never sees this, whatever
  /// [widget.onCancel] is wired to.
  bool get _cancellable {
    final d = widget.detail;
    return d != null &&
        widget.onCancel != null &&
        widget.meId != null &&
        d.organizer?.id == widget.meId &&
        d.status == 'in_progress';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -1),
          radius: 1.1,
          colors: [WBColors.accentA(.16), Colors.transparent],
          stops: const [0, .72],
        ),
      ),
      child: Column(
        children: [
          _header(),
          _hint(),
          Expanded(child: _bracket()),
          if (_cancellable)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: _cancelSection(),
            ),
        ],
      ),
    );
  }

  Widget _cancelSection() {
    if (!_confirmingCancel) {
      return _FlatActionButton(
        label: 'Bekor qilish',
        color: WBColors.redSoft,
        border: WBColors.redA(.28),
        onTap: () => setState(() => _confirmingCancel = true),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: WBColors.redA(.08),
        border: Border.all(color: WBColors.redA(.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Turnir butunlay bekor qilinadi va uni qayta boshlab bo'lmaydi. Barcha qatnashchilarga xabar beriladi.",
            style: WBText.grotesk(size: 12, height: 1.45, color: WBColors.textA(.72)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FlatActionButton(
                  label: 'Bekor qilish',
                  color: WBColors.textA(.75),
                  border: WBColors.whiteA(.12),
                  onTap: () => setState(() => _confirmingCancel = false),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _FlatActionButton(
                  label: 'Ha, bekor qilish',
                  color: WBColors.redSoft,
                  border: WBColors.redA(.45),
                  fill: WBColors.redA(.14),
                  onTap: widget.onCancel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final d = widget.detail;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 13),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: WBColors.whiteA(.07)))),
      child: Row(
        children: [
          Pressable(
            onTap: widget.onBack,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.1)),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.arrow_back_ios_new, size: 14, color: WBColors.textA(.7)),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  d?.name ?? 'Turnir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                ),
                if (d != null)
                  Text(
                    _subtitle(d),
                    style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.4), letterSpacing: .1),
                  ),
                if (d?.organizer != null)
                  Text(
                    "${d!.organizer!.label} tashkil qilgan",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WBText.grotesk(size: 10, weight: FontWeight.w500, color: WBColors.textA(.3)),
                  ),
              ],
            ),
          ),
          Pressable(
            onTap: d == null ? null : () => _share(d),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.1)),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.ios_share, size: 15, color: WBColors.textA(.7)),
            ),
          ),
          const SizedBox(width: 8),
          if (d != null && d.status == 'in_progress')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: WBColors.greenA(.11),
                border: Border.all(color: WBColors.greenA(.28)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: WBColors.green,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: WBColors.greenA(.8), blurRadius: 7)],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('JONLI', style: WBText.mono(size: 11, weight: FontWeight.w700, color: WBColors.green, letterSpacing: .05)),
                ],
              ),
            )
          else
            const SizedBox(width: 38),
        ],
      ),
    );
  }

  /// `wordbattle.example.uz` is a placeholder for the real production domain
  /// — swap it here once one exists (see backend/README.md's "Turnirlar"
  /// section for the Android App Links half of this link).
  void _share(TournamentDetail d) {
    SharePlus.instance.share(
      ShareParams(text: "${d.name} turniriga qo'shil! https://wordbattle.example.uz/t/${d.id}"),
    );
  }

  String _subtitle(TournamentDetail d) {
    final entrants = d.isTeam ? '${d.size} JAMOA' : "${d.size} O'YINCHI";
    if (d.isCompleted) return '$entrants · YAKUNLANDI';
    final label = tournamentRoundLabel(d.currentRound.round, d.totalRounds);
    return '$entrants · $label BOSQICHI';
  }

  Widget _hint() => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
        child: Text(
          "↔ Bracketni ko'rish uchun suring",
          textAlign: TextAlign.center,
          style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.28), letterSpacing: .08),
        ),
      );

  Widget _bracket() {
    final d = widget.detail;
    if (d == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (d.rounds.isEmpty || d.rounds.first.matches.isEmpty) {
      return Center(
        child: Text("Bracket hali tayyor emas", style: WBText.grotesk(size: 14, color: WBColors.textA(.5))),
      );
    }

    // Every round before the final splits cleanly in half by slot — the first
    // half of a round's matches (in slot order) always feeds the left side of
    // the next round, the second half the right, all the way down to the two
    // single matches that produce the two finalists. See the class note.
    final sideRounds = d.totalRounds - 1;
    final leftRounds = <TournamentRound>[];
    final rightRounds = <TournamentRound>[];
    for (var r = 0; r < sideRounds; r++) {
      final round = d.rounds[r];
      final half = round.matches.length ~/ 2;
      leftRounds.add(TournamentRound(round: round.round, matches: round.matches.sublist(0, half)));
      rightRounds.add(TournamentRound(round: round.round, matches: round.matches.sublist(half)));
    }
    final finalRound = d.rounds[sideRounds];

    // A shape function of match counts alone, so the same centres apply to
    // either side — the tree is symmetric.
    final sideCenters = _centersByRound(leftRounds);
    final bodyHeight = (leftRounds.first.matches.length - 1) * _rowPitch + _matchHeight;
    final finalCenter = bodyHeight / 2;
    final championBottom = finalCenter + _matchHeight / 2 + _championGap + _championHeight;
    final centerBodyHeight = math.max(bodyHeight, championBottom);

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var r = 0; r < sideRounds; r++) ...[
                            _column(leftRounds[r], sideCenters[r], bodyHeight, d.totalRounds),
                            _connector(
                              childCenters: sideCenters[r],
                              parentCenters: r + 1 < sideCenters.length ? sideCenters[r + 1] : [finalCenter],
                              decided: leftRounds[r].matches.map((m) => m.isDone).toList(),
                              bodyHeight: bodyHeight,
                            ),
                          ],
                          _finalColumn(d, finalRound, finalCenter, centerBodyHeight),
                          for (var r = sideRounds - 1; r >= 0; r--) ...[
                            Transform.flip(
                              flipX: true,
                              child: _connector(
                                childCenters: sideCenters[r],
                                parentCenters: r + 1 < sideCenters.length ? sideCenters[r + 1] : [finalCenter],
                                decided: rightRounds[r].matches.map((m) => m.isDone).toList(),
                                bodyHeight: bodyHeight,
                              ),
                            ),
                            _column(rightRounds[r], sideCenters[r], bodyHeight, d.totalRounds),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          bottom: 22,
          width: 26,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [WBColors.bg.withValues(alpha: 0), WBColors.bg],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 22,
          width: 26,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [WBColors.bg.withValues(alpha: 0), WBColors.bg],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Round-1 match centres (within one side) are evenly spaced; every later
  /// round's centre is the midpoint of the pair of matches that feed it — the
  /// same maths whichever side it is run on, since it depends only on how
  /// many matches each round has.
  List<List<double>> _centersByRound(List<TournamentRound> sideRounds) {
    final round1Count = sideRounds.first.matches.length;
    var previous = List.generate(round1Count, (i) => i * _rowPitch + _matchHeight / 2);
    final result = [previous];
    for (var r = 1; r < sideRounds.length; r++) {
      final next = <double>[];
      for (var i = 0; i * 2 + 1 < previous.length; i++) {
        next.add((previous[i * 2] + previous[i * 2 + 1]) / 2);
      }
      result.add(next);
      previous = next;
    }
    return result;
  }

  Widget _column(TournamentRound round, List<double> centers, double bodyHeight, int totalRounds) {
    return SizedBox(
      width: _matchWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: _colLabelHeight,
            child: Center(
              child: Text(
                tournamentRoundLabel(round.round, totalRounds),
                style: WBText.mono(size: 10, weight: FontWeight.w600, color: WBColors.textA(.38), letterSpacing: .1),
              ),
            ),
          ),
          SizedBox(
            width: _matchWidth,
            height: bodyHeight,
            child: Stack(
              children: [
                for (var i = 0; i < round.matches.length; i++)
                  Positioned(
                    top: centers[i] - _matchHeight / 2,
                    left: 0,
                    width: _matchWidth,
                    height: _matchHeight,
                    child: _matchCard(round.matches[i]),
                  ),
                for (var i = 0; i < round.matches.length; i++)
                  if (round.matches[i].isLive)
                    Positioned(
                      top: centers[i] - _matchHeight / 2 + _matchHeight + 6,
                      left: 0,
                      width: _matchWidth,
                      child: _liveTag(),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveTag() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: WBColors.green,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: WBColors.greenA(.85), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 4),
          Text('JONLI', style: WBText.mono(size: 8.5, weight: FontWeight.w700, color: WBColors.green, letterSpacing: .1)),
        ],
      );

  Widget _matchCard(TournamentMatchView match) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: WBColors.cardFill,
        border: Border.all(color: WBColors.cardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _playerRow(match, match.playerOne, match.playerOnePartner, isFirst: true),
          _playerRow(match, match.playerTwo, match.playerTwoPartner, isFirst: false),
        ],
      ),
    );
  }

  /// One side of a match — a lone player, or, in a 2v2 bracket, the pair that
  /// plays as one seat, stacked under a single avatar.
  Widget _playerRow(TournamentMatchView match, UserDto? player, UserDto? partner, {required bool isFirst}) {
    final content = player == null
        ? Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: WBColors.whiteA(.18), style: BorderStyle.solid),
                ),
                alignment: Alignment.center,
                child: Text('?', style: WBText.mono(size: 10, color: WBColors.whiteA(.25))),
              ),
              const SizedBox(width: 7),
              Text('Kutilmoqda', style: WBText.grotesk(size: 10.5, weight: FontWeight.w500, color: WBColors.whiteA(.35))),
            ],
          )
        : Row(
            children: [
              _avatar(player),
              const SizedBox(width: 7),
              Expanded(
                child: partner == null
                    ? Text(
                        player.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WBText.grotesk(size: 11, weight: FontWeight.w600, color: _nameColor(match, player)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            player.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WBText.grotesk(size: 10, weight: FontWeight.w600, color: _nameColor(match, player)),
                          ),
                          Text(
                            '+ ${partner.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WBText.grotesk(size: 10, weight: FontWeight.w600, color: _nameColor(match, player)),
                          ),
                        ],
                      ),
              ),
              if (match.isDone && match.wonBy(player))
                Icon(Icons.check, size: 13, color: WBColors.green),
            ],
          );

    return Container(
      padding: EdgeInsets.only(top: isFirst ? 0 : 4, bottom: 3),
      margin: EdgeInsets.only(top: isFirst ? 0 : 1),
      decoration: isFirst
          ? null
          : BoxDecoration(border: Border(top: BorderSide(color: WBColors.whiteA(.07)))),
      child: content,
    );
  }

  Color _nameColor(TournamentMatchView match, UserDto player) {
    if (match.isDone) return match.wonBy(player) ? WBColors.text : WBColors.textA(.4);
    return WBColors.text;
  }

  Widget _connector({
    required List<double> childCenters,
    required List<double> parentCenters,
    required List<bool> decided,
    required double bodyHeight,
  }) {
    return SizedBox(
      width: _connectorWidth,
      height: _colLabelHeight + bodyHeight,
      child: Padding(
        padding: const EdgeInsets.only(top: _colLabelHeight),
        child: CustomPaint(
          size: Size(_connectorWidth, bodyHeight),
          painter: _BracketConnectorPainter(
            childCenters: childCenters,
            parentCenters: parentCenters,
            decided: decided,
          ),
        ),
      ),
    );
  }

  /// The centre column: the Final match, at the same row every side's own
  /// final plays on, and the Champion slot below it.
  Widget _finalColumn(TournamentDetail d, TournamentRound finalRound, double center, double bodyHeight) {
    final finalMatch = finalRound.matches.isEmpty ? null : finalRound.matches[0];
    return SizedBox(
      width: _centerWidth,
      child: Column(
        children: [
          SizedBox(
            height: _colLabelHeight,
            child: Center(
              child: Text('FINAL', style: WBText.mono(size: 10, weight: FontWeight.w600, color: WBColors.textA(.38), letterSpacing: .1)),
            ),
          ),
          SizedBox(
            width: _centerWidth,
            height: bodyHeight,
            child: Stack(
              children: [
                if (finalMatch != null)
                  Positioned(
                    top: center - _matchHeight / 2,
                    left: 0,
                    width: _centerWidth,
                    height: _matchHeight,
                    child: _matchCard(finalMatch),
                  ),
                if (finalMatch != null && finalMatch.isLive)
                  Positioned(
                    top: center - _matchHeight / 2 + _matchHeight + 6,
                    left: 0,
                    width: _centerWidth,
                    child: _liveTag(),
                  ),
                Positioned(
                  top: center + _matchHeight / 2 + _championGap,
                  left: 0,
                  width: _centerWidth,
                  height: _championHeight,
                  child: _championBox(d.champion, d.championPartner),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _championBox(UserDto? champion, UserDto? championPartner) {
    final label = champion == null
        ? 'ANIQLANMAGAN'
        : championPartner == null
            ? champion.label.toUpperCase()
            : '${champion.label.toUpperCase()} + ${championPartner.label.toUpperCase()}';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: WBColors.blueA(.45), width: 1.5),
        borderRadius: BorderRadius.circular(16),
        gradient: RadialGradient(
          center: const Alignment(0, -.4),
          radius: .9,
          colors: [WBColors.blueA(.16), Colors.transparent],
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 22, color: WBColors.blueText),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: championPartner == null ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: WBText.mono(
                size: 10,
                weight: FontWeight.w700,
                color: WBColors.blueText.withValues(alpha: .75),
                letterSpacing: .1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              champion == null
                  ? 'final tugagach'
                  : championPartner == null
                      ? "turnir g'olibi"
                      : "g'olib jamoa",
              style: WBText.grotesk(size: 9.5, weight: FontWeight.w500, color: WBColors.textA(.35)),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _avatar(UserDto user) {
    final gradient = _gradients[user.id.abs() % _gradients.length];
    final color = _textColors[user.id.abs() % _textColors.length];
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(6)),
      alignment: Alignment.center,
      child: Text(user.initial, style: WBText.grotesk(size: 8.5, weight: FontWeight.w700, color: color)),
    );
  }
}

/// Draws the elbow connectors between one round's match centres and the next
/// round's — solid blue once the feeding match is decided, dashed grey while
/// it is still pending, exactly as the mockup marks a bracket path that has
/// not been walked yet. Used unmirrored for the left half, and wrapped in
/// `Transform.flip(flipX: true)` for the right half — a mirror image of the
/// same shape rather than a second painter.
class _BracketConnectorPainter extends CustomPainter {
  _BracketConnectorPainter({required this.childCenters, required this.parentCenters, required this.decided});

  final List<double> childCenters;
  final List<double> parentCenters;
  final List<bool> decided;

  static const _elbowX = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final solid = Paint()
      ..color = WBColors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final dashed = Paint()
      ..color = WBColors.whiteA(.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var i = 0; i < parentCenters.length; i++) {
      final parentY = parentCenters[i];
      for (final childIndex in [i * 2, i * 2 + 1]) {
        if (childIndex >= childCenters.length) continue;
        final childY = childCenters[childIndex];
        final path = Path()..moveTo(0, childY);
        if ((childY - parentY).abs() < 0.5) {
          path.lineTo(size.width, parentY);
        } else {
          path
            ..lineTo(_elbowX, childY)
            ..lineTo(_elbowX, parentY)
            ..lineTo(size.width, parentY);
        }
        final isDecided = childIndex < decided.length && decided[childIndex];
        _drawPath(canvas, path, isDecided ? solid : dashed, dashed: !isDecided);
      }
    }
  }

  void _drawPath(Canvas canvas, Path path, Paint paint, {required bool dashed}) {
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    const dashLength = 3.0;
    const gapLength = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BracketConnectorPainter oldDelegate) =>
      oldDelegate.childCenters != childCenters ||
      oldDelegate.parentCenters != parentCenters ||
      oldDelegate.decided != decided;
}

/// A flat, bordered row button — the same quiet, non-accent tone
/// `OrganizeTournamentManageScreen` uses for its own cancel confirmation.
class _FlatActionButton extends StatelessWidget {
  const _FlatActionButton({
    required this.label,
    required this.color,
    required this.border,
    required this.onTap,
    this.fill,
  });

  final String label;
  final Color color;
  final Color border;
  final Color? fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: fill ?? WBColors.whiteA(.04),
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(15),
          ),
          alignment: Alignment.center,
          child: Text(label, style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: color)),
        ),
      ),
    );
  }
}
