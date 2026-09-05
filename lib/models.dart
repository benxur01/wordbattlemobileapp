enum WBScreen {
  /// Restoring the saved session before anything is drawn.
  loading,
  /// The backend could not be reached at all — offers a retry.
  offline,
  onb1,
  onb2,
  lobby,
  match,
  duel,
  win,
  lose,
  /// Read-only: a friend's live duel, watched rather than played.
  spectateDuel,
  board,
  profile,
  /// Finished battles, reached from the profile.
  history,
  practice,
  friends,
  invite,
  incoming,
  /// A tournament invite waiting for Accept/Decline.
  tournamentInvite,
  /// The live bracket — reachable by any signed-in player, participant or not.
  tournamentBracket,
  /// The friends screen's "Turnir tashkil qilish": pick a size, then friends.
  organizeTournamentSetup,
  /// The organizer's own view of a tournament they just created.
  organizeTournamentManage,
  /// Every tournament worth discovering, paginated — the lobby's "Barchasini
  /// ko'rish".
  tournamentsBrowse,
  /// A team-duel invite waiting for a friend's answer.
  teamInvite,
  /// A team-duel invite waiting for this player's own Accept/Decline.
  teamIncoming,
  /// The 2v2 queue: both teammates searching together.
  teamQueue,
  /// The live 2v2 duel board.
  teamDuel,
  /// Read-only: a friend's live 2v2 duel, watched rather than played.
  teamSpectateDuel,
  teamWin,
  teamLose,
}

enum NickState { idle, checking, free, taken, bad }


