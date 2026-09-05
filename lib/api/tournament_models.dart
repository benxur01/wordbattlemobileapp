/// Wire models for the tournament feature, mirroring the backend's
/// `TournamentSummaryDto` / `TournamentInviteDto` / `TournamentMatchPromptDto`
/// / `TournamentDetailDto` field for field — see `lib/api/models.dart`'s own
/// note for why the shapes match the JSON exactly.
library;

import 'models.dart';

/// The lobby's "an active tournament exists" discovery card.
class TournamentSummary {
  const TournamentSummary({required this.id, required this.name, required this.size, required this.status});

  factory TournamentSummary.fromJson(Map<String, dynamic> json) => TournamentSummary(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? '',
      );

  final int id;
  final String name;
  final int size;
  final String status;
}

/// A tournament invite waiting for an answer — pushed live as
/// `tournament.invite`, unlike a duel challenge this survives a disconnect.
class TournamentInvite {
  const TournamentInvite({
    required this.tournamentId,
    required this.name,
    required this.size,
    required this.participantStatus,
    required this.organizer,
  });

  factory TournamentInvite.fromJson(Map<String, dynamic> json) => TournamentInvite(
        tournamentId: (json['tournamentId'] as num).toInt(),
        name: json['name'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        participantStatus: json['participantStatus'] as String? ?? '',
        organizer: json['organizer'] == null ? null : UserDto.fromJson(json['organizer'] as Map<String, dynamic>),
      );

  final int tournamentId;
  final String name;
  final int size;
  final String participantStatus;

  /// Whoever created this tournament — an admin or a player organizing one
  /// among friends, the same shape either way. Null only if that account has
  /// since been deleted.
  final UserDto? organizer;
}

/// "Your tournament match is ready" — the lobby's prompt to press start.
class TournamentMatchPrompt {
  const TournamentMatchPrompt({
    required this.tournamentMatchId,
    required this.tournamentId,
    required this.tournamentName,
    required this.round,
    required this.totalRounds,
    required this.opponent,
  });

  factory TournamentMatchPrompt.fromJson(Map<String, dynamic> json) => TournamentMatchPrompt(
        tournamentMatchId: (json['tournamentMatchId'] as num).toInt(),
        tournamentId: (json['tournamentId'] as num).toInt(),
        tournamentName: json['tournamentName'] as String? ?? '',
        round: (json['round'] as num?)?.toInt() ?? 1,
        totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 1,
        opponent: json['opponent'] == null ? null : UserDto.fromJson(json['opponent'] as Map<String, dynamic>),
      );

  final int tournamentMatchId;
  final int tournamentId;
  final String tournamentName;
  final int round;
  final int totalRounds;
  final UserDto? opponent;

  String get roundLabel => tournamentRoundLabel(round, totalRounds);
}

/// One match card in the bracket. `playerOne`/`playerTwo` are null until an
/// earlier round decides them — drawn as the dashed "Kutilmoqda" slot.
class TournamentMatchView {
  const TournamentMatchView({
    required this.slot,
    required this.id,
    required this.playerOne,
    required this.playerTwo,
    required this.winnerUserId,
    required this.status,
  });

  factory TournamentMatchView.fromJson(Map<String, dynamic> json) => TournamentMatchView(
        slot: (json['slot'] as num?)?.toInt() ?? 0,
        id: (json['id'] as num?)?.toInt(),
        playerOne: json['playerOne'] == null ? null : UserDto.fromJson(json['playerOne'] as Map<String, dynamic>),
        playerTwo: json['playerTwo'] == null ? null : UserDto.fromJson(json['playerTwo'] as Map<String, dynamic>),
        winnerUserId: (json['winnerUserId'] as num?)?.toInt(),
        status: json['status'] as String? ?? 'pending',
      );

  final int slot;
  final int? id;
  final UserDto? playerOne;
  final UserDto? playerTwo;
  final int? winnerUserId;

  /// One of `pending`, `ready`, `live`, `done`.
  final String status;

  bool get isLive => status == 'live';
  bool get isDone => status == 'done';

  bool wonBy(UserDto? player) => player != null && winnerUserId == player.id;
}

class TournamentRound {
  const TournamentRound({required this.round, required this.matches});

  factory TournamentRound.fromJson(Map<String, dynamic> json) => TournamentRound(
        round: (json['round'] as num?)?.toInt() ?? 1,
        matches: ((json['matches'] as List?) ?? const [])
            .map((e) => TournamentMatchView.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final int round;
  final List<TournamentMatchView> matches;
}

/// The whole bracket, as `tournament_bracket_screen.dart` draws it — readable
/// by any signed-in player, participant or not.
class TournamentDetail {
  const TournamentDetail({
    required this.id,
    required this.name,
    required this.size,
    required this.status,
    required this.totalRounds,
    required this.rounds,
    required this.champion,
    required this.organizer,
  });

  factory TournamentDetail.fromJson(Map<String, dynamic> json) => TournamentDetail(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? '',
        totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 0,
        rounds: ((json['rounds'] as List?) ?? const [])
            .map((e) => TournamentRound.fromJson(e as Map<String, dynamic>))
            .toList(),
        champion: json['champion'] == null ? null : UserDto.fromJson(json['champion'] as Map<String, dynamic>),
        organizer: json['organizer'] == null ? null : UserDto.fromJson(json['organizer'] as Map<String, dynamic>),
      );

  final int id;
  final String name;
  final int size;
  final String status;
  final int totalRounds;
  final List<TournamentRound> rounds;
  final UserDto? champion;

  /// Whoever created this tournament. Null only if that account has since
  /// been deleted.
  final UserDto? organizer;

  bool get isCompleted => status == 'completed';

  /// The earliest round that still has a match left to decide — the stage the
  /// header's "N O'YINCHI · ... BOSQICHI" line names. Every round is done once
  /// the champion is known, so this falls back to the last one.
  TournamentRound get currentRound {
    for (final round in rounds) {
      if (round.matches.any((m) => !m.isDone)) return round;
    }
    return rounds.isEmpty ? const TournamentRound(round: 1, matches: []) : rounds.last;
  }
}

/// One invited player on the organizer's own setup screen — the friends-screen
/// "Turnir tashkil qilish" flow's view of `GET /api/tournaments/{id}/participants`.
class TournamentParticipantView {
  const TournamentParticipantView({required this.userId, required this.user, required this.status, this.seed});

  factory TournamentParticipantView.fromJson(Map<String, dynamic> json) => TournamentParticipantView(
        userId: (json['userId'] as num).toInt(),
        user: json['user'] == null ? null : UserDto.fromJson(json['user'] as Map<String, dynamic>),
        status: json['status'] as String? ?? 'invited',
        seed: (json['seed'] as num?)?.toInt(),
      );

  final int userId;
  final UserDto? user;

  /// One of `invited`, `accepted`, `declined`.
  final String status;
  final int? seed;

  bool get accepted => status == 'accepted';

  String get statusLabel => switch (status) {
        'accepted' => 'Qabul qildi',
        'declined' => 'Rad etdi',
        _ => 'Taklif qilindi',
      };
}

/// The bracket column label for a round — "1/4-FINAL", "YARIM FINAL", "FINAL"
/// — the same denominator football and word-battle tournaments both use:
/// how many matches are left to decide that round.
String tournamentRoundLabel(int round, int totalRounds) {
  final fromFinal = totalRounds - round;
  if (fromFinal <= 0) return 'FINAL';
  if (fromFinal == 1) return 'YARIM FINAL';
  return '1/${1 << fromFinal}-FINAL';
}
