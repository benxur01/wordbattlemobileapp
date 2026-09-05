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
}

enum NickState { idle, checking, free, taken, bad }


