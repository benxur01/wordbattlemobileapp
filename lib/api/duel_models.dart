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
    required this.timeLeftMs,
    required this.turnSeconds,
    required this.yourWords,
    required this.opponentWords,
    required this.opponentThinking,
  });

  factory DuelView.fromMatchFound(Map<String, dynamic> json) => DuelView(
        duelId: json['duelId'] as String,
        opponent: UserDto.fromJson(json['opponent'] as Map<String, dynamic>),
        rated: json['rated'] as bool? ?? true,
        chain: ((json['chain'] as List?) ?? const [])
            .map((e) => ChainWord.fromJson(e as Map<String, dynamic>))
            .toList(),
        yourTurn: json['yourTurn'] as bool? ?? false,
        needLetter: (json['needLetter'] as String? ?? 'a').toUpperCase(),
        timeLeftMs: ((json['turnSeconds'] as num?)?.toInt() ?? 15) * 1000,
        turnSeconds: (json['turnSeconds'] as num?)?.toInt() ?? 15,
        yourWords: 0,
        opponentWords: 0,
        opponentThinking: !(json['yourTurn'] as bool? ?? false),
      );

  final String duelId;
  final UserDto opponent;
  final bool rated;
  final List<ChainWord> chain;
  final bool yourTurn;
  final String needLetter;
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
  });

  factory FinishedDuel.fromJson(Map<String, dynamic> json) => FinishedDuel(
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
      );

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

  String get averageLabel => '${(averageMs / 1000).toStringAsFixed(1)}s';
}

/// A challenge waiting for an answer, in either direction.
class PendingInvite {
  PendingInvite({required this.inviteId, required this.user, required this.secondsLeft});

  final String inviteId;
  final UserDto user;
  int secondsLeft;
}
