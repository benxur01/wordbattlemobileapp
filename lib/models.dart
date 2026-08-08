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
}

enum NickState { idle, checking, free, taken, bad }


