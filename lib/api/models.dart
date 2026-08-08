/// Wire models mirroring the backend DTOs. Field names match the JSON exactly,
/// so a change on either side shows up as a missing key rather than silently
/// wrong data.
library;

class UserDto {
  const UserDto({
    required this.id,
    required this.nickname,
    required this.displayName,
    required this.initial,
    required this.city,
    required this.rating,
    required this.streakDays,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
        id: json['id'] as int,
        nickname: json['nickname'] as String?,
        displayName: json['displayName'] as String?,
        initial: (json['initial'] as String?) ?? '?',
        city: json['city'] as String?,
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String? nickname;
  final String? displayName;
  final String initial;
  final String? city;
  final int rating;
  final int streakDays;

  /// The name every screen draws. The server labels the players it cannot name
  /// — a deleted opponent arrives as "O'chirilgan akkaunt" — so this last
  /// fallback is for a live account with no nickname yet and no name from
  /// Google. Rare, but it is still a person the app has to address in Uzbek.
  String get label => nickname ?? displayName ?? "O'yinchi";
}

class NicknameCheck {
  const NicknameCheck({required this.available, this.reason, this.suggestions = const []});

  factory NicknameCheck.fromJson(Map<String, dynamic> json) => NicknameCheck(
        available: json['available'] as bool? ?? false,
        reason: json['reason'] as String?,
        suggestions: ((json['suggestions'] as List?) ?? const []).map((e) => e as String).toList(),
      );

  final bool available;
  final String? reason;
  final List<String> suggestions;
}

class RatingPoint {
  const RatingPoint(this.at, this.rating);

  factory RatingPoint.fromJson(Map<String, dynamic> json) =>
      RatingPoint(DateTime.parse(json['at'] as String), (json['rating'] as num).toInt());

  final DateTime at;
  final int rating;
}

class BadgeDto {
  const BadgeDto({
    required this.code,
    required this.label,
    required this.unlocked,
    required this.progress,
    required this.target,
  });

  factory BadgeDto.fromJson(Map<String, dynamic> json) => BadgeDto(
        code: json['code'] as String,
        label: json['label'] as String,
        unlocked: json['unlocked'] as bool? ?? false,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        target: (json['target'] as num?)?.toInt() ?? 0,
      );

  final String code;
  final String label;
  final bool unlocked;
  final int progress;
  final int target;
}

class ProfileDto {
  const ProfileDto({
    required this.user,
    required this.globalRank,
    required this.battles,
    required this.wins,
    required this.winPercent,
    required this.longestChain,
    required this.wordsLearned,
    required this.streakDays,
    required this.weeklyDelta,
    required this.ratingHistory,
    required this.badges,
  });

  factory ProfileDto.fromJson(Map<String, dynamic> json) => ProfileDto(
        user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
        globalRank: (json['globalRank'] as num?)?.toInt() ?? 0,
        battles: (json['battles'] as num?)?.toInt() ?? 0,
        wins: (json['wins'] as num?)?.toInt() ?? 0,
        winPercent: (json['winPercent'] as num?)?.toInt() ?? 0,
        longestChain: (json['longestChain'] as num?)?.toInt() ?? 0,
        wordsLearned: (json['wordsLearned'] as num?)?.toInt() ?? 0,
        streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
        weeklyDelta: (json['weeklyDelta'] as num?)?.toInt() ?? 0,
        ratingHistory: ((json['ratingHistory'] as List?) ?? const [])
            .map((e) => RatingPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        badges: ((json['badges'] as List?) ?? const [])
            .map((e) => BadgeDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final UserDto user;
  final int globalRank;
  final int battles;
  final int wins;
  final int winPercent;
  final int longestChain;
  final int wordsLearned;
  final int streakDays;
  final int weeklyDelta;
  final List<RatingPoint> ratingHistory;
  final List<BadgeDto> badges;
}

class FriendDto {
  const FriendDto({required this.user, required this.online, required this.inBattle, this.lastSeenAt});

  factory FriendDto.fromJson(Map<String, dynamic> json) => FriendDto(
        user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
        online: json['online'] as bool? ?? false,
        inBattle: json['inBattle'] as bool? ?? false,
        lastSeenAt: json['lastSeenAt'] == null ? null : DateTime.parse(json['lastSeenAt'] as String),
      );

  final UserDto user;
  final bool online;
  final bool inBattle;
  final DateTime? lastSeenAt;

  /// The status line under the nickname on the friends screen.
  String get status {
    if (inBattle) return 'onlayn · jangda';
    if (online) return 'onlayn · jangga tayyor';
    final seen = lastSeenAt;
    if (seen == null) return 'oflayn';
    final gap = DateTime.now().difference(seen);
    if (gap.inMinutes < 60) return '${gap.inMinutes} daqiqa oldin';
    if (gap.inHours < 24) return '${gap.inHours} soat oldin';
    return '${gap.inDays} kun oldin';
  }
}

class FriendRequestDto {
  const FriendRequestDto({required this.id, required this.user, required this.mutualFriends});

  factory FriendRequestDto.fromJson(Map<String, dynamic> json) => FriendRequestDto(
        id: json['id'] as int,
        user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
        mutualFriends: (json['mutualFriends'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final UserDto user;
  final int mutualFriends;

  String get meta => mutualFriends > 0
      ? "${user.rating} · $mutualFriends umumiy do'st"
      : '${user.rating}';
}

class LeaderboardRow {
  const LeaderboardRow({required this.rank, required this.user, required this.self});

  factory LeaderboardRow.fromJson(Map<String, dynamic> json) => LeaderboardRow(
        rank: (json['rank'] as num).toInt(),
        user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
        self: json['self'] as bool? ?? false,
      );

  final int rank;
  final UserDto user;
  final bool self;
}

class LeaderboardDto {
  const LeaderboardDto({required this.rows, this.me});

  factory LeaderboardDto.fromJson(Map<String, dynamic> json) => LeaderboardDto(
        rows: ((json['rows'] as List?) ?? const [])
            .map((e) => LeaderboardRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        me: json['me'] == null ? null : LeaderboardRow.fromJson(json['me'] as Map<String, dynamic>),
      );

  final List<LeaderboardRow> rows;
  final LeaderboardRow? me;
}

class PracticeWordDto {
  const PracticeWordDto({required this.word, required this.ipa, required this.meaning});

  factory PracticeWordDto.fromJson(Map<String, dynamic> json) => PracticeWordDto(
        word: json['word'] as String,
        ipa: (json['ipa'] as String?) ?? '',
        meaning: json['meaning'] as String,
      );

  final String word;
  final String ipa;
  final String meaning;
}

/// One finished duel in the history list.
class MatchSummaryDto {
  const MatchSummaryDto({
    required this.id,
    required this.opponent,
    required this.botOpponent,
    required this.won,
    required this.rated,
    required this.delta,
    required this.ratingAfter,
    required this.chainLength,
    required this.endReason,
    required this.finishedAt,
  });

  factory MatchSummaryDto.fromJson(Map<String, dynamic> json) => MatchSummaryDto(
        id: (json['id'] as num).toInt(),
        opponent: UserDto.fromJson(json['opponent'] as Map<String, dynamic>),
        botOpponent: json['botOpponent'] as bool? ?? false,
        won: json['won'] as bool? ?? false,
        rated: json['rated'] as bool? ?? false,
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        ratingAfter: (json['ratingAfter'] as num?)?.toInt() ?? 0,
        chainLength: (json['chainLength'] as num?)?.toInt() ?? 0,
        endReason: json['endReason'] as String? ?? '',
        finishedAt: DateTime.parse(json['finishedAt'] as String),
      );

  final int id;
  final UserDto opponent;
  final bool botOpponent;
  final bool won;
  final bool rated;
  final int delta;
  final int ratingAfter;
  final int chainLength;
  final String endReason;
  final DateTime finishedAt;
}

/// A finished duel with its full chain, for the replay view.
class MatchDetailDto {
  const MatchDetailDto({required this.summary, required this.chain});

  factory MatchDetailDto.fromJson(Map<String, dynamic> json) => MatchDetailDto(
        summary: MatchSummaryDto.fromJson(json['summary'] as Map<String, dynamic>),
        chain: ((json['chain'] as List?) ?? const [])
            .map((e) => MatchWordDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final MatchSummaryDto summary;
  final List<MatchWordDto> chain;
}

class MatchWordDto {
  const MatchWordDto({required this.word, required this.mine, required this.spentMs});

  factory MatchWordDto.fromJson(Map<String, dynamic> json) => MatchWordDto(
        word: json['word'] as String,
        mine: json['mine'] as bool? ?? false,
        spentMs: (json['spentMs'] as num?)?.toInt() ?? 0,
      );

  final String word;
  final bool mine;
  final int spentMs;
}
