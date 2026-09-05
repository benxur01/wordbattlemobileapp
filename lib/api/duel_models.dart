import 'models.dart';

/// One word in the chain, as the server sees it.
class ChainWord {
  const ChainWord({required this.word, required this.mine, required this.spentMs});

  factory ChainWord.fromJson(Map<String, dynamic> json) => ChainWord(
        word: json['word'] as String,
        mine: json['mine'] as bool? ?? false,
        spentMs: (json['spentMs'] as num?)?.toInt() ?? 0,
      );

  final String word;
  final bool mine;
  final int spentMs;

  /// "1.8s" under the word, matching the design's label.
  String get spentLabel => '${(spentMs / 1000).toStringAsFixed(1)}s';
}

/// The live duel, rebuilt from every `match.found` / `duel.update` frame.
class DuelView {
  const DuelView({
    required this.duelId,
    required this.opponent,
    required this.rated,
    required this.chain,
    required this.yourTurn,
    required this.needLetter,
    required this.substitutedFrom,
    required this.timeLeftMs,
    required this.turnSeconds,
    required this.yourWords,
    required this.opponentWords,
    required this.opponentThinking,
  });

  /// The board a `match.found` raises, or null when the frame cannot carry one.
  ///
  /// Read the same defensive way [fromDuelUpdate] is, and for more: this frame
  /// is the only thing that puts a player on the duel screen at the start of a
  /// battle. It used to be taken at face value, so a payload whose `opponent`
  /// was missing or shaped differently — a rolling deploy serving two server
  /// versions, a matchmaking race — threw from inside the `setState` that was
  /// meant to raise the screen. Nothing caught it: `duel` was never assigned
  /// and the screen never changed, so the player watched the search screen
  /// turn while the server ran their turn timer down and their opponent played
  /// somebody who had stopped answering.
  ///
  /// The two fields checked here are the two that cannot be defaulted — a
  /// board with nobody on the other side of it, or one that cannot be named
  /// afterwards by [duelFrameApplies], is worse than no board at all.
  static DuelView? fromMatchFound(Map<String, dynamic> json) {
    final duelId = json['duelId'];
    final opponent = json['opponent'];
    if (duelId is! String || opponent is! Map<String, dynamic>) return null;

    return DuelView(
      duelId: duelId,
      opponent: UserDto.fromJson(opponent),
      rated: json['rated'] as bool? ?? true,
      chain: ((json['chain'] as List?) ?? const [])
          .map((e) => ChainWord.fromJson(e as Map<String, dynamic>))
          .toList(),
      yourTurn: json['yourTurn'] as bool? ?? false,
      needLetter: (json['needLetter'] as String? ?? 'a').toUpperCase(),
      substitutedFrom: (json['substitutedFrom'] as String?)?.toUpperCase(),
      timeLeftMs: ((json['turnSeconds'] as num?)?.toInt() ?? 15) * 1000,
      turnSeconds: (json['turnSeconds'] as num?)?.toInt() ?? 15,
      yourWords: 0,
      opponentWords: 0,
      opponentThinking: !(json['yourTurn'] as bool? ?? false),
    );
  }

  /// The board rebuilt from a `duel.update` on its own, or null when the frame
  /// cannot carry one.
  ///
  /// A live duel used to be reachable only through `match.found`, which meant
  /// only a process that had been running since the duel began could show one.
  /// Kill the app mid-battle — Android does it for memory, players do it by
  /// habit — and the relaunched process reconnected, was handed the duel state
  /// exactly as it should be, and dropped the frame because it had no board to
  /// apply it to. The player sat on the lobby while their turn timer ran out
  /// and charged them a rated loss they never saw, and their opponent was left
  /// playing someone who had gone silent.
  ///
  /// The server now names the opponent and says whether the duel is rated on
  /// every state frame, those being the only two things a `duel.update` did not
  /// already carry. Null means it did not — a server older than the fields —
  /// and the app then behaves as it always did rather than raising a board with
  /// nobody on the other side of it.
  ///
  /// Everything past those two is read by [applyUpdate]: one frame shape, one
  /// place that knows how to read it, so a field added to the frame cannot be
  /// picked up on the live path and forgotten on this one. The values handed to
  /// the constructor below are placeholders that [applyUpdate] overwrites — a
  /// `duel.update` carries all of them — and exist only because [DuelView]
  /// holds its fields final.
  static DuelView? fromDuelUpdate(Map<String, dynamic> json) {
    final duelId = json['duelId'];
    final opponent = json['opponent'];
    if (duelId is! String || opponent is! Map<String, dynamic>) return null;

    return DuelView(
      duelId: duelId,
      opponent: UserDto.fromJson(opponent),
      rated: json['rated'] as bool? ?? true,
      chain: const [],
      yourTurn: false,
      needLetter: 'A',
      substitutedFrom: null,
      timeLeftMs: 0,
      turnSeconds: 15,
      yourWords: 0,
      opponentWords: 0,
      opponentThinking: false,
    ).applyUpdate(json);
  }

  final String duelId;
  final UserDto opponent;
  final bool rated;
  final List<ChainWord> chain;
  final bool yourTurn;
  final String needLetter;

  /// The rare letter the chain skipped past, when it did. Null the rest of the
  /// time: the server leaves the field out entirely on the turns nothing was
  /// substituted, which is exactly when the note has to come off the screen.
  final String? substitutedFrom;
  final int timeLeftMs;
  final int turnSeconds;
  final int yourWords;
  final int opponentWords;
  final bool opponentThinking;

  DuelView applyUpdate(Map<String, dynamic> json) => DuelView(
        duelId: json['duelId'] as String? ?? duelId,
        opponent: opponent,
        rated: rated,
        chain: ((json['chain'] as List?) ?? const [])
            .map((e) => ChainWord.fromJson(e as Map<String, dynamic>))
            .toList(),
        yourTurn: json['yourTurn'] as bool? ?? false,
        needLetter: (json['needLetter'] as String? ?? needLetter).toUpperCase(),
        // Deliberately without a fallback to the previous value: an absent
        // field means this chain ends on an ordinary letter, so the note goes.
        substitutedFrom: (json['substitutedFrom'] as String?)?.toUpperCase(),
        timeLeftMs: (json['timeLeftMs'] as num?)?.toInt() ?? timeLeftMs,
        turnSeconds: (json['turnSeconds'] as num?)?.toInt() ?? turnSeconds,
        yourWords: (json['yourWords'] as num?)?.toInt() ?? yourWords,
        opponentWords: (json['opponentWords'] as num?)?.toInt() ?? opponentWords,
        opponentThinking: json['opponentThinking'] as bool? ?? false,
      );

  /// Local countdown between server frames, so the ring moves smoothly.
  DuelView tick(int elapsedMs) => DuelView(
        duelId: duelId,
        opponent: opponent,
        rated: rated,
        chain: chain,
        yourTurn: yourTurn,
        needLetter: needLetter,
        substitutedFrom: substitutedFrom,
        timeLeftMs: timeLeftMs - elapsedMs < 0 ? 0 : timeLeftMs - elapsedMs,
        turnSeconds: turnSeconds,
        yourWords: yourWords,
        opponentWords: opponentWords,
        opponentThinking: opponentThinking,
      );

  double get secondsLeft => timeLeftMs / 1000;
}

/// The `duel.finished` payload behind the win and lose screens.
class FinishedDuel {
  const FinishedDuel({
    required this.duelId,
    required this.won,
    required this.reason,
    required this.rated,
    required this.delta,
    required this.ratingBefore,
    required this.ratingAfter,
    required this.chainLength,
    required this.yourWords,
    required this.averageMs,
    required this.newWords,
    required this.streakDays,
    required this.stuckLetter,
    required this.hints,
    required this.opponentId,
    required this.opponentIsBot,
  });

  factory FinishedDuel.fromJson(Map<String, dynamic> json) => FinishedDuel(
        duelId: json['duelId'] as String?,
        won: (json['result'] as String? ?? 'lose') == 'win',
        reason: json['reason'] as String? ?? '',
        rated: json['rated'] as bool? ?? false,
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        ratingBefore: (json['ratingBefore'] as num?)?.toInt() ?? 0,
        ratingAfter: (json['ratingAfter'] as num?)?.toInt() ?? 0,
        chainLength: (json['chainLength'] as num?)?.toInt() ?? 0,
        yourWords: (json['yourWords'] as num?)?.toInt() ?? 0,
        averageMs: (json['averageMs'] as num?)?.toInt() ?? 0,
        newWords: (json['newWords'] as num?)?.toInt() ?? 0,
        streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
        stuckLetter: json['stuckLetter'] as String?,
        hints: ((json['hints'] as List?) ?? const []).map((e) => e as String).toList(),
        opponentId: (json['opponentId'] as num?)?.toInt(),
        opponentIsBot: json['opponentIsBot'] as bool? ?? false,
      );

  /// Which duel this is the result of — the one thing that tells a result
  /// arriving for the duel just left behind from the result of the duel being
  /// played right now. Nullable only for a server old enough not to send it,
  /// which the app then treats as it always did; see `duelFrameApplies`.
  final String? duelId;

  final bool won;
  final String reason;
  final bool rated;
  final int delta;
  final int ratingBefore;
  final int ratingAfter;
  final int chainLength;
  final int yourWords;
  final int averageMs;
  final int newWords;
  final int streakDays;
  final String? stuckLetter;
  final List<String> hints;

  /// Who was actually played, so a rematch can challenge that person rather
  /// than whoever matchmaking hands out next. Null only for a server old
  /// enough not to send it.
  final int? opponentId;

  /// Whether [opponentId] was the bot rather than a real player — the bot has
  /// a real, fixed id ([opponentId] is never null for it), so this is the
  /// only way to tell the two apart.
  final bool opponentIsBot;

  String get averageLabel => '${(averageMs / 1000).toStringAsFixed(1)}s';
}

/// One word in a spectated duel's chain, as a third party sees it: the
/// player who sent it is named outright rather than reduced to [ChainWord]'s
/// `mine`.
class SpectateChainWord {
  const SpectateChainWord({required this.word, required this.playerId, required this.spentMs});

  factory SpectateChainWord.fromJson(Map<String, dynamic> json) => SpectateChainWord(
        word: json['word'] as String,
        playerId: (json['playerId'] as num?)?.toInt() ?? 0,
        spentMs: (json['spentMs'] as num?)?.toInt() ?? 0,
      );

  final String word;

  /// Matches [SpectateState.playerOne]'s or [SpectateState.playerTwo]'s id —
  /// except for the chain's opening word, which the server marks with 0,
  /// an id that belongs to neither. See [isSeed].
  final int playerId;
  final int spentMs;

  /// The chain's opening word, seeded by nobody rather than played by either
  /// side — the one entry [playerId] cannot be used to attribute.
  bool get isSeed => playerId == 0;

  /// "1.8s" under the word, matching [ChainWord.spentLabel].
  String get spentLabel => '${(spentMs / 1000).toStringAsFixed(1)}s';
}

/// A live duel as a third party watches it, rebuilt whole from every
/// `duel.spectate_state` frame — both players named outright, rather than the
/// `mine`/`opponent` shape [DuelView] uses for whoever is actually playing.
class SpectateState {
  const SpectateState({
    required this.duelId,
    required this.playerOne,
    required this.playerTwo,
    required this.chain,
    required this.turnPlayerId,
    required this.needLetter,
    required this.substitutedFrom,
    required this.timeLeftMs,
    required this.turnSeconds,
    required this.playerOneWords,
    required this.playerTwoWords,
  });

  factory SpectateState.fromJson(Map<String, dynamic> json) => SpectateState(
        duelId: json['duelId'] as String,
        playerOne: UserDto.fromJson(json['playerOne'] as Map<String, dynamic>),
        playerTwo: UserDto.fromJson(json['playerTwo'] as Map<String, dynamic>),
        chain: ((json['chain'] as List?) ?? const [])
            .map((e) => SpectateChainWord.fromJson(e as Map<String, dynamic>))
            .toList(),
        turnPlayerId: (json['turnPlayerId'] as num?)?.toInt() ?? 0,
        needLetter: (json['needLetter'] as String? ?? 'a').toUpperCase(),
        substitutedFrom: (json['substitutedFrom'] as String?)?.toUpperCase(),
        timeLeftMs: (json['timeLeftMs'] as num?)?.toInt() ?? 0,
        turnSeconds: (json['turnSeconds'] as num?)?.toInt() ?? 15,
        playerOneWords: (json['playerOneWords'] as num?)?.toInt() ?? 0,
        playerTwoWords: (json['playerTwoWords'] as num?)?.toInt() ?? 0,
      );

  final String duelId;
  final UserDto playerOne;
  final UserDto playerTwo;
  final List<SpectateChainWord> chain;

  /// Whichever of [playerOne] or [playerTwo] is on turn right now.
  final int turnPlayerId;
  final String needLetter;

  /// The rare letter the chain skipped past, when it did — null the rest of
  /// the time, same as [DuelView.substitutedFrom].
  final String? substitutedFrom;
  final int timeLeftMs;
  final int turnSeconds;
  final int playerOneWords;
  final int playerTwoWords;

  bool get playerOneTurn => turnPlayerId == playerOne.id;

  /// Local countdown between server frames, mirroring [DuelView.tick].
  SpectateState tick(int elapsedMs) => SpectateState(
        duelId: duelId,
        playerOne: playerOne,
        playerTwo: playerTwo,
        chain: chain,
        turnPlayerId: turnPlayerId,
        needLetter: needLetter,
        substitutedFrom: substitutedFrom,
        timeLeftMs: timeLeftMs - elapsedMs < 0 ? 0 : timeLeftMs - elapsedMs,
        turnSeconds: turnSeconds,
        playerOneWords: playerOneWords,
        playerTwoWords: playerTwoWords,
      );

  double get secondsLeft => timeLeftMs / 1000;
}

/// One line of the duel's chat — this duel only, never persisted. [mine]
/// tells the bubble which side to render on, the same way [ChainWord.mine]
/// does for the chain.
class DuelChatMessage {
  const DuelChatMessage({required this.text, required this.mine});

  final String text;
  final bool mine;
}

/// A reaction the opponent sent. [id] is a local counter rather than
/// anything the server hands back, so the same emoji sent twice in a row is
/// still seen as a fresh event and replays its animation.
class DuelReaction {
  const DuelReaction({required this.emoji, required this.id});

  final String emoji;
  final int id;
}

/// A challenge waiting for an answer, in either direction.
class PendingInvite {
  PendingInvite({required this.inviteId, required this.user, required this.secondsLeft});

  final String inviteId;
  final UserDto user;
  int secondsLeft;
}

/// A team-duel invite waiting for an answer, in either direction — the same
/// shape as [PendingInvite], kept as its own type so the two can never be mixed
/// up in state that has to hold both at once.
class PendingTeamInvite {
  PendingTeamInvite({required this.inviteId, required this.user, required this.secondsLeft});

  final String inviteId;
  final UserDto user;
  int secondsLeft;
}

/// One word in a team duel's chain, as all four participants see it: whether
/// this player said it, their partner said it, or one of the two opponents did
/// — [mine] and [ally] mirror the server's own fields rather than being
/// derived, and [playerId] is what tells the two opponents apart, the same way
/// [SpectateChainWord.playerId] tells the two spectated players apart.
class TeamChainWord {
  const TeamChainWord({
    required this.word,
    required this.playerId,
    required this.mine,
    required this.ally,
    required this.spentMs,
  });

  factory TeamChainWord.fromJson(Map<String, dynamic> json) => TeamChainWord(
        word: json['word'] as String,
        playerId: (json['playerId'] as num?)?.toInt() ?? 0,
        mine: json['mine'] as bool? ?? false,
        ally: json['ally'] as bool? ?? false,
        spentMs: (json['spentMs'] as num?)?.toInt() ?? 0,
      );

  final String word;
  final int playerId;
  final bool mine;
  final bool ally;
  final int spentMs;

  /// Neither [mine] nor [ally]: one of the two opponents said it. [playerId]
  /// is then read against the duel's `opponentOne`/`opponentTwo` ids to say
  /// which.
  bool get isFoe => !mine && !ally;

  /// "1.8s" under the word, matching [ChainWord.spentLabel].
  String get spentLabel => '${(spentMs / 1000).toStringAsFixed(1)}s';
}

/// The live 2v2 duel, rebuilt from every `team_duel.match_found` /
/// `team_duel.update` frame — four named participants rather than [DuelView]'s
/// one opponent, and a turn that cycles through all four rather than
/// alternating between two.
class TeamDuelView {
  const TeamDuelView({
    required this.duelId,
    required this.partner,
    required this.opponentOne,
    required this.opponentTwo,
    required this.rated,
    required this.seedWord,
    required this.chain,
    required this.yourTurn,
    required this.turnPlayerId,
    required this.needLetter,
    required this.substitutedFrom,
    required this.timeLeftMs,
    required this.turnSeconds,
    required this.yourWords,
    required this.partnerWords,
    required this.opponentOneWords,
    required this.opponentTwoWords,
  });

  /// The board a `team_duel.match_found` raises, or null when the frame cannot
  /// carry one — the same defensive read [DuelView.fromMatchFound] gives the
  /// 1v1 frame, for the same reason: a duel screen raised on half a board is
  /// worse than no board at all.
  static TeamDuelView? fromMatchFound(Map<String, dynamic> json) {
    final duelId = json['duelId'];
    final partner = json['partner'];
    final opponentOne = json['opponentOne'];
    final opponentTwo = json['opponentTwo'];
    if (duelId is! String ||
        partner is! Map<String, dynamic> ||
        opponentOne is! Map<String, dynamic> ||
        opponentTwo is! Map<String, dynamic>) {
      return null;
    }

    return TeamDuelView(
      duelId: duelId,
      partner: UserDto.fromJson(partner),
      opponentOne: UserDto.fromJson(opponentOne),
      opponentTwo: UserDto.fromJson(opponentTwo),
      rated: json['rated'] as bool? ?? true,
      // Only `match_found` carries this — the fixed starting word never
      // changes for the rest of the duel, so `team_duel.update` does not
      // repeat it. See [seedWord].
      seedWord: json['seedWord'] as String? ?? '',
      chain: ((json['chain'] as List?) ?? const [])
          .map((e) => TeamChainWord.fromJson(e as Map<String, dynamic>))
          .toList(),
      yourTurn: json['yourTurn'] as bool? ?? false,
      turnPlayerId: (json['turnPlayerId'] as num?)?.toInt() ?? 0,
      needLetter: (json['needLetter'] as String? ?? 'a').toUpperCase(),
      substitutedFrom: (json['substitutedFrom'] as String?)?.toUpperCase(),
      timeLeftMs: ((json['turnSeconds'] as num?)?.toInt() ?? 15) * 1000,
      turnSeconds: (json['turnSeconds'] as num?)?.toInt() ?? 15,
      yourWords: 0,
      partnerWords: 0,
      opponentOneWords: 0,
      opponentTwoWords: 0,
    );
  }

  /// The board rebuilt from a `team_duel.update` on its own, or null when the
  /// frame cannot carry one — mirrors [DuelView.fromDuelUpdate], for the same
  /// relaunch-mid-duel case.
  ///
  /// [seedWord] comes back empty here: a relaunch that reconnects mid-duel is
  /// handed a `team_duel.update`, which never repeats it. The chain already
  /// played is unaffected — only the chip naming the very first word is
  /// missing after a resume.
  static TeamDuelView? fromDuelUpdate(Map<String, dynamic> json) {
    final duelId = json['duelId'];
    final partner = json['partner'];
    final opponentOne = json['opponentOne'];
    final opponentTwo = json['opponentTwo'];
    if (duelId is! String ||
        partner is! Map<String, dynamic> ||
        opponentOne is! Map<String, dynamic> ||
        opponentTwo is! Map<String, dynamic>) {
      return null;
    }

    return TeamDuelView(
      duelId: duelId,
      partner: UserDto.fromJson(partner),
      opponentOne: UserDto.fromJson(opponentOne),
      opponentTwo: UserDto.fromJson(opponentTwo),
      rated: true,
      seedWord: '',
      chain: const [],
      yourTurn: false,
      turnPlayerId: 0,
      needLetter: 'A',
      substitutedFrom: null,
      timeLeftMs: 0,
      turnSeconds: 15,
      yourWords: 0,
      partnerWords: 0,
      opponentOneWords: 0,
      opponentTwoWords: 0,
    ).applyUpdate(json);
  }

  final String duelId;
  final UserDto partner;
  final UserDto opponentOne;
  final UserDto opponentTwo;
  final bool rated;

  /// The duel's fixed starting word, shown once ahead of [chain] — see the
  /// note on [fromMatchFound] and [fromDuelUpdate] for when it is and is not
  /// known.
  final String seedWord;
  final List<TeamChainWord> chain;
  final bool yourTurn;

  /// Whichever of the four participants is on turn right now — see
  /// [partnerTurn], [opponentOneTurn], [opponentTwoTurn].
  final int turnPlayerId;
  final String needLetter;

  /// The rare letter the chain skipped past, when it did — null the rest of
  /// the time, same as [DuelView.substitutedFrom].
  final String? substitutedFrom;
  final int timeLeftMs;
  final int turnSeconds;
  final int yourWords;
  final int partnerWords;
  final int opponentOneWords;
  final int opponentTwoWords;

  bool get partnerTurn => turnPlayerId == partner.id;
  bool get opponentOneTurn => turnPlayerId == opponentOne.id;
  bool get opponentTwoTurn => turnPlayerId == opponentTwo.id;

  TeamDuelView applyUpdate(Map<String, dynamic> json) => TeamDuelView(
        duelId: json['duelId'] as String? ?? duelId,
        partner: partner,
        opponentOne: opponentOne,
        opponentTwo: opponentTwo,
        rated: rated,
        seedWord: seedWord,
        chain: ((json['chain'] as List?) ?? const [])
            .map((e) => TeamChainWord.fromJson(e as Map<String, dynamic>))
            .toList(),
        yourTurn: json['yourTurn'] as bool? ?? false,
        turnPlayerId: (json['turnPlayerId'] as num?)?.toInt() ?? turnPlayerId,
        needLetter: (json['needLetter'] as String? ?? needLetter).toUpperCase(),
        substitutedFrom: (json['substitutedFrom'] as String?)?.toUpperCase(),
        timeLeftMs: (json['timeLeftMs'] as num?)?.toInt() ?? timeLeftMs,
        turnSeconds: (json['turnSeconds'] as num?)?.toInt() ?? turnSeconds,
        yourWords: (json['yourWords'] as num?)?.toInt() ?? yourWords,
        partnerWords: (json['partnerWords'] as num?)?.toInt() ?? partnerWords,
        opponentOneWords: (json['opponentOneWords'] as num?)?.toInt() ?? opponentOneWords,
        opponentTwoWords: (json['opponentTwoWords'] as num?)?.toInt() ?? opponentTwoWords,
      );

  /// Local countdown between server frames, mirroring [DuelView.tick].
  TeamDuelView tick(int elapsedMs) => TeamDuelView(
        duelId: duelId,
        partner: partner,
        opponentOne: opponentOne,
        opponentTwo: opponentTwo,
        rated: rated,
        seedWord: seedWord,
        chain: chain,
        yourTurn: yourTurn,
        turnPlayerId: turnPlayerId,
        needLetter: needLetter,
        substitutedFrom: substitutedFrom,
        timeLeftMs: timeLeftMs - elapsedMs < 0 ? 0 : timeLeftMs - elapsedMs,
        turnSeconds: turnSeconds,
        yourWords: yourWords,
        partnerWords: partnerWords,
        opponentOneWords: opponentOneWords,
        opponentTwoWords: opponentTwoWords,
      );

  double get secondsLeft => timeLeftMs / 1000;
}

/// The `team_duel.finished` payload behind the team win and lose screens —
/// the same fields [FinishedDuel] carries, plus the three named participants
/// a 2v2 result has to credit instead of a single opponent.
class TeamFinishedDuel {
  const TeamFinishedDuel({
    required this.duelId,
    required this.won,
    required this.reason,
    required this.rated,
    required this.delta,
    required this.ratingBefore,
    required this.ratingAfter,
    required this.chainLength,
    required this.yourWords,
    required this.averageMs,
    required this.newWords,
    required this.streakDays,
    required this.stuckLetter,
    required this.hints,
    required this.partner,
    required this.opponentOne,
    required this.opponentTwo,
  });

  factory TeamFinishedDuel.fromJson(Map<String, dynamic> json) => TeamFinishedDuel(
        duelId: json['duelId'] as String?,
        won: (json['result'] as String? ?? 'lose') == 'win',
        reason: json['reason'] as String? ?? '',
        rated: json['rated'] as bool? ?? true,
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        ratingBefore: (json['ratingBefore'] as num?)?.toInt() ?? 0,
        ratingAfter: (json['ratingAfter'] as num?)?.toInt() ?? 0,
        chainLength: (json['chainLength'] as num?)?.toInt() ?? 0,
        yourWords: (json['yourWords'] as num?)?.toInt() ?? 0,
        averageMs: (json['averageMs'] as num?)?.toInt() ?? 0,
        newWords: (json['newWords'] as num?)?.toInt() ?? 0,
        streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
        stuckLetter: json['stuckLetter'] as String?,
        hints: ((json['hints'] as List?) ?? const []).map((e) => e as String).toList(),
        partner: UserDto.fromJson(json['partner'] as Map<String, dynamic>),
        opponentOne: UserDto.fromJson(json['opponentOne'] as Map<String, dynamic>),
        opponentTwo: UserDto.fromJson(json['opponentTwo'] as Map<String, dynamic>),
      );

  /// Which duel this is the result of — mirrors [FinishedDuel.duelId], and
  /// exists for the same reason: see `duelFrameApplies` in `app_root.dart`.
  final String? duelId;

  final bool won;
  final String reason;
  final bool rated;
  final int delta;
  final int ratingBefore;
  final int ratingAfter;
  final int chainLength;
  final int yourWords;
  final int averageMs;
  final int newWords;
  final int streakDays;
  final String? stuckLetter;
  final List<String> hints;
  final UserDto partner;
  final UserDto opponentOne;
  final UserDto opponentTwo;

  String get averageLabel => '${(averageMs / 1000).toStringAsFixed(1)}s';
}
