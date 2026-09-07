/// Wire models for `/api/admin/**`, mirroring the records in
/// `AdminController.java` field for field.
///
/// Shapes of their own rather than the player-facing DTOs on purpose, and for
/// the same reason the server keeps them apart: this is the one place a deleted
/// shell, a ban and the admin role itself are worth rendering.
///
/// Every field here is read defensively — a date that will not parse becomes
/// null and a number that is missing becomes zero — so one changed shape costs a
/// cell its label rather than costing the screen its whole table. A rolling
/// deploy has two versions answering for as long as it takes to roll, and an
/// admin looking into a complaint is exactly who should not be told to come back
/// later.
library;

class AdminPage<T> {
  const AdminPage({
    required this.items,
    required this.page,
    required this.size,
    required this.total,
    required this.totalPages,
  });

  factory AdminPage.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) item) => AdminPage(
        items: ((json['items'] as List?) ?? const []).map((e) => item(e as Map<String, dynamic>)).toList(),
        page: (json['page'] as num?)?.toInt() ?? 0,
        size: (json['size'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      );

  final List<T> items;
  final int page;
  final int size;
  final int total;
  final int totalPages;

  bool get hasPrevious => page > 0;

  bool get hasNext => page + 1 < totalPages;
}

class AdminUserRow {
  const AdminUserRow({
    required this.id,
    required this.nickname,
    required this.displayName,
    required this.city,
    required this.rating,
    required this.battles,
    required this.wins,
    required this.admin,
    required this.banned,
    required this.bannedAt,
    required this.deleted,
    required this.createdAt,
    required this.lastSeenAt,
  });

  factory AdminUserRow.fromJson(Map<String, dynamic> json) => AdminUserRow(
        id: (json['id'] as num).toInt(),
        nickname: json['nickname'] as String?,
        displayName: json['displayName'] as String?,
        city: json['city'] as String?,
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        battles: (json['battles'] as num?)?.toInt() ?? 0,
        wins: (json['wins'] as num?)?.toInt() ?? 0,
        admin: json['admin'] as bool? ?? false,
        banned: json['banned'] as bool? ?? false,
        bannedAt: DateTime.tryParse(json['bannedAt'] as String? ?? ''),
        deleted: json['deleted'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
      );

  final int id;
  final String? nickname;
  final String? displayName;
  final String? city;
  final int rating;
  final int battles;
  final int wins;
  final bool admin;
  final bool banned;
  final DateTime? bannedAt;
  final bool deleted;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;

  /// A nickname, a display name, or the id — whichever the row still has, which
  /// is how the server labels these accounts too. A deleted shell has neither.
  String get label => nickname ?? displayName ?? '#$id';
}

class AdminUserDetail {
  const AdminUserDetail({
    required this.user,
    required this.globalRank,
    required this.winPercent,
    required this.longestChain,
    required this.wordsLearned,
    required this.streakDays,
    required this.lastPlayedOn,
  });

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) => AdminUserDetail(
        user: AdminUserRow.fromJson(json['user'] as Map<String, dynamic>),
        globalRank: (json['globalRank'] as num?)?.toInt() ?? 0,
        winPercent: (json['winPercent'] as num?)?.toInt() ?? 0,
        longestChain: (json['longestChain'] as num?)?.toInt() ?? 0,
        wordsLearned: (json['wordsLearned'] as num?)?.toInt() ?? 0,
        streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
        // A `LocalDate`, so "2026-08-11" rather than an instant.
        lastPlayedOn: DateTime.tryParse(json['lastPlayedOn'] as String? ?? ''),
      );

  final AdminUserRow user;
  final int globalRank;
  final int winPercent;
  final int longestChain;
  final int wordsLearned;
  final int streakDays;
  final DateTime? lastPlayedOn;
}

class AdminMatchRow {
  const AdminMatchRow({
    required this.id,
    required this.playerOneId,
    required this.playerOne,
    required this.playerTwoId,
    required this.playerTwo,
    required this.botOpponent,
    required this.winnerId,
    required this.endReason,
    required this.chainLength,
    required this.startedAt,
    required this.finishedAt,
  });

  factory AdminMatchRow.fromJson(Map<String, dynamic> json) => AdminMatchRow(
        id: (json['id'] as num).toInt(),
        playerOneId: (json['playerOneId'] as num?)?.toInt(),
        playerOne: json['playerOne'] as String?,
        // Null for a bot duel: the second player is not an account.
        playerTwoId: (json['playerTwoId'] as num?)?.toInt(),
        playerTwo: json['playerTwo'] as String?,
        botOpponent: json['botOpponent'] as bool? ?? false,
        winnerId: (json['winnerId'] as num?)?.toInt(),
        endReason: json['endReason'] as String? ?? '',
        chainLength: (json['chainLength'] as num?)?.toInt() ?? 0,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
        finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
      );

  final int id;
  final int? playerOneId;
  final String? playerOne;
  final int? playerTwoId;
  final String? playerTwo;
  final bool botOpponent;
  final int? winnerId;
  final String endReason;
  final int chainLength;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  String get playerOneLabel => playerOne ?? (playerOneId == null ? '—' : '#$playerOneId');

  String get playerTwoLabel => botOpponent ? 'BOT' : (playerTwo ?? (playerTwoId == null ? '—' : '#$playerTwoId'));
}

class AdminAuditEntry {
  const AdminAuditEntry({
    required this.id,
    required this.adminUserId,
    required this.admin,
    required this.action,
    required this.targetUserId,
    required this.target,
    required this.detail,
    required this.createdAt,
  });

  factory AdminAuditEntry.fromJson(Map<String, dynamic> json) => AdminAuditEntry(
        id: (json['id'] as num).toInt(),
        adminUserId: (json['adminUserId'] as num?)?.toInt(),
        admin: json['admin'] as String?,
        action: json['action'] as String? ?? '',
        targetUserId: (json['targetUserId'] as num?)?.toInt(),
        target: json['target'] as String?,
        detail: json['detail'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  final int id;
  final int? adminUserId;
  final String? admin;
  final String action;
  final int? targetUserId;
  final String? target;
  final String? detail;
  final DateTime? createdAt;

  String get adminLabel => admin ?? (adminUserId == null ? '—' : '#$adminUserId');

  String get targetLabel => target ?? (targetUserId == null ? '—' : '#$targetUserId');

  /// The three actions `AdminAuditService` writes, in the panel's language.
  /// An action it does not know is shown as the server wrote it rather than
  /// hidden — a log with rows missing is a log that gets believed wrongly.
  String get actionLabel => switch (action) {
        'user_ban' => 'Bloklandi',
        'user_unban' => 'Blok olindi',
        'user_nickname' => "Taxallus o'zgardi",
        _ => action,
      };
}

class AdminTournamentRow {
  const AdminTournamentRow({
    required this.id,
    required this.name,
    required this.size,
    required this.status,
    required this.format,
    required this.createdAt,
    required this.startedAt,
    required this.finishedAt,
  });

  factory AdminTournamentRow.fromJson(Map<String, dynamic> json) => AdminTournamentRow(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? '',
        format: json['format'] as String? ?? 'solo',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
        finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
      );

  final int id;
  final String name;
  final int size;
  final String status;

  /// `solo` — one player per seat — or `team`, where every seat is a pair
  /// playing each round as one 2v2 duel.
  final String format;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get isTeam => format == 'team';

  String get statusLabel => switch (status) {
        'open' => 'Ochiq',
        'in_progress' => 'Jonli',
        'completed' => 'Yakunlangan',
        'cancelled' => 'Bekor qilindi',
        _ => status,
      };
}

class AdminTournamentParticipantRow {
  const AdminTournamentParticipantRow({
    required this.userId,
    required this.label,
    required this.status,
    required this.seed,
    required this.partnerUserId,
    required this.partnerLabel,
    required this.partnerStatus,
  });

  factory AdminTournamentParticipantRow.fromJson(Map<String, dynamic> json) => AdminTournamentParticipantRow(
        userId: (json['userId'] as num).toInt(),
        label: json['label'] as String? ?? '#${json['userId']}',
        status: json['status'] as String? ?? '',
        seed: (json['seed'] as num?)?.toInt(),
        partnerUserId: (json['partnerUserId'] as num?)?.toInt(),
        partnerLabel: json['partnerLabel'] as String?,
        partnerStatus: json['partnerStatus'] as String?,
      );

  final int userId;
  final String label;
  final String status;
  final int? seed;

  /// The three fields below are filled only for a team tournament's seat, which
  /// two people hold and each answers the invite for themselves.
  final int? partnerUserId;
  final String? partnerLabel;
  final String? partnerStatus;

  String get statusLabel => adminParticipantStatusLabel(status);

  String? get partnerStatusLabel =>
      partnerStatus == null ? null : adminParticipantStatusLabel(partnerStatus!);

  /// Whether this seat counts towards filling the bracket, which for a team
  /// needs both of its members to have accepted — the server's own rule, since
  /// that is what it refuses to start a short bracket on.
  bool get fullyAccepted => status == 'accepted' && (partnerUserId == null || partnerStatus == 'accepted');
}

String adminParticipantStatusLabel(String status) => switch (status) {
      'invited' => 'Taklif qilindi',
      'accepted' => 'Qabul qildi',
      'declined' => 'Rad etdi',
      _ => status,
    };

/// One card of the bracket, flattened out of the nested round/match shape the
/// server sends — the admin table has no use for the tree, only the rows.
class AdminTournamentMatchRow {
  const AdminTournamentMatchRow({
    required this.round,
    required this.slot,
    required this.playerOneLabel,
    required this.playerOnePartnerLabel,
    required this.playerTwoLabel,
    required this.playerTwoPartnerLabel,
    required this.winnerLabel,
    required this.winnerPartnerLabel,
    required this.status,
  });

  final int round;
  final int slot;
  final String playerOneLabel;
  final String playerTwoLabel;
  final String? winnerLabel;
  final String status;

  /// The second member of each side, filled only in a team bracket — the pair
  /// a bracket draws as one seat.
  final String? playerOnePartnerLabel;
  final String? playerTwoPartnerLabel;
  final String? winnerPartnerLabel;

  String get statusLabel => switch (status) {
        'pending' => 'Kutilmoqda',
        'ready' => 'Tayyor',
        'live' => 'Jonli',
        'done' => 'Tugadi',
        _ => status,
      };
}

class AdminTournamentDetail {
  const AdminTournamentDetail({required this.tournament, required this.participants, required this.matches});

  factory AdminTournamentDetail.fromJson(Map<String, dynamic> json) {
    final matches = <AdminTournamentMatchRow>[];
    final bracket = json['bracket'] as Map<String, dynamic>?;
    if (bracket != null) {
      for (final round in (bracket['rounds'] as List? ?? const [])) {
        final roundJson = round as Map<String, dynamic>;
        final roundNumber = (roundJson['round'] as num?)?.toInt() ?? 0;
        for (final match in (roundJson['matches'] as List? ?? const [])) {
          final matchJson = match as Map<String, dynamic>;
          final playerOne = matchJson['playerOne'] as Map<String, dynamic>?;
          final playerTwo = matchJson['playerTwo'] as Map<String, dynamic>?;
          final playerOnePartner = matchJson['playerOnePartner'] as Map<String, dynamic>?;
          final playerTwoPartner = matchJson['playerTwoPartner'] as Map<String, dynamic>?;
          final winnerId = (matchJson['winnerUserId'] as num?)?.toInt();
          final wonBySlotOne = (playerOne?['id'] as num?)?.toInt() == winnerId;
          matches.add(AdminTournamentMatchRow(
            round: roundNumber,
            slot: (matchJson['slot'] as num?)?.toInt() ?? 0,
            playerOneLabel: _playerLabel(playerOne),
            playerOnePartnerLabel: _partnerLabel(playerOnePartner),
            playerTwoLabel: _playerLabel(playerTwo),
            playerTwoPartnerLabel: _partnerLabel(playerTwoPartner),
            winnerLabel: winnerId == null
                ? null
                : wonBySlotOne
                    ? _playerLabel(playerOne)
                    : _playerLabel(playerTwo),
            winnerPartnerLabel: winnerId == null
                ? null
                : _partnerLabel(wonBySlotOne ? playerOnePartner : playerTwoPartner),
            status: matchJson['status'] as String? ?? 'pending',
          ));
        }
      }
    }
    return AdminTournamentDetail(
      tournament: AdminTournamentRow.fromJson(json['tournament'] as Map<String, dynamic>),
      participants: ((json['participants'] as List?) ?? const [])
          .map((e) => AdminTournamentParticipantRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      matches: matches,
    );
  }

  final AdminTournamentRow tournament;
  final List<AdminTournamentParticipantRow> participants;
  final List<AdminTournamentMatchRow> matches;

  static String _playerLabel(Map<String, dynamic>? player) {
    if (player == null) return '—';
    return (player['nickname'] as String?) ?? (player['displayName'] as String?) ?? '#${player['id']}';
  }

  /// The same, for a side's second member — absent throughout a solo bracket,
  /// where there is no teammate to name rather than one still undecided.
  static String? _partnerLabel(Map<String, dynamic>? partner) => partner == null ? null : _playerLabel(partner);
}

class AdminMetrics {
  const AdminMetrics({
    required this.totalUsers,
    required this.bannedUsers,
    required this.battlesToday,
    required this.botBattles,
    required this.humanBattles,
  });

  factory AdminMetrics.fromJson(Map<String, dynamic> json) => AdminMetrics(
        totalUsers: (json['totalUsers'] as num?)?.toInt() ?? 0,
        bannedUsers: (json['bannedUsers'] as num?)?.toInt() ?? 0,
        battlesToday: (json['battlesToday'] as num?)?.toInt() ?? 0,
        botBattles: (json['botBattles'] as num?)?.toInt() ?? 0,
        humanBattles: (json['humanBattles'] as num?)?.toInt() ?? 0,
      );

  final int totalUsers;
  final int bannedUsers;
  final int battlesToday;
  final int botBattles;
  final int humanBattles;

  int get totalBattles => botBattles + humanBattles;

  /// The share of settled duels that were against the fallback bot — the one
  /// ratio that says whether players are finding each other.
  int get botPercent => totalBattles == 0 ? 0 : ((botBattles * 100) / totalBattles).round();
}
