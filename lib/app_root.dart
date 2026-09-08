import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/api_client.dart';
import 'api/api_config.dart';
import 'api/api_exception.dart';
import 'api/duel_models.dart';
import 'api/game_socket.dart';
import 'api/google_auth.dart';
import 'api/models.dart';
import 'api/session.dart';
import 'api/tournament_models.dart';
import 'models.dart';
import 'theme.dart';
import 'screens/onboarding1_screen.dart';
import 'screens/onboarding2_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/matchmaking_screen.dart';
import 'screens/bot_battle_screen.dart';
import 'screens/duel_screen.dart';
import 'screens/win_screen.dart';
import 'screens/lose_screen.dart';
import 'screens/board_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/history_screen.dart';
import 'screens/practice_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/spectate_duel_screen.dart';
import 'screens/invite_screen.dart';
import 'screens/incoming_screen.dart';
import 'screens/team_invite_screen.dart';
import 'screens/team_incoming_screen.dart';
import 'screens/team_queue_screen.dart';
import 'screens/team_duel_screen.dart';
import 'screens/team_win_screen.dart';
import 'screens/team_lose_screen.dart';
import 'screens/team_spectate_duel_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/tournament_invite_screen.dart';
import 'screens/tournament_bracket_screen.dart';
import 'screens/organize_tournament_screen.dart';
import 'screens/organize_tournament_manage_screen.dart';
import 'screens/tournaments_browse_screen.dart';
import 'widgets/bottom_nav.dart';

/// Drives the whole app off the backend: REST for anything that can wait, and
/// one WebSocket for matchmaking, duels and challenges.
///
/// The screens stay pure — they take data and callbacks. Every rule that
/// decides a duel now lives on the server; this class mirrors what it is told
/// and sends the player's intent back.
/// What a change of app lifecycle means for the player's place in the queue.
enum QueueAction { none, leave, rejoin }

/// Backgrounding the app mid-search should not leave a ghost in the queue —
/// the server would pair a player who is not looking at the screen, and the
/// duel would run its turn timer out unwatched.
///
/// Coming back has to undo that, and for a long time it did not: leaving
/// without ever rejoining left the search screen turning its radar at a server
/// that had already forgotten the player. No opponent was coming, the bot
/// fallback only serves players actually queued, and the sole way out was the
/// cancel button.
///
/// Only the search screen is affected. `inactive` is deliberately not a leave:
/// on iOS it fires for a notification banner or the app switcher preview,
/// which are not backgrounding, and dropping the queue for those would make
/// the search restart constantly.
QueueAction queueActionFor(AppLifecycleState state, WBScreen screen) {
  if (screen != WBScreen.match && screen != WBScreen.teamQueue) return QueueAction.none;
  return switch (state) {
    AppLifecycleState.paused || AppLifecycleState.detached || AppLifecycleState.hidden => QueueAction.leave,
    AppLifecycleState.resumed => QueueAction.rejoin,
    AppLifecycleState.inactive => QueueAction.none,
  };
}

/// Whether a `duel.update` or `duel.finished` frame is about the duel the
/// player is actually in.
///
/// Duel frames used to be taken at face value, and one of them could end a
/// duel that had nothing to do with it: backing out of a battle forfeits it,
/// and the result of that forfeit is written to the database before anyone is
/// told, so a player who backs out and searches again is often already in their
/// next duel by the time the old one's `duel.finished` comes down the same
/// socket. Applied blindly it threw away the live board and dropped the player
/// on a win or lose screen for a battle they had left — while their new
/// opponent went on playing someone who had stopped answering.
///
/// [liveDuelId] null means there is no board to protect, which is the reconnect
/// case: a player coming back after their duel ended is handed the result they
/// missed, and must still be shown it. A frame without an id at all can only
/// come from a server that predates the field, and is let through rather than
/// leaving that app stuck on a duel screen forever.
bool duelFrameApplies(String? liveDuelId, String? frameDuelId) =>
    liveDuelId == null || frameDuelId == null || liveDuelId == frameDuelId;

/// Whether an `invite.declined` or `invite.expired` is about the invite held in
/// one of the app's two slots — the challenge sent, or the one received.
///
/// An invite has no single owner on the wire the way a duel does. The server
/// sends `invite.declined` to whichever of the two players did not press the
/// button, so the identical frame means "the friend you challenged said no" on
/// one socket and "the challenge you were offered has been taken back" on the
/// other. The app read it as the first of those always, which is why an inviter
/// cancelling left the receiver's sheet standing over an invite that no longer
/// existed: tapping accept on it answered `invite_gone`. Read against both
/// slots, the id is the only thing that tells the two apart.
///
/// [pendingInviteId] null is deliberately *not* the free pass [duelFrameApplies]
/// gives an absent duel. A duel result with no board to protect still has to be
/// shown to the player; an invite reply with no invite to clear must not tear
/// down a screen it cannot be about — it is the race described on
/// [inviteSentActionFor], and it is remembered rather than acted on. A frame
/// naming no invite at all can only come from a server predating the field and
/// clears whatever is waiting, as it always did.
bool inviteFrameApplies(String? pendingInviteId, String? frameInviteId) =>
    pendingInviteId != null && (frameInviteId == null || frameInviteId == pendingInviteId);

/// What to do with an `invite.sent` by the time it actually lands.
enum InviteSentAction {
  /// Raise the "waiting for an answer" screen — the ordinary case.
  open,

  /// Take the challenge back. The player has moved on to something the invite
  /// must not interrupt, and a friend accepting it would start a duel nobody is
  /// watching.
  withdraw,

  /// The invite is already dead: its refusal overtook its confirmation. Nothing
  /// to show, and nothing left to withdraw.
  drop,
}

/// Decides that, from the screen the player is on and what the app already
/// knows about the invite being confirmed.
///
/// The two frames an invite produces leave on two different sockets — the
/// player being challenged is told first, the player who challenged second — so
/// the app cannot assume its own confirmation arrives before the answer to it.
/// A scripted client run against the live server declined instantly and what
/// came down the inviter's socket was `invite.declined`, with `invite.sent`
/// never arriving at all. Turned around, the same race hands the app the
/// confirmation of an invite that is already refused, and the app opened a
/// "waiting for X" screen on it. Nothing was ever coming to close that screen:
/// the server expires invites out of its own map and had already dropped this
/// one, so the countdown ran to 0:00 and stopped there with the cancel button
/// as the only way off. Hence [drop], and hence the app remembering the id of a
/// reply it could not place.
///
/// [withdraw] is the other half — what the player did while the confirmation
/// was in flight. The frame used to set the screen unconditionally, so a
/// confirmation delayed past a `match.found` (tap Jang, give up, search, get
/// paired) pulled the player off a live board with their turn timer still
/// running on it, and sent no forfeit either, because the screen was changed by
/// a frame rather than by `go`. A search and a result just delivered are the
/// same story with less at stake. Everywhere else the screen is raised: it is
/// the only place a live challenge can be seen and cancelled, so wandering to
/// the lobby or the leaderboard in the moment before the server answers must
/// not lose the player their only handle on it.
InviteSentAction inviteSentActionFor({
  required WBScreen screen,
  required String inviteId,
  required String? settledInviteId,
}) {
  if (inviteId == settledInviteId) return InviteSentAction.drop;
  return switch (screen) {
    WBScreen.duel ||
    WBScreen.match ||
    WBScreen.win ||
    WBScreen.lose ||
    WBScreen.teamDuel ||
    WBScreen.teamQueue ||
    WBScreen.teamWin ||
    WBScreen.teamLose =>
      InviteSentAction.withdraw,
    _ => InviteSentAction.open,
  };
}

/// The seconds an invite has left, or null once the wait is over.
///
/// Null is the whole point. The countdown used to be a display and nothing
/// more: it reached zero and the screen sat on 0:00, waiting for an
/// `invite.expired` that could not come, because the server sweeps its own map
/// and an invite already refused, withdrawn, or lost with a dropped socket is
/// no longer in it. The clock running out is the app's own evidence that the
/// wait is over and is now acted on.
///
/// A missing [startedAt] counts as over for the same reason: an invite screen
/// with no clock behind it has nothing left to wait for, and the screens draw a
/// vanished invite as an empty rectangle with only the system back button off
/// it. One clock serves both directions, so it can also be left over from the
/// other one — always from further in the past, which can only end a wait early
/// and never extend one past its window.
int? inviteSecondsLeftAt(DateTime? startedAt, int secondsLeft, DateTime now) {
  if (startedAt == null) return null;
  final left = secondsLeft - now.difference(startedAt).inSeconds;
  return left <= 0 ? null : left;
}

/// The frame leaving [from] for [next] owes the server, or null when the move
/// commits the player to nothing.
///
/// Two screens are a standing claim on the server's side: the duel screen says
/// this player is playing, the search screen says they are waiting to be
/// paired. Walking off either has to be said out loud — and the saying was the
/// part taken on trust. `go` wrote the frame and changed the screen whether or
/// not the write reached anybody, so a socket that happened to be reconnecting
/// swallowed the forfeit whole: the app went to the lobby, the server kept the
/// duel, and the next `duel.update` for it dropped the player back onto a board
/// they had walked out of, since there was no board left in memory to weigh it
/// against.
///
/// Naming the frame here rather than inline in `go` is what lets that be
/// checked at all — the answer to "was it delivered" needs something to ask
/// about.
String? exitFrameFor(WBScreen from, WBScreen next) {
  if (from == next) return null;
  return switch (from) {
    WBScreen.duel => 'duel.forfeit',
    WBScreen.match => 'queue.leave',
    WBScreen.teamDuel => 'team_duel.forfeit',
    WBScreen.teamQueue => 'team.queue.leave',
    _ => null,
  };
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  final ApiClient _api = ApiClient();
  late final Session _session = Session(_api);
  final GameSocket _socket = GameSocket();
  final GoogleAuth _google = GoogleAuth();
  final AppLinks _appLinks = AppLinks();

  WBScreen screen = WBScreen.loading;
  String? banner; // transient error / notice shown over the current screen

  // ---- account ----
  UserDto? me;
  bool busy = false;

  // ---- onboarding ----
  String nickname = '';
  NickState nickState = NickState.idle;
  String nickError = '';
  List<String> nickSuggestions = const [];
  Timer? _nickDebounce;
  int _nickRequest = 0;

  // ---- social ----
  int onlineCount = 0;
  List<FriendDto> friends = const [];
  List<FriendRequestDto> friendRequests = const [];
  List<UserDto> searchResults = const [];
  String search = '';
  Timer? _searchDebounce;
  final Set<int> _sentRequests = {};

  // ---- board / profile / practice ----
  bool boardGlobal = true;
  LeaderboardDto? board;
  ProfileDto? profile;
  List<MatchSummaryDto>? history;
  PracticeWordDto? practiceWord;
  List<String> practiceHints = const [];

  // ---- realtime ----
  DuelView? duel;
  FinishedDuel? finished;
  String duelError = '';
  PendingInvite? outgoingInvite;
  PendingInvite? incomingInvite;
  DateTime? queuedAt;
  DateTime? _inviteStartedAt;
  int _inviteSecondsLeft = 0;

  /// How strong a bot the picker is currently offering to play. Set from this
  /// player's own rating each time the screen is opened — an opponent about
  /// their own strength is the one place a slider like this can honestly start
  /// from — and left alone after that, so a player who dragged it somewhere
  /// they liked keeps that setting for as long as they stay on the screen.
  int botRating = 400;

  /// The topics the picker offers, fetched once — see [_loadBotThemes] — and
  /// the one currently picked, by id. Null is the full dictionary, which is
  /// what the picker opens on and what every other duel in the app plays with.
  /// Unlike [botRating] this is not reset when the screen is reopened: it was
  /// chosen outright rather than derived from anything.
  List<WordThemeDto> botThemes = const [];
  String? botTheme;

  /// Chat exchanged in the current duel only — never persisted, and cleared
  /// the moment that duel ends or the screen is left.
  List<DuelChatMessage> duelChat = const [];
  DuelReaction? duelReaction;
  int _reactionSeq = 0;

  /// What is left of this duel's power-ups. Only a bot practice has any, and
  /// only the server may say a charge is gone — this is what it has said so
  /// far, which is why it is reset with the duel rather than with the screen.
  DuelPowerUps duelPowerUps = const DuelPowerUps();

  /// A friend's duel currently being watched, rebuilt whole from every
  /// `duel.spectate_state` frame — null whenever nobody is being spectated.
  SpectateState? spectating;
  final ScrollController spectateScrollController = ScrollController();

  /// The same, for a friend who turned out to be in a 2v2 duel instead —
  /// rebuilt from every `team_duel.spectate_state` frame. Which of the two the
  /// server sends is its own decision, made from the duel the friend is
  /// actually in; the app asks to watch a person either way.
  TeamSpectateState? teamSpectating;
  final ScrollController teamSpectateScrollController = ScrollController();

  // ---- team duels ----
  /// The friend this player has formed a 2v2 team with — null whenever no
  /// team is currently formed. Set by `team.formed`, cleared by
  /// `team.disbanded` or this player's own `team.cancel`. Outlives a single
  /// duel: the team can queue again without being re-formed.
  UserDto? teamPartner;
  TeamDuelView? teamDuel;
  TeamFinishedDuel? teamFinished;
  String teamDuelError = '';
  PendingTeamInvite? outgoingTeamInvite;
  PendingTeamInvite? incomingTeamInvite;
  DateTime? teamQueuedAt;
  DateTime? _teamInviteStartedAt;
  int _teamInviteSecondsLeft = 0;

  /// The team duel's own chat and latest reaction — [duelChat] and
  /// [duelReaction] again, kept apart from them because both modes' state is,
  /// and carrying the sender's name, which a 1v1 line never needed.
  List<TeamChatMessage> teamChat = const [];
  TeamReaction? teamReaction;

  /// Mirrors [_settledInviteId], for the team-invite channel — see
  /// [inviteSentActionFor] and [inviteFrameApplies], which serve both.
  String? _settledTeamInviteId;

  final ScrollController teamChainScrollController = ScrollController();

  // ---- tournaments ----
  TournamentInvite? tournamentInvite;
  TournamentMatchPrompt? tournamentMatchReady;
  TournamentSummary? activeTournament;
  TournamentDetail? tournamentDetail;
  int? _viewingTournamentId;

  /// The friends-screen "Turnir tashkil qilish" flow: the tournament being set
  /// up, and who has answered so far.
  TournamentSummary? organizingTournament;
  List<TournamentParticipantView>? organizingParticipants;

  /// The lobby's "Barchasini ko'rish": every tournament worth discovering,
  /// paginated.
  List<TournamentSummary> tournamentBrowseList = const [];
  bool _tournamentBrowseLoading = false;
  bool _tournamentBrowseLoadingMore = false;
  bool _tournamentBrowseHasMore = true;
  int _tournamentBrowsePage = 0;
  static const _tournamentBrowsePageSize = 20;

  /// An invite the app was told about only by its ending. It is always one we
  /// sent — see [_settleInvite] — and holding its id is what lets the
  /// confirmation still in flight for it be dropped instead of opening a screen
  /// on a challenge that is already over.
  String? _settledInviteId;

  WBTab? previousNavTab;

  final ScrollController chainScrollController = ScrollController();

  Timer? _ticker;
  StreamSubscription<SocketEvent>? _socketEvents;
  StreamSubscription<SocketStatus>? _socketStatus;
  StreamSubscription<Uri>? _linkSub;

  /// A shared link that arrived before there was a session to open it with —
  /// see [_handleDeepLink], which parks it here, and [_openPendingDeepLink],
  /// which spends it.
  Uri? _pendingDeepLink;

  DateTime _lastTick = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _onTick());
    _bootstrap();
    _listenForDeepLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _nickDebounce?.cancel();
    _searchDebounce?.cancel();
    _socketEvents?.cancel();
    _socketStatus?.cancel();
    _linkSub?.cancel();
    _socket.dispose();
    _api.close();
    chainScrollController.dispose();
    spectateScrollController.dispose();
    teamSpectateScrollController.dispose();
    teamChainScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (queueActionFor(state, screen)) {
      case QueueAction.leave:
        _socket.send(screen == WBScreen.teamQueue ? 'team.queue.leave' : 'queue.leave');
      case QueueAction.rejoin:
        _rejoinQueue();
      case QueueAction.none:
        break;
    }
  }

  /// Puts the player back in the queue they were taken out of. Safe to call
  /// when they are already in it: the server keeps the wait they had served
  /// rather than starting the rating window over.
  void _rejoinQueue() {
    if (screen == WBScreen.match) {
      _socket.send('queue.join');
    } else if (screen == WBScreen.teamQueue) {
      _socket.send('team.queue.join');
    }
  }

  // -------------------------------------------------------------- bootstrap

  /// Guarded like every other action on this class, and for a reason the others
  /// do not have: the offline screen's retry lands here, and two taps on it
  /// used to start two restores that both reached [_connectSocket] — see
  /// [GameSocket.connect] for what a second dial did to the first socket.
  Future<void> _bootstrap() async {
    if (busy) return;
    setState(() {
      busy = true;
      screen = WBScreen.loading;
      banner = null;
    });
    try {
      final restored = await _session.restore();
      if (!mounted) return;
      if (restored) {
        me = _session.user;
        _connectSocket();
        setState(() {
          busy = false;
          screen = me?.nickname == null ? WBScreen.onb2 : WBScreen.lobby;
        });
        unawaited(_refreshSocial());
        unawaited(_refreshActiveTournament());
        _openPendingDeepLink();
      } else {
        setState(() {
          busy = false;
          screen = WBScreen.onb1;
        });
      }
    } on ApiException catch (e) {
      // The token survives this: the server could not be reached, which says
      // nothing about whether it is still good. The offline screen retries.
      _showOffline(e.message);
    } catch (_) {
      // A response we could not make sense of. Rare, but letting it escape
      // leaves the app on the loading screen with no way forward.
      _showOffline("Serverga ulanib bo'lmadi");
    }
  }

  void _showOffline(String message) {
    if (!mounted) return;
    setState(() {
      busy = false;
      screen = WBScreen.offline;
      banner = message;
    });
  }

  void _connectSocket() {
    final token = _session.token;
    if (token == null) return;

    _socketEvents?.cancel();
    _socketStatus?.cancel();
    // The handler has its own boundary — see [_onSocketEvent] — which covers a
    // frame it cannot read. This covers the other half: an error put on the
    // stream itself, which no `try` inside the handler can see and which would
    // otherwise leave the app with a dead subscription and no notice.
    _socketEvents = _socket.events.listen(_onSocketEvent, onError: (Object _) => _onBadFrame());
    _socketStatus = _socket.status.listen((status) {
      if (!mounted) return;
      if (status == SocketStatus.disconnected) {
        setState(() => banner = 'Aloqa uzildi — qayta ulanmoqda…');
        unawaited(_probeSessionAfterDropouts());
      } else if (status == SocketStatus.connected) {
        setState(() => banner = null);
      }
    });
    _socket.connect(token);
  }

  // ------------------------------------------------------------------- auth

  /// The onboarding button: the phone gets an idToken from Google, the server
  /// checks it with Google and hands back the session the rest of the app runs
  /// on. The only production way in.
  Future<void> loginWithGoogle() async {
    if (busy) return;
    setState(() {
      busy = true;
      banner = null;
    });
    try {
      final idToken = await _google.signIn();
      if (idToken == null) {
        // The account sheet was dismissed — nothing went wrong, so no banner.
        if (mounted) setState(() => busy = false);
        return;
      }
      await _completeLogin(await _api.loginWithGoogle(idToken));
    } on ApiException catch (e) {
      _loginFailed(e);
    }
  }

  /// Development escape hatch, offered only while [ApiConfig.googleServerClientId]
  /// is still the placeholder — without it there would be no way into the app
  /// before the real client ID is pasted in. It disappears the moment one is.
  Future<void> loginDev() async {
    if (busy) return;
    setState(() {
      busy = true;
      banner = null;
    });
    try {
      final id = DateTime.now().millisecondsSinceEpoch % 1000000000;
      await _completeLogin(await _api.loginDev('player$id'));
    } on ApiException catch (e) {
      _loginFailed(e);
    }
  }

  /// Instagram-style sign-up: the player picks the nickname and password
  /// themselves, straight on the first onboarding screen.
  Future<void> registerWithPassword(String nickname, String password) async {
    if (busy) return;
    setState(() {
      busy = true;
      banner = null;
    });
    try {
      await _completeLogin(await _api.registerWithPassword(nickname, password));
    } on ApiException catch (e) {
      _loginFailed(e);
    }
  }

  /// Signs back in with the nickname and password chosen at registration.
  Future<void> loginWithPassword(String nickname, String password) async {
    if (busy) return;
    setState(() {
      busy = true;
      banner = null;
    });
    try {
      await _completeLogin(await _api.loginWithPassword(nickname, password));
    } on ApiException catch (e) {
      _loginFailed(e);
    }
  }

  Future<void> _completeLogin(({String token, UserDto user, bool needsNickname}) result) async {
    await _session.save(result.token, result.user);
    if (!mounted) return;
    me = result.user;
    _connectSocket();
    setState(() {
      busy = false;
      screen = result.needsNickname ? WBScreen.onb2 : WBScreen.lobby;
    });
    unawaited(_refreshSocial());
    unawaited(_refreshActiveTournament());
    _openPendingDeepLink();
  }

  void _loginFailed(ApiException e) {
    if (!mounted) return;
    setState(() {
      busy = false;
      banner = e.message;
    });
  }

  // ------------------------------------------------------- session lifetime

  /// True when the failure means the session is over rather than that one call
  /// went wrong — see [ApiException.endsSession], which [Session.restore] holds
  /// to the same rule.
  bool _isSessionOver(ApiException e) => e.endsSession;

  /// The single place an API failure is turned into UI. Anything that ends the
  /// session drops it and returns to onboarding; everything else is a banner.
  /// Before this existed a token that expired mid-session left the app in a
  /// reconnect loop with no way out but reinstalling.
  void _onApiError(ApiException e) {
    if (!mounted) return;
    if (_isSessionOver(e)) {
      unawaited(_endSession("Sessiya tugadi — qaytadan kiring"));
      return;
    }
    setState(() => banner = e.message);
  }

  /// Drops everything tied to the logged-in player and returns to onboarding.
  Future<void> _endSession(String? notice, {bool forgetGoogle = true}) async {
    _socketEvents?.cancel();
    _socketStatus?.cancel();
    _socketEvents = null;
    _socketStatus = null;
    await _socket.disconnect();
    if (forgetGoogle) await _google.signOut();
    await _session.clear();
    if (!mounted) return;
    setState(() {
      me = null;
      profile = null;
      board = null;
      history = null;
      friends = const [];
      friendRequests = const [];
      searchResults = const [];
      search = '';
      _sentRequests.clear();
      duel = null;
      finished = null;
      outgoingInvite = null;
      incomingInvite = null;
      _settledInviteId = null;
      _inviteStartedAt = null;
      queuedAt = null;
      teamPartner = null;
      teamDuel = null;
      teamFinished = null;
      outgoingTeamInvite = null;
      incomingTeamInvite = null;
      _settledTeamInviteId = null;
      _teamInviteStartedAt = null;
      teamQueuedAt = null;
      tournamentInvite = null;
      tournamentMatchReady = null;
      activeTournament = null;
      tournamentDetail = null;
      _viewingTournamentId = null;
      organizingTournament = null;
      organizingParticipants = null;
      tournamentBrowseList = const [];
      _tournamentBrowseLoading = false;
      _tournamentBrowseLoadingMore = false;
      _tournamentBrowseHasMore = true;
      _tournamentBrowsePage = 0;
      nickname = '';
      nickState = NickState.idle;
      busy = false;
      banner = notice;
      screen = WBScreen.onb1;
    });
  }

  /// The profile screen's "Chiqish".
  Future<void> logout() => _endSession(null);

  /// The profile screen's "Akkauntni o'chirish", after its confirmation.
  Future<void> deleteAccount() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await _api.deleteAccount();
      await _endSession("Akkaunt o'chirildi");
    } on ApiException catch (e) {
      // A token that is already dead means the account is gone either way.
      if (_isSessionOver(e)) {
        await _endSession("Akkaunt o'chirildi");
        return;
      }
      if (!mounted) return;
      setState(() {
        busy = false;
        banner = e.message;
      });
    }
  }

  /// The socket cannot report a 401: a refused handshake looks exactly like a
  /// dead network. After a couple of failed reconnects the token is checked
  /// over REST, which can say which one it is.
  Future<void> _probeSessionAfterDropouts() async {
    if (_session.token == null || _socket.failedAttempts < 2) return;
    try {
      await _api.me();
    } on ApiException catch (e) {
      if (_isSessionOver(e)) await _endSession("Sessiya tugadi — qaytadan kiring");
    }
  }

  // --------------------------------------------------------------- nickname

  void setNick(String value) {
    final raw = value.length > 16 ? value.substring(0, 16) : value;
    _nickDebounce?.cancel();

    setState(() {
      nickname = raw;
      nickSuggestions = const [];
      nickError = '';
      nickState = raw.trim().isEmpty ? NickState.idle : NickState.checking;
    });
    if (raw.trim().isEmpty) return;

    // The server owns the rules; ask it, but not on every keystroke.
    final request = ++_nickRequest;
    _nickDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final result = await _api.checkNickname(raw);
        if (!mounted || request != _nickRequest) return;
        setState(() {
          if (result.available) {
            nickState = NickState.free;
            nickError = '';
          } else if (result.suggestions.isNotEmpty) {
            nickState = NickState.taken;
            nickSuggestions = result.suggestions;
          } else {
            nickState = NickState.bad;
            nickError = result.reason ?? 'Taxallus mos emas';
          }
        });
      } on ApiException catch (e) {
        if (!mounted || request != _nickRequest) return;
        setState(() {
          nickState = NickState.bad;
          nickError = e.message;
        });
      }
    });
  }

  Future<void> claimNickname() async {
    if (busy || nickState != NickState.free) return;
    setState(() => busy = true);
    try {
      final user = await _api.claimNickname(nickname);
      if (!mounted) return;
      me = user;
      setState(() {
        busy = false;
        screen = WBScreen.lobby;
      });
      unawaited(_refreshSocial());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        // Someone claimed it between the check and the save.
        nickState = e.code == 'nickname_taken' ? NickState.taken : NickState.bad;
        nickError = e.message;
      });
    }
  }

  // ---------------------------------------------------------------- loading

  /// The one failure a loader could not report, and the only one that stranded
  /// a screen for good.
  ///
  /// `on ApiException` covers the call going wrong; it does not cover the call
  /// going right and the body not being what this version of the app knows how
  /// to read — a field dropped, a date in a shape `DateTime.parse` refuses,
  /// either of which a rolling deploy can serve for as long as it takes to roll.
  /// That throws a `FormatException` or a `TypeError` from inside the `try`,
  /// matches no `on` clause, and escapes an `unawaited` future where nothing is
  /// waiting to catch it. The screen keeps its spinner — no banner, no retry,
  /// nothing but leaving and coming back. [_bootstrap] has had the same
  /// fallback since the day a malformed session response did this to the
  /// loading screen; the loaders were simply never given one.
  void _onLoadFailure() {
    if (!mounted) return;
    setState(() => banner = "Ma'lumotni o'qib bo'lmadi");
  }

  Future<void> _refreshSocial() async {
    try {
      final friendList = await _api.friends();
      final requests = await _api.friendRequests();
      if (!mounted) return;
      setState(() {
        friends = friendList;
        friendRequests = requests;
      });
    } on ApiException catch (e) {
      // The lobby still works without the counters, so a failure here is
      // silent — unless it is the session itself that has gone.
      if (_isSessionOver(e)) _onApiError(e);
    } catch (_) {
      // Silent for the same reason, and unlike the loaders below there is no
      // spinner behind this one: the friends list keeps whatever it last had.
      // Caught all the same, because escaping is what does the damage.
    }
  }

  Future<void> _loadBoard() async {
    try {
      final data = boardGlobal ? await _api.globalLeaderboard() : await _api.friendsLeaderboard();
      if (!mounted) return;
      setState(() => board = data);
    } on ApiException catch (e) {
      _onApiError(e);
    } catch (_) {
      _onLoadFailure();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _api.profile();
      if (!mounted) return;
      setState(() {
        profile = data;
        me = data.user;
      });
    } on ApiException catch (e) {
      _onApiError(e);
    } catch (_) {
      _onLoadFailure();
    }
  }

  /// The list is left in place while it reloads, so returning to the screen
  /// shows the battles it had rather than flashing the spinner again.
  Future<void> _loadHistory() async {
    try {
      final data = await _api.matchHistory();
      if (!mounted) return;
      setState(() => history = data);
    } on ApiException catch (e) {
      _onApiError(e);
    } catch (_) {
      _onLoadFailure();
    }
  }

  Future<void> _loadPractice() async {
    try {
      final word = await _api.practiceWord();
      if (!mounted) return;
      setState(() {
        practiceWord = word;
        practiceHints = const [];
      });
    } on ApiException catch (e) {
      _onApiError(e);
    } catch (_) {
      _onLoadFailure();
    }
  }

  /// The bot picker's topic row. Fetched only while it is empty: the themes a
  /// server build offers cannot change under a running app. Silent on failure
  /// like [_refreshActiveTournament] — without them the picker is the strength
  /// slider it was before themes existed, which is a working screen.
  Future<void> _loadBotThemes() async {
    if (botThemes.isNotEmpty) return;
    try {
      final list = await _api.wordThemes();
      if (!mounted) return;
      setState(() => botThemes = list);
    } on ApiException catch (e) {
      if (_isSessionOver(e)) _onApiError(e);
    } catch (_) {
      // Silent, as above.
    }
  }

  Future<void> loadHints() async {
    final word = practiceWord;
    if (word == null) return;
    try {
      final hints = await _api.practiceHints(word.word.substring(word.word.length - 1));
      if (mounted) setState(() => practiceHints = hints);
    } on ApiException catch (_) {
      // The hint button is optional; stay quiet if it fails.
    }
  }

  // ------------------------------------------------------------ tournaments

  /// The lobby's low-key "a tournament is being played" card. Silent on
  /// failure, the same way `_refreshSocial` is: the lobby works without it.
  Future<void> _refreshActiveTournament() async {
    try {
      final list = await _api.activeTournaments();
      if (!mounted) return;
      setState(() => activeTournament = list.isEmpty ? null : list.first);
    } on ApiException catch (e) {
      if (_isSessionOver(e)) _onApiError(e);
    } catch (_) {
      // Silent, as above.
    }
  }

  Future<void> _loadTournamentDetail(int id) async {
    try {
      final data = await _api.tournamentDetail(id);
      if (!mounted) return;
      setState(() => tournamentDetail = data);
    } on ApiException catch (e) {
      _onApiError(e);
    } catch (_) {
      _onLoadFailure();
    }
  }

  /// Opens the bracket screen — for the tournament's own participants and for
  /// a spectator alike, since the screen is read-only either way.
  void openTournamentBracket(int id) {
    setState(() {
      _viewingTournamentId = id;
      tournamentDetail = null;
    });
    go(WBScreen.tournamentBracket);
    unawaited(_loadTournamentDetail(id));
  }

  /// The bracket screen's own "Ha, bekor qilish" — only ever wired up for the
  /// tournament's own organizer (see [TournamentBracketScreen]'s visibility
  /// check), so unlike [cancelOrganizedTournament] this acts on whichever
  /// tournament is currently open rather than the one just being set up.
  Future<void> cancelViewedTournament() async {
    final detail = tournamentDetail;
    if (detail == null || busy) return;
    setState(() => busy = true);
    try {
      await _api.cancelTournament(detail.id);
      if (!mounted) return;
      setState(() {
        busy = false;
        tournamentDetail = null;
      });
      go(WBScreen.lobby);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        banner = e.message;
      });
    }
  }

  /// Wires up Android App Links: a tournament shared as
  /// `https://wordbattle.example.uz/t/<id>` and tapped while the app is
  /// already installed lands straight on that tournament's bracket — see
  /// [_handleDeepLink]. iOS has no Universal Links entitlement yet, so a
  /// shared link there never reaches this app at all; it just opens in a
  /// browser, which is the expected fallback for now.
  void _listenForDeepLinks() {
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });
    _linkSub = _appLinks.uriLinkStream.listen(_handleDeepLink, onError: (Object _) {});
  }

  /// Parses `/t/<id>` out of a shared tournament link and jumps to its
  /// bracket, the same screen [openTournamentBracket] already opens from the
  /// lobby's own "active tournament" card.
  ///
  /// A link that arrives before login has finished has nowhere to land yet:
  /// [me] is only ever set once a session is restored or a login completes,
  /// which is the same "signed in" point every tournament REST call already
  /// waits for (see the calls right after [_bootstrap] and [_completeLogin]).
  /// A cold launch runs [_bootstrap] unawaited, so the tap that started the
  /// app reliably loses that race — the link waits in [_pendingDeepLink] and
  /// is opened from those two places instead of being thrown away.
  void _handleDeepLink(Uri uri) {
    if (!mounted) return;
    if (me == null) {
      _pendingDeepLink = uri;
      return;
    }
    final segments = uri.pathSegments;
    if (segments.length != 2 || segments[0] != 't') return;
    final id = int.tryParse(segments[1]);
    if (id == null) return;
    openTournamentBracket(id);
  }

  /// Opens the link that was waiting on sign-in, if there was one. Only one is
  /// ever held: a second link arriving before the first could be opened is the
  /// newer intent, and the older one is what the player has already moved on
  /// from.
  void _openPendingDeepLink() {
    final pending = _pendingDeepLink;
    if (pending == null) return;
    _pendingDeepLink = null;
    _handleDeepLink(pending);
  }

  void openTournamentInvite() => go(WBScreen.tournamentInvite);

  void acceptTournamentInvite() {
    final invite = tournamentInvite;
    if (invite == null) return;
    _socket.send('tournament.accept', {'tournamentId': invite.tournamentId});
    setState(() => tournamentInvite = null);
    go(WBScreen.lobby);
  }

  void declineTournamentInvite() {
    final invite = tournamentInvite;
    if (invite == null) return;
    _socket.send('tournament.decline', {'tournamentId': invite.tournamentId});
    setState(() => tournamentInvite = null);
    go(WBScreen.lobby);
  }

  /// The lobby's "Boshlash" tap on a ready tournament match. Either player may
  /// press it — both already committed to playing by accepting the tournament
  /// — and the duel that follows arrives through the ordinary `match.found`
  /// path, tagged as a tournament match only on the server.
  void startReadyTournamentMatch() {
    final ready = tournamentMatchReady;
    if (ready == null) return;
    _socket.send('tournament.match_start', {'tournamentMatchId': ready.tournamentMatchId});
    setState(() => tournamentMatchReady = null);
  }

  // --------------------------------------------- tournaments: self-organized

  void openOrganizeTournament() => go(WBScreen.organizeTournamentSetup);

  /// The organize screen's "Taklif yuborish"/"Turnir yaratish": creates the
  /// tournament, then — for a friends-only one — invites every chosen friend
  /// one by one, the server checking each against the friend list itself so a
  /// friend removed in the meantime is simply skipped rather than failing the
  /// whole batch. A public tournament has no invitees to loop over — strangers
  /// self-join later from the browse screen instead.
  Future<void> createAndInviteTournament(int size, List<UserDto> invitees, bool isPublic) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final created = await _api.createTournament("${me?.label ?? "O'yinchi"} turniri", size, isPublic);
      var failed = 0;
      if (!isPublic) {
        for (final invitee in invitees) {
          try {
            await _api.inviteToTournament(created.id, invitee.id);
          } on ApiException {
            failed++;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        busy = false;
        organizingTournament = created;
        organizingParticipants = null;
        banner = failed == 0 ? null : "$failed ta taklifni yuborib bo'lmadi";
      });
      go(WBScreen.organizeTournamentManage);
      unawaited(_loadOrganizingParticipants());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        banner = e.message;
      });
    }
  }

  /// The 2v2 half of [createAndInviteTournament]: creates a `team` tournament
  /// — always friends-only, since nobody can self-join one — and invites each
  /// chosen pair with a single call, the server checking the organizer against
  /// both members of it.
  Future<void> createAndInviteTeamTournament(int size, List<(UserDto, UserDto)> teams) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final created = await _api.createTournament("${me?.label ?? "O'yinchi"} turniri", size, false, format: 'team');
      var failed = 0;
      for (final team in teams) {
        try {
          await _api.inviteTeamToTournament(created.id, team.$1.id, team.$2.id);
        } on ApiException {
          failed++;
        }
      }
      if (!mounted) return;
      setState(() {
        busy = false;
        organizingTournament = created;
        organizingParticipants = null;
        banner = failed == 0 ? null : "$failed ta jamoani taklif qilib bo'lmadi";
      });
      go(WBScreen.organizeTournamentManage);
      unawaited(_loadOrganizingParticipants());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        banner = e.message;
      });
    }
  }

  Future<void> _loadOrganizingParticipants() async {
    final tournament = organizingTournament;
    if (tournament == null) return;
    try {
      final rows = await _api.tournamentParticipants(tournament.id);
      if (!mounted) return;
      setState(() => organizingParticipants = rows);
    } on ApiException catch (e) {
      _onApiError(e);
    } catch (_) {
      _onLoadFailure();
    }
  }

  /// The manage screen's "Turnirni boshlash", once everyone invited has
  /// accepted. Success drops straight into the live bracket — the same screen
  /// any spectator or participant would open on it.
  Future<void> startOrganizedTournament() async {
    final tournament = organizingTournament;
    if (tournament == null || busy) return;
    setState(() => busy = true);
    try {
      await _api.startTournament(tournament.id);
      if (!mounted) return;
      setState(() {
        busy = false;
        organizingTournament = null;
        organizingParticipants = null;
      });
      openTournamentBracket(tournament.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        // The server counts seats and phrases `not_ready` as "N/M o'yinchi",
        // which reads wrong for a 2v2 bracket where a seat is a whole team.
        banner = tournament.isTeam && e.code == 'not_ready' ? "Barcha jamoalar hali qabul qilmadi" : e.message;
      });
    }
  }

  /// The manage screen's "Ha, bekor qilish" — calls the tournament off for
  /// good and drops the organizer back to the lobby, the same place leaving
  /// it unstarted already does.
  Future<void> cancelOrganizedTournament() async {
    final tournament = organizingTournament;
    if (tournament == null || busy) return;
    setState(() => busy = true);
    try {
      await _api.cancelTournament(tournament.id);
      if (!mounted) return;
      setState(() {
        busy = false;
        organizingTournament = null;
        organizingParticipants = null;
      });
      go(WBScreen.lobby);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        banner = e.message;
      });
    }
  }

  void leaveOrganizingTournament() {
    setState(() {
      organizingTournament = null;
      organizingParticipants = null;
    });
    go(WBScreen.lobby);
  }

  // ------------------------------------------------------- tournaments: browse

  /// The lobby's "Barchasini ko'rish".
  void openTournamentsBrowse() {
    setState(() {
      tournamentBrowseList = const [];
      _tournamentBrowsePage = 0;
      _tournamentBrowseHasMore = true;
    });
    go(WBScreen.tournamentsBrowse);
    unawaited(_loadTournamentsBrowse(0));
  }

  /// Loads page 0 fresh, replacing whatever the list already held; loads any
  /// later page onto the end of it instead — the browse screen's own "Yana
  /// ko'rsatish".
  Future<void> _loadTournamentsBrowse(int page) async {
    final loadingMore = page > 0;
    setState(() {
      if (loadingMore) {
        _tournamentBrowseLoadingMore = true;
      } else {
        _tournamentBrowseLoading = true;
      }
    });
    try {
      final rows = await _api.listTournaments(page: page, size: _tournamentBrowsePageSize);
      if (!mounted) return;
      setState(() {
        _tournamentBrowseLoading = false;
        _tournamentBrowseLoadingMore = false;
        _tournamentBrowsePage = page;
        _tournamentBrowseHasMore = rows.length == _tournamentBrowsePageSize;
        tournamentBrowseList = page == 0 ? rows : [...tournamentBrowseList, ...rows];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _tournamentBrowseLoading = false;
        _tournamentBrowseLoadingMore = false;
      });
      _onApiError(e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tournamentBrowseLoading = false;
        _tournamentBrowseLoadingMore = false;
      });
      _onLoadFailure();
    }
  }

  void loadMoreTournamentsBrowse() {
    if (_tournamentBrowseLoading || _tournamentBrowseLoadingMore || !_tournamentBrowseHasMore) return;
    unawaited(_loadTournamentsBrowse(_tournamentBrowsePage + 1));
  }

  /// The browse screen's "Qo'shilish": self-joins a public or global
  /// tournament that's still open. `tournament_not_joinable` and
  /// `rating_too_low` arrive with their own Uzbek message from the server,
  /// same as every other failure this class only ever shows as a banner.
  Future<void> joinTournament(int tournamentId) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final joined = await _api.joinTournament(tournamentId);
      if (!mounted) return;
      setState(() {
        busy = false;
        tournamentBrowseList = [for (final t in tournamentBrowseList) t.id == joined.id ? joined : t];
      });
      openTournamentBracket(joined.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        banner = e.message;
      });
    }
  }

  // ----------------------------------------------------------------- social

  void setSearch(String value) {
    setState(() => search = value);
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => searchResults = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await _api.searchUsers(value.trim());
        if (mounted) setState(() => searchResults = results);
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => searchResults = const []);
        if (_isSessionOver(e)) _onApiError(e);
      }
    });
  }

  Future<void> sendFriendRequest(UserDto user) async {
    setState(() => _sentRequests.add(user.id));
    try {
      await _api.sendFriendRequest(user.id);
      await _refreshSocial();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sentRequests.remove(user.id);
        banner = e.message;
      });
    }
  }

  bool requestSentTo(int userId) => _sentRequests.contains(userId);

  Future<void> acceptRequest(FriendRequestDto request) async {
    setState(() => friendRequests = friendRequests.where((r) => r.id != request.id).toList());
    try {
      await _api.acceptFriendRequest(request.id);
    } on ApiException catch (e) {
      _onApiError(e);
    }
    await _refreshSocial();
  }

  Future<void> declineRequest(FriendRequestDto request) async {
    setState(() => friendRequests = friendRequests.where((r) => r.id != request.id).toList());
    try {
      await _api.declineFriendRequest(request.id);
    } on ApiException catch (e) {
      _onApiError(e);
    }
  }

  // --------------------------------------------------------------- realtime

  /// Every frame the server sends, with the one thing that used to be missing
  /// between it and the UI: a boundary.
  ///
  /// Every REST call in this class is wrapped in a `try`; the socket was the
  /// one input that was not, and it is the one that arrives without a button
  /// press behind it, on the duel path, with no caller left to fail back to. A
  /// frame the app could not read threw out of the handler and off the end of
  /// the world — whatever it was in the middle of doing stayed half done, and
  /// the player was left on a screen that had quietly stopped agreeing with the
  /// server about what they were doing.
  ///
  /// Dropping the frame is safe in a way that letting it escape is not: a duel
  /// states its whole board on every move, so the next frame carries everything
  /// this one did, and a socket that is genuinely broken reconnects and is
  /// handed the state over again.
  void _onSocketEvent(SocketEvent event) {
    if (!mounted) return;
    try {
      _applySocketEvent(event);
    } catch (_) {
      _onBadFrame();
    }
  }

  /// What a frame the app could not make sense of is worth: a line on the
  /// screen. The alternative — the old behaviour — is a player watching a
  /// screen that has stopped matching the server with nothing telling them so.
  void _onBadFrame() {
    if (!mounted) return;
    setState(() => banner = "Serverdan noto'g'ri xabar keldi");
  }

  void _applySocketEvent(SocketEvent event) {
    switch (event.type) {
      case 'hello':
        final user = event.payload['user'];
        setState(() {
          if (user is Map<String, dynamic>) me = UserDto.fromJson(user);
          onlineCount = (event.payload['onlineCount'] as num?)?.toInt() ?? onlineCount;
        });
        // A socket that dropped while the app was in the background took the
        // player's place in the queue with it, and the rejoin on resume was
        // written to a socket that was already gone. This is the one frame
        // that proves the new socket is live, so the queue is claimed here.
        _rejoinQueue();
      case 'queue.joined':
        // The server reports when the wait actually started, which is not now
        // for anyone rejoining — using the local clock instead would reset the
        // displayed timer on every reconnect.
        setState(() => queuedAt = DateTime.tryParse(event.payload['since'] as String? ?? '')?.toLocal()
            ?? queuedAt
            ?? DateTime.now());
      case 'queue.left':
        setState(() => queuedAt = null);
      case 'match.found':
        final found = DuelView.fromMatchFound(event.payload);
        if (found == null) {
          // Half a frame is not a board that can be drawn — see
          // [DuelView.fromMatchFound] — so it is dropped rather than guessed
          // at. What happens next depends on which side of the duel this is,
          // and neither outcome is good; the point is only that neither is
          // worse than the crash this replaces.
          //
          // The server sends `match.found` to both players and then waits: a
          // duel broadcasts no state of its own until somebody submits a word,
          // and it opens with the first player on turn unconditionally. So the
          // player who moves second is rescued by the first one's move — that
          // `duel.update` arrives with no board in memory and raises one
          // through [_resumeDuel], the same path a relaunch takes. The player
          // who moves *first* has nothing to wait for: they cannot act, so no
          // update is ever generated, and their turn timer runs out. What ends
          // it for them is `duel.finished`, which lands because
          // [duelFrameApplies] lets a result through when there is no board to
          // protect — a forfeit they did not choose, on the win/lose screen
          // rather than on a screen frozen forever.
          //
          // Closing that second case needs the server to re-send or to state
          // the duel once at the start, which is not this class's to do.
          _onBadFrame();
          return;
        }
        setState(() {
          duel = found;
          duelError = '';
          finished = null;
          queuedAt = null;
          outgoingInvite = null;
          incomingInvite = null;
          duelChat = const [];
          duelReaction = null;
          duelPowerUps = const DuelPowerUps();
          screen = WBScreen.duel;
        });
        _scrollChainToBottom();
      case 'duel.update':
        final current = duel;
        // No board in memory is not "nothing to do" — it is the relaunch: the
        // app was killed mid-duel and this frame is the server handing the
        // battle back. It used to be dropped here, and the player watched the
        // lobby while their turn timer ran out. See [_resumeDuel].
        if (current == null) {
          _resumeDuel(event.payload);
          return;
        }
        if (!duelFrameApplies(current.duelId, event.payload['duelId'] as String?)) return;
        setState(() {
          duel = current.applyUpdate(event.payload);
          duelError = '';
          // The suggested words were for the board as it stood when they were
          // asked for. It has moved, so they go — even when the letter has not,
          // since a word that was on offer may be the one just played.
          duelPowerUps = duelPowerUps.withoutHints();
        });
        _scrollChainToBottom();
      case 'duel.power_up':
        // The server has spent a charge: the button greys out, and the hint —
        // the only one of the four with anything to say — hands over its words.
        final powerUp = DuelPowerUp.byId(event.payload['type'] as String?);
        if (duel == null || powerUp == null) return;
        setState(() => duelPowerUps = duelPowerUps.used(
              powerUp,
              ((event.payload['words'] as List?) ?? const []).map((word) => word as String).toList(),
            ));
      case 'duel.rejected':
        setState(() => duelError = event.payload['message'] as String? ?? "So'z qabul qilinmadi");
      case 'duel.chat':
        final text = event.payload['text'] as String?;
        if (duel == null || text == null || text.isEmpty) return;
        setState(() => duelChat = [...duelChat, DuelChatMessage(text: text, mine: false)]);
      case 'duel.reaction':
        final emoji = event.payload['emoji'] as String?;
        if (duel == null || emoji == null || emoji.isEmpty) return;
        setState(() => duelReaction = DuelReaction(emoji: emoji, id: _reactionSeq++));
      case 'duel.finished':
        final result = FinishedDuel.fromJson(event.payload);
        if (!duelFrameApplies(duel?.duelId, result.duelId)) return;
        setState(() {
          finished = result;
          duel = null;
          duelChat = const [];
          duelReaction = null;
          duelPowerUps = const DuelPowerUps();
          screen = result.won ? WBScreen.win : WBScreen.lose;
        });
        unawaited(_refreshSocial());
      case 'invite.sent':
        final sentId = event.payload['inviteId'] as String;
        switch (inviteSentActionFor(
          screen: screen,
          inviteId: sentId,
          settledInviteId: _settledInviteId,
        )) {
          case InviteSentAction.drop:
            // The race is over; the id has done its job.
            _settledInviteId = null;
          case InviteSentAction.withdraw:
            // Quietly. The player is in a duel, a search or a result they chose
            // over this challenge, and a banner across a live board costs more
            // than the news is worth — but the friend must not be left holding
            // an invite that would drop this player into a second duel.
            _socket.send('invite.decline', {'inviteId': sentId});
          case InviteSentAction.open:
            setState(() {
              final invite = PendingInvite(
                inviteId: sentId,
                user: UserDto.fromJson(event.payload['to'] as Map<String, dynamic>),
                secondsLeft: (event.payload['expiresInSeconds'] as num?)?.toInt() ?? 12,
              );
              outgoingInvite = invite;
              _inviteStartedAt = DateTime.now();
              _inviteSecondsLeft = invite.secondsLeft;
              screen = WBScreen.invite;
            });
        }
      case 'invite.incoming':
        setState(() {
          incomingInvite = PendingInvite(
            inviteId: event.payload['inviteId'] as String,
            user: UserDto.fromJson(event.payload['from'] as Map<String, dynamic>),
            secondsLeft: (event.payload['expiresInSeconds'] as num?)?.toInt() ?? 12,
          );
          _inviteStartedAt = DateTime.now();
          _inviteSecondsLeft = incomingInvite!.secondsLeft;
          // Never interrupt a live duel — 1v1 or team — with a challenge sheet.
          if (screen != WBScreen.duel && screen != WBScreen.teamDuel) screen = WBScreen.incoming;
        });
      case 'invite.declined':
        _settleInvite(event.payload['inviteId'] as String?, refused: true);
      case 'invite.expired':
        _settleInvite(event.payload['inviteId'] as String?, refused: false);
      case 'team.formed':
        setState(() {
          teamPartner = UserDto.fromJson(event.payload['partner'] as Map<String, dynamic>);
          // Either slot might have held the invite this just answered,
          // depending on which side of it this player was on.
          outgoingTeamInvite = null;
          incomingTeamInvite = null;
          if (screen == WBScreen.teamInvite || screen == WBScreen.teamIncoming) screen = WBScreen.lobby;
        });
      case 'team.disbanded':
        final reason = event.payload['reason'] as String?;
        setState(() {
          final partner = teamPartner;
          teamPartner = null;
          teamQueuedAt = null;
          if (screen == WBScreen.teamQueue) screen = WBScreen.lobby;
          banner = reason == 'disconnected'
              ? "${partner?.label ?? 'Sherigingiz'} aloqadan uzildi — jamoa tarqadi"
              : "${partner?.label ?? 'Sherigingiz'} jamoani bekor qildi";
        });
      case 'team_invite.sent':
        final sentId = event.payload['inviteId'] as String;
        switch (inviteSentActionFor(
          screen: screen,
          inviteId: sentId,
          settledInviteId: _settledTeamInviteId,
        )) {
          case InviteSentAction.drop:
            _settledTeamInviteId = null;
          case InviteSentAction.withdraw:
            _socket.send('team_invite.decline', {'inviteId': sentId});
          case InviteSentAction.open:
            setState(() {
              final invite = PendingTeamInvite(
                inviteId: sentId,
                user: UserDto.fromJson(event.payload['to'] as Map<String, dynamic>),
                secondsLeft: (event.payload['expiresInSeconds'] as num?)?.toInt() ?? 12,
              );
              outgoingTeamInvite = invite;
              _teamInviteStartedAt = DateTime.now();
              _teamInviteSecondsLeft = invite.secondsLeft;
              screen = WBScreen.teamInvite;
            });
        }
      case 'team_invite.incoming':
        setState(() {
          incomingTeamInvite = PendingTeamInvite(
            inviteId: event.payload['inviteId'] as String,
            user: UserDto.fromJson(event.payload['from'] as Map<String, dynamic>),
            secondsLeft: (event.payload['expiresInSeconds'] as num?)?.toInt() ?? 12,
          );
          _teamInviteStartedAt = DateTime.now();
          _teamInviteSecondsLeft = incomingTeamInvite!.secondsLeft;
          if (screen != WBScreen.duel && screen != WBScreen.teamDuel) screen = WBScreen.teamIncoming;
        });
      case 'team_invite.declined':
        _settleTeamInvite(event.payload['inviteId'] as String?, refused: true);
      case 'team_invite.expired':
        _settleTeamInvite(event.payload['inviteId'] as String?, refused: false);
      case 'team.queue.joined':
        setState(() => teamQueuedAt = DateTime.tryParse(event.payload['since'] as String? ?? '')?.toLocal()
            ?? teamQueuedAt
            ?? DateTime.now());
      case 'team.queue.left':
        setState(() => teamQueuedAt = null);
      case 'team_duel.match_found':
        final found = TeamDuelView.fromMatchFound(event.payload);
        if (found == null) {
          // See the long note on `match.found` above — the same half-a-frame
          // problem, on the team channel.
          _onBadFrame();
          return;
        }
        setState(() {
          teamDuel = found;
          teamDuelError = '';
          teamFinished = null;
          teamQueuedAt = null;
          outgoingTeamInvite = null;
          incomingTeamInvite = null;
          teamChat = const [];
          teamReaction = null;
          screen = WBScreen.teamDuel;
        });
        _scrollTeamChainToBottom();
      case 'team_duel.update':
        final current = teamDuel;
        if (current == null) {
          // The relaunch case — see [_resumeDuel] — on the team channel.
          _resumeTeamDuel(event.payload);
          return;
        }
        if (!duelFrameApplies(current.duelId, event.payload['duelId'] as String?)) return;
        setState(() {
          teamDuel = current.applyUpdate(event.payload);
          teamDuelError = '';
        });
        _scrollTeamChainToBottom();
      case 'team_duel.rejected':
        setState(() => teamDuelError = event.payload['message'] as String? ?? "So'z qabul qilinmadi");
      case 'team_duel.chat':
        final board = teamDuel;
        final text = event.payload['text'] as String?;
        if (board == null || text == null || text.isEmpty) return;
        setState(() => teamChat = [
              ...teamChat,
              TeamChatMessage(
                text: text,
                sender: board.labelOf((event.payload['playerId'] as num?)?.toInt() ?? 0),
              ),
            ]);
      case 'team_duel.reaction':
        final board = teamDuel;
        final emoji = event.payload['emoji'] as String?;
        if (board == null || emoji == null || emoji.isEmpty) return;
        setState(() => teamReaction = TeamReaction(
              emoji: emoji,
              sender: board.labelOf((event.payload['playerId'] as num?)?.toInt() ?? 0),
              id: _reactionSeq++,
            ));
      case 'team_duel.finished':
        final result = TeamFinishedDuel.fromJson(event.payload);
        if (!duelFrameApplies(teamDuel?.duelId, result.duelId)) return;
        setState(() {
          teamFinished = result;
          teamDuel = null;
          teamChat = const [];
          teamReaction = null;
          screen = result.won ? WBScreen.teamWin : WBScreen.teamLose;
        });
        unawaited(_refreshSocial());
      case 'team_duel.aborted':
        setState(() {
          teamDuel = null;
          teamFinished = null;
          teamChat = const [];
          teamReaction = null;
          banner = event.payload['message'] as String? ?? 'Jamoa jangi bekor qilindi';
          if (screen == WBScreen.teamDuel) screen = WBScreen.lobby;
        });
      case 'tournament.invite':
        setState(() => tournamentInvite = TournamentInvite.fromJson(event.payload));
      case 'tournament.match_ready':
        setState(() => tournamentMatchReady = TournamentMatchPrompt.fromJson(event.payload));
      case 'tournament.bracket_update':
        final id = (event.payload['tournamentId'] as num?)?.toInt();
        if (id != null && id == _viewingTournamentId) unawaited(_loadTournamentDetail(id));
      case 'tournament.cancelled':
        final id = (event.payload['tournamentId'] as num?)?.toInt();
        final name = event.payload['name'] as String? ?? 'Turnir';
        setState(() {
          banner = "'$name' turniri bekor qilindi";
          if (tournamentInvite?.tournamentId == id) tournamentInvite = null;
          if (tournamentMatchReady?.tournamentId == id) tournamentMatchReady = null;
          if (activeTournament?.id == id) activeTournament = null;
          if (tournamentDetail?.id == id) tournamentDetail = null;
        });
      case 'duel.aborted':
        // The server is going away mid-duel. Nobody won; say so plainly rather
        // than leaving the duel screen frozen on a turn that will never end.
        setState(() {
          duel = null;
          finished = null;
          duelChat = const [];
          duelReaction = null;
          duelPowerUps = const DuelPowerUps();
          banner = event.payload['message'] as String? ?? 'Jang bekor qilindi';
          if (screen == WBScreen.duel) screen = WBScreen.lobby;
        });
      case 'duel.spectate_state':
        // Sent once right after a successful `duel.spectate`, then again on
        // every move by either player — the full board each time, the same
        // way `duel.update` restates a played duel rather than diffing it.
        setState(() {
          spectating = SpectateState.fromJson(event.payload);
          screen = WBScreen.spectateDuel;
        });
        _scrollSpectateChainToBottom();
      case 'duel.spectate_ended':
        final reason = event.payload['reason'] as String?;
        setState(() {
          spectating = null;
          if (screen == WBScreen.spectateDuel) screen = WBScreen.friends;
          if (reason == 'aborted') banner = 'Kuzatilayotgan jang bekor qilindi';
        });
      case 'team_duel.spectate_state':
        // `duel.spectate_state` for a friend who turned out to be in a 2v2
        // duel: the same frame on every move, with four participants on it
        // instead of two.
        setState(() {
          teamSpectating = TeamSpectateState.fromJson(event.payload);
          screen = WBScreen.teamSpectateDuel;
        });
        _scrollTeamSpectateChainToBottom();
      case 'team_duel.spectate_ended':
        final reason = event.payload['reason'] as String?;
        setState(() {
          teamSpectating = null;
          if (screen == WBScreen.teamSpectateDuel) screen = WBScreen.friends;
          if (reason == 'aborted') banner = 'Kuzatilayotgan jang bekor qilindi';
        });
      case 'error':
        setState(() => banner = event.payload['message'] as String? ?? 'Xatolik');
    }
  }

  /// Applies an `invite.declined` or `invite.expired` to whichever of the two
  /// invites it names, and remembers the ones it cannot place.
  ///
  /// [refused] separates a person pressing a button from a clock running out.
  /// Only the first is worth saying, and what it says depends on which side of
  /// the invite the player is on: their challenge was turned down, or the one
  /// they were deciding about has been taken back out from under them.
  ///
  /// A frame that names neither invite is the race. It cannot be about a
  /// challenge received — those and every reply to them travel on this player's
  /// own socket, in order, so an incoming invite is always known before it can
  /// be taken back. It can only be one we sent, whose `invite.sent` is still in
  /// flight on the other side of the server; a scripted opponent declining
  /// instantly is fast enough to produce exactly that. Keeping the id is what
  /// stops the confirmation, when it lands, from opening a wait on a challenge
  /// that is already over.
  void _settleInvite(String? inviteId, {required bool refused}) {
    final settlesOutgoing = inviteFrameApplies(outgoingInvite?.inviteId, inviteId);
    final settlesIncoming = inviteFrameApplies(incomingInvite?.inviteId, inviteId);

    setState(() {
      if (settlesOutgoing) {
        outgoingInvite = null;
        if (screen == WBScreen.invite) screen = WBScreen.friends;
      }
      if (settlesIncoming) {
        incomingInvite = null;
        if (screen == WBScreen.incoming) screen = WBScreen.lobby;
      }
      if (!settlesOutgoing && !settlesIncoming) _settledInviteId = inviteId;
      if (refused) {
        banner = settlesIncoming && !settlesOutgoing ? 'Chaqiruv bekor qilindi' : 'Chaqiruv rad etildi';
      }
      // Nothing left to count. Leaving the start time behind would hand it to
      // the next invite's countdown, which would then open part-spent.
      if (outgoingInvite == null && incomingInvite == null) _inviteStartedAt = null;
    });
  }

  /// Mirrors [_settleInvite], for the team-invite channel.
  void _settleTeamInvite(String? inviteId, {required bool refused}) {
    final settlesOutgoing = inviteFrameApplies(outgoingTeamInvite?.inviteId, inviteId);
    final settlesIncoming = inviteFrameApplies(incomingTeamInvite?.inviteId, inviteId);

    setState(() {
      if (settlesOutgoing) {
        outgoingTeamInvite = null;
        if (screen == WBScreen.teamInvite) screen = WBScreen.friends;
      }
      if (settlesIncoming) {
        incomingTeamInvite = null;
        if (screen == WBScreen.teamIncoming) screen = WBScreen.lobby;
      }
      if (!settlesOutgoing && !settlesIncoming) _settledTeamInviteId = inviteId;
      if (refused) {
        banner = settlesIncoming && !settlesOutgoing ? 'Jamoa taklifi bekor qilindi' : 'Jamoa taklifi rad etildi';
      }
      if (outgoingTeamInvite == null && incomingTeamInvite == null) _teamInviteStartedAt = null;
    });
  }

  /// Puts a player back on the board after the app process itself went away.
  ///
  /// Everything else survives a relaunch through the stored token: the session
  /// is restored, the profile refetched, the socket dialled again. A live duel
  /// did not, because the only thing that ever raised the duel screen was
  /// `match.found`, and a process that started after the duel did will never
  /// see one. The server already hands the state back the moment the new socket
  /// connects; this is where that frame becomes a battle again, setting what
  /// `match.found` sets from the fields the state frame now carries.
  ///
  /// It cannot bring a dead duel back: the server sends no state for a duel
  /// that has ended, and a player returning to one is handed its result
  /// instead, which lands them on the win or lose screen through
  /// `duel.finished`. That covers the relaunch that took longer than the
  /// disconnect grace, where the battle was forfeited while they were away.
  void _resumeDuel(Map<String, dynamic> payload) {
    final resumed = DuelView.fromDuelUpdate(payload);
    if (resumed == null) {
      // Said out loud, for the same reason `match.found` says it — and with
      // less to fall back on. This is already the recovery path: the player is
      // sitting on the lobby with a duel running somewhere they cannot see, and
      // returning in silence is exactly the thing this method exists to stop.
      // A banner is all that is honest here, but it beats nothing at all.
      _onBadFrame();
      return;
    }
    setState(() {
      duel = resumed;
      duelError = '';
      // The same clean slate `match.found` makes: whatever the player was doing
      // before, the server says they are in a duel, so nothing else is.
      finished = null;
      queuedAt = null;
      outgoingInvite = null;
      incomingInvite = null;
      screen = WBScreen.duel;
    });
    _scrollChainToBottom();
  }

  /// Mirrors [_resumeDuel], for the team channel.
  void _resumeTeamDuel(Map<String, dynamic> payload) {
    final resumed = TeamDuelView.fromDuelUpdate(payload);
    if (resumed == null) {
      _onBadFrame();
      return;
    }
    setState(() {
      teamDuel = resumed;
      teamDuelError = '';
      teamFinished = null;
      teamQueuedAt = null;
      outgoingTeamInvite = null;
      incomingTeamInvite = null;
      screen = WBScreen.teamDuel;
    });
    _scrollTeamChainToBottom();
  }

  void _onTick() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTick).inMilliseconds;
    _lastTick = now;
    if (!mounted) return;

    final current = duel;
    final currentTeam = teamDuel;
    final watched = spectating;
    final watchedTeam = teamSpectating;
    if (screen == WBScreen.duel && current != null && current.timeLeftMs > 0) {
      setState(() => duel = current.tick(elapsed));
    } else if (screen == WBScreen.teamDuel && currentTeam != null && currentTeam.timeLeftMs > 0) {
      setState(() => teamDuel = currentTeam.tick(elapsed));
    } else if (screen == WBScreen.spectateDuel && watched != null && watched.timeLeftMs > 0) {
      setState(() => spectating = watched.tick(elapsed));
    } else if (screen == WBScreen.teamSpectateDuel && watchedTeam != null && watchedTeam.timeLeftMs > 0) {
      setState(() => teamSpectating = watchedTeam.tick(elapsed));
    } else if (screen == WBScreen.match && queuedAt != null) {
      setState(() {}); // redraw the elapsed clock
    } else if (screen == WBScreen.teamQueue && teamQueuedAt != null) {
      setState(() {}); // redraw the elapsed clock
    } else if (screen == WBScreen.invite || screen == WBScreen.incoming) {
      _tickInvite();
    } else if (screen == WBScreen.teamInvite || screen == WBScreen.teamIncoming) {
      _tickTeamInvite();
    }
  }

  /// Moves the clock under whichever invite screen is up, and — the part that
  /// was missing — ends the wait when it runs out.
  ///
  /// The countdown used to be display only, so an invite screen the server
  /// never closed stayed up forever showing 0:00. See [inviteSecondsLeftAt] for
  /// when that happens and why nothing else was going to close it.
  void _tickInvite() {
    final invite = screen == WBScreen.invite ? outgoingInvite : incomingInvite;
    final left = invite == null
        ? null
        : inviteSecondsLeftAt(_inviteStartedAt, invite.secondsLeft, DateTime.now());
    if (left == null) {
      _giveUpOnInvite();
      return;
    }
    setState(() => _inviteSecondsLeft = left);
  }

  /// Ends the wait the current screen is showing and leaves that screen, the
  /// same way the server's own `invite.expired` would have.
  ///
  /// The invite is not withdrawn on the way out. The countdown starts from the
  /// server's `expiresInSeconds` at the moment its frame reached the phone, so
  /// the app's zero is never earlier than the server's, and the sweep that
  /// expires it there runs every second regardless.
  void _giveUpOnInvite() {
    setState(() {
      _inviteSecondsLeft = 0;
      if (screen == WBScreen.invite) {
        outgoingInvite = null;
        screen = WBScreen.friends;
      } else if (screen == WBScreen.incoming) {
        incomingInvite = null;
        screen = WBScreen.lobby;
      }
      if (outgoingInvite == null && incomingInvite == null) _inviteStartedAt = null;
    });
  }

  /// Mirrors [_tickInvite], for the team-invite channel.
  void _tickTeamInvite() {
    final invite = screen == WBScreen.teamInvite ? outgoingTeamInvite : incomingTeamInvite;
    final left = invite == null
        ? null
        : inviteSecondsLeftAt(_teamInviteStartedAt, invite.secondsLeft, DateTime.now());
    if (left == null) {
      _giveUpOnTeamInvite();
      return;
    }
    setState(() => _teamInviteSecondsLeft = left);
  }

  /// Mirrors [_giveUpOnInvite], for the team-invite channel.
  void _giveUpOnTeamInvite() {
    setState(() {
      _teamInviteSecondsLeft = 0;
      if (screen == WBScreen.teamInvite) {
        outgoingTeamInvite = null;
        screen = WBScreen.friends;
      } else if (screen == WBScreen.teamIncoming) {
        incomingTeamInvite = null;
        screen = WBScreen.lobby;
      }
      if (outgoingTeamInvite == null && incomingTeamInvite == null) _teamInviteStartedAt = null;
    });
  }

  /// Brings a word that has just joined the chain into view.
  ///
  /// Runs after the frame that added the row, so the extent it aims at counts
  /// the new bubble. This half only answers to words arriving; the chain can
  /// also lose its place when the keyboard resizes the viewport under it, and
  /// `DuelScreen.didChangeDependencies` is the half that handles that.
  void _scrollChainToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!chainScrollController.hasClients) return;
      chainScrollController.animateTo(
        chainScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// The same courtesy [_scrollChainToBottom] pays a played duel, paid to a
  /// watched one: a spectator whose chain keeps growing off the bottom of the
  /// screen is watching the wrong half of it.
  void _scrollSpectateChainToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!spectateScrollController.hasClients) return;
      spectateScrollController.animateTo(
        spectateScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// [_scrollSpectateChainToBottom] again, for a watched 2v2 duel.
  void _scrollTeamSpectateChainToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!teamSpectateScrollController.hasClients) return;
      teamSpectateScrollController.animateTo(
        teamSpectateScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// The same courtesy [_scrollChainToBottom] pays a played 1v1 duel, paid to
  /// a team one.
  void _scrollTeamChainToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!teamChainScrollController.hasClients) return;
      teamChainScrollController.animateTo(
        teamChainScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Leaving a pending invite behind used to be possible from the invite
  /// screen's "skip to matchmaking": the friend could then accept a challenge
  /// from someone already in another duel, which put one player in two duels at
  /// once and broke both. The invite is withdrawn first now.
  ///
  /// One it cannot withdraw is an invite whose `invite.sent` has not arrived
  /// yet: there is no id here to name it by. That one is taken back when its
  /// confirmation lands on the search screen — see [inviteSentActionFor].
  void startMatchmaking() {
    final pending = outgoingInvite;
    if (pending != null) _socket.send('invite.decline', {'inviteId': pending.inviteId});
    setState(() {
      outgoingInvite = null;
      queuedAt = DateTime.now();
      finished = null;
      screen = WBScreen.match;
    });
    _socket.send('queue.join');
  }

  void cancelMatchmaking() {
    // `go` already sends `queue.leave` when leaving the match screen; sending
    // it here as well made every cancel arrive twice.
    setState(() => queuedAt = null);
    go(WBScreen.lobby);
  }

  /// The lobby's "Bot bilan jang". The slider opens on this player's own
  /// rating, rounded to a step it can actually stop on — a value between two
  /// divisions would be snapped to one on the first drag and look like the
  /// screen had changed its mind.
  void openBotBattle() {
    final mine = (me?.rating ?? BotBattleScreen.minRating).toDouble();
    final snapped = (mine / BotBattleScreen.step).round() * BotBattleScreen.step;
    setState(() => botRating = snapped.clamp(BotBattleScreen.minRating, BotBattleScreen.maxRating).round());
    go(WBScreen.botSetup);
  }

  /// Nothing changes screen here: the duel arrives as `match.found`, exactly as
  /// it does for a matched opponent or an accepted challenge, and that frame is
  /// what raises the board. A refusal comes back as an error frame instead and
  /// leaves the player on the picker, where they can simply tap again.
  ///
  /// A frame that never left the phone is the one case the server cannot answer
  /// for, and it has to be said out loud: unlike `queue.join`, which the `hello`
  /// handler repeats on every reconnect, nothing sends this one a second time,
  /// so an unreported failure is a button that does nothing at all.
  void startBotBattle() {
    // `?botTheme` drops the key entirely when no theme is picked, which is what
    // the server reads as the ordinary full-dictionary duel.
    if (_socket.send('queue.bot', {'rating': botRating, 'theme': ?botTheme})) return;
    setState(() => banner = "Aloqa yo'q — jang boshlanmadi");
  }

  void submitWord(String word) {
    if (word.trim().isEmpty) return;
    _socket.send('duel.submit', {'word': word.trim()});
  }

  /// Sends a chat line to the opponent. The server never echoes it back, so
  /// it is added to the local log here — the sender already knows what they
  /// typed, but the log would otherwise show only half the conversation.
  void sendDuelChat(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _socket.send('duel.chat', {'text': trimmed});
    setState(() => duelChat = [...duelChat, DuelChatMessage(text: trimmed, mine: true)]);
  }

  /// Sends immediately — no confirmation, no local echo. The tap itself is
  /// the only feedback the sender needs.
  void sendDuelReaction(String emoji) => _socket.send('duel.reaction', {'emoji': emoji});

  /// Asks for one of the bot practice's four power-ups. Nothing is marked spent
  /// here: the server answers with `duel.power_up` when it has actually given
  /// the charge, and with an error frame when it will not — asking on the bot's
  /// turn, or twice for the same one — which must not cost the charge.
  void useDuelPowerUp(DuelPowerUp powerUp) => _socket.send('duel.power_up', {'type': powerUp.id});

  void challenge(FriendDto friend) => _challengeUserId(friend.user.id);

  void _challengeUserId(int userId) => _socket.send('invite.send', {'userId': userId});

  /// The friends screen's "Kuzatish", for a friend currently `inBattle`. The
  /// screen only changes once `duel.spectate_state` actually arrives — see
  /// that case in [_applySocketEvent] — so a rejection (`self_spectate`,
  /// `already_in_duel`, `not_friends`, `not_in_duel`) just surfaces as the
  /// ordinary error banner and leaves the player exactly where they were, the
  /// same way a refused `invite.send` does.
  void spectate(FriendDto friend) => _socket.send('duel.spectate', {'userId': friend.user.id});

  void stopSpectating() => _socket.send('duel.unspectate');

  /// The spectate screen's own exit. The backend also drops a spectator on
  /// socket disconnect as a backstop, but one who is still connected and
  /// simply walks away has to say so, or its registry keeps counting them as
  /// watching a duel nobody is looking at any more.
  void leaveSpectating() {
    stopSpectating();
    setState(() => spectating = null);
    go(WBScreen.friends);
  }

  /// [leaveSpectating] for a watched 2v2 duel. The frame on the way out is the
  /// same one: `duel.unspectate` stops either kind of watch, since the app was
  /// never told which of the two it asked for.
  void leaveTeamSpectating() {
    stopSpectating();
    setState(() => teamSpectating = null);
    go(WBScreen.friends);
  }

  /// A rematch challenges the exact person just played, when that is
  /// possible. `InviteService.send` only ever lets a challenge through
  /// between friends, so this only ever manages a real rematch when the
  /// opponent already is one — an unrated bot or a stranger from
  /// matchmaking falls back to today's "find someone new" instead of
  /// tapping a button that would just come back `not_friends`.
  void rematch(FinishedDuel result) {
    final opponentId = result.opponentId;
    final opponent = result.opponentIsBot || opponentId == null ? null : _friendById(opponentId);
    if (opponent != null) {
      _challengeUserId(opponent.user.id);
    } else {
      startMatchmaking();
    }
  }

  FriendDto? _friendById(int userId) {
    for (final friend in friends) {
      if (friend.user.id == userId) return friend;
    }
    return null;
  }

  void acceptIncoming() {
    final invite = incomingInvite;
    if (invite == null) return;
    _socket.send('invite.accept', {'inviteId': invite.inviteId});
  }

  void declineIncoming() {
    final invite = incomingInvite;
    if (invite != null) _socket.send('invite.decline', {'inviteId': invite.inviteId});
    setState(() => incomingInvite = null);
    go(WBScreen.lobby);
  }

  void cancelOutgoingInvite() {
    final invite = outgoingInvite;
    if (invite != null) _socket.send('invite.decline', {'inviteId': invite.inviteId});
    setState(() => outgoingInvite = null);
    go(WBScreen.friends);
  }

  // --------------------------------------------------------------- team duels

  /// The friends screen's "jamoa taklif qilish" — mirrors [challenge] exactly.
  void inviteToTeam(FriendDto friend) => _socket.send('team_invite.send', {'userId': friend.user.id});

  void acceptIncomingTeamInvite() {
    final invite = incomingTeamInvite;
    if (invite == null) return;
    _socket.send('team_invite.accept', {'inviteId': invite.inviteId});
  }

  void declineIncomingTeamInvite() {
    final invite = incomingTeamInvite;
    if (invite != null) _socket.send('team_invite.decline', {'inviteId': invite.inviteId});
    setState(() => incomingTeamInvite = null);
    go(WBScreen.lobby);
  }

  void cancelOutgoingTeamInvite() {
    final invite = outgoingTeamInvite;
    if (invite != null) _socket.send('team_invite.decline', {'inviteId': invite.inviteId});
    setState(() => outgoingTeamInvite = null);
    go(WBScreen.friends);
  }

  /// Disbands the currently-formed team — the lobby banner's "×".
  void cancelTeam() {
    _socket.send('team.cancel');
    setState(() => teamPartner = null);
  }

  void startTeamQueue() {
    setState(() {
      teamQueuedAt = DateTime.now();
      teamFinished = null;
      screen = WBScreen.teamQueue;
    });
    _socket.send('team.queue.join');
  }

  void cancelTeamQueue() {
    // `go` already sends `team.queue.leave` when leaving the team-queue
    // screen — see [cancelMatchmaking] for the same reasoning.
    setState(() => teamQueuedAt = null);
    go(WBScreen.lobby);
  }

  void submitTeamWord(String word) {
    if (word.trim().isEmpty) return;
    _socket.send('team_duel.submit', {'word': word.trim()});
  }

  /// Mirrors [sendDuelChat] — the server fans the line out to the other three
  /// and never echoes it back, so the sender's own copy is added here.
  void sendTeamChat(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _socket.send('team_duel.chat', {'text': trimmed});
    setState(() => teamChat = [...teamChat, TeamChatMessage(text: trimmed, sender: null)]);
  }

  /// Mirrors [sendDuelReaction]: sent immediately, with no local echo.
  void sendTeamReaction(String emoji) => _socket.send('team_duel.reaction', {'emoji': emoji});

  /// The team result screens' "Yana o'ynash". Nothing disbands a team when its
  /// duel ends, so the same two players simply queue again — there is no
  /// team-to-team challenge to send, so a rematch is a fresh search rather than
  /// a call back to the two opponents just played. A team that did break up in
  /// between — a partner who disconnected — has nothing to queue, and goes back
  /// to the lobby instead of asking the server for a refusal.
  void rematchAsTeam() {
    if (teamPartner == null) {
      go(WBScreen.lobby);
      return;
    }
    startTeamQueue();
  }

  // ------------------------------------------------------------- navigation

  static WBTab? _tabOf(WBScreen screen) => switch (screen) {
        WBScreen.lobby => WBTab.home,
        WBScreen.friends => WBTab.friends,
        WBScreen.board => WBTab.board,
        WBScreen.profile => WBTab.profile,
        _ => null,
      };

  void go(WBScreen next) {
    final from = _tabOf(screen);
    final to = _tabOf(next);
    previousNavTab = from != null && to != null && from != to ? from : null;

    // Walking out of a duel is a forfeit — the server decides the rest.
    final exit = exitFrameFor(screen, next);
    final delivered = exit == null || _socket.send(exit);

    setState(() {
      screen = next;
      // A forfeit that never left the phone is not nothing to report. The
      // player is off the duel screen and the server still has them on it, and
      // the app has no honest way to close that gap itself: `duel.forfeit`
      // names no duel, so replaying it when the socket returns would forfeit
      // whatever duel the server has *then* — including a fresh one the player
      // has since been paired into. Queueing it would trade a duel the player
      // meant to leave for one they meant to play.
      //
      // What closes it instead is the server's own disconnect grace: a socket
      // this far down is about to be counted as gone, and the duel ends there.
      // So the app says what happened and lets that run.
      banner = delivered ? null : "Aloqa yo'q — server bundan xabarsiz";
      duelError = '';
      teamDuelError = '';
      // The chat and reactions belong to the duel just left, not whatever
      // comes next — same as the rest of this duel's state, none of which
      // outlives the screen it was shown on. `exit` names this move as a
      // forfeit only when it is leaving the duel screen, which is exactly
      // when there is a chat log to drop.
      if (exit == 'duel.forfeit') {
        duelChat = const [];
        duelReaction = null;
        duelPowerUps = const DuelPowerUps();
      }
      if (exit == 'team_duel.forfeit') {
        teamChat = const [];
        teamReaction = null;
      }
    });

    switch (next) {
      case WBScreen.board:
        unawaited(_loadBoard());
      case WBScreen.profile:
        unawaited(_loadProfile());
      case WBScreen.history:
        unawaited(_loadHistory());
      case WBScreen.practice:
        unawaited(_loadPractice());
      case WBScreen.botSetup:
        unawaited(_loadBotThemes());
      case WBScreen.friends:
      case WBScreen.lobby:
        unawaited(_refreshSocial());
        unawaited(_refreshActiveTournament());
      default:
        break;
    }
  }

  /// The only way out of a live duel, shared by the Android back gesture and
  /// the duel screens' own exit button — iOS has neither a hardware back
  /// button nor a page route to swipe, so without that button there is no way
  /// off the board at all. Leaving forfeits (see [go]), which is far too much
  /// to hand a stray gesture, so it is asked about first.
  Future<void> confirmLeaveDuel() async {
    final from = screen;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WBColors.bgPanel,
        title: Text("Taslim bo'lasizmi?", style: WBText.grotesk(size: 16, weight: FontWeight.w700)),
        content: Text(
          "O'yin mag'lubiyat bilan tugaydi.",
          style: WBText.grotesk(size: 13, height: 1.45, color: WBColors.textA(.72)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Bekor qilish',
              style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: WBColors.textA(.75)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(backgroundColor: WBColors.redA(.14)),
            child: Text(
              "Ha, taslim bo'lish",
              style: WBText.grotesk(size: 13, weight: FontWeight.w700, color: WBColors.redSoft),
            ),
          ),
        ],
      ),
    );
    // The duel can end while the question is still on screen — a turn timed
    // out, or the opponent walked out first — and the result screen that
    // replaced it is not something to forfeit out of.
    if (!mounted || answer != true || screen != from) return;
    go(WBScreen.lobby);
  }

  void handleBack() {
    switch (screen) {
      case WBScreen.onb1:
      case WBScreen.lobby:
      case WBScreen.loading:
      case WBScreen.offline:
        SystemNavigator.pop();
      case WBScreen.onb2:
        go(WBScreen.onb1);
      // Reached from the profile, so back belongs there and not on the lobby.
      case WBScreen.history:
        go(WBScreen.profile);
      case WBScreen.invite:
        cancelOutgoingInvite();
      case WBScreen.incoming:
        declineIncoming();
      case WBScreen.teamInvite:
        cancelOutgoingTeamInvite();
      case WBScreen.teamIncoming:
        declineIncomingTeamInvite();
      case WBScreen.spectateDuel:
        leaveSpectating();
      case WBScreen.teamSpectateDuel:
        leaveTeamSpectating();
      case WBScreen.organizeTournamentSetup:
        go(WBScreen.friends);
      case WBScreen.organizeTournamentManage:
        leaveOrganizingTournament();
      // Named rather than left to the fallback below: for these two the
      // fallback's `go` is a forfeit, and a back-gesture is not consent to one.
      case WBScreen.duel:
      case WBScreen.teamDuel:
        unawaited(confirmLeaveDuel());
      default:
        go(WBScreen.lobby);
    }
  }

  // ----------------------------------------------------------------- layout

  /// The design is a fixed-width 412dp canvas, scaled by width only: fitting it
  /// by height letterboxes the UI on a real phone.
  static const _designWidth = 412.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) handleBack();
      },
      child: ColoredBox(
        color: WBColors.bg,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = constraints.maxWidth / _designWidth;
              final available = constraints.maxHeight - media.viewInsets.bottom;
              final designHeight = (available < 0 ? 0.0 : available) / scale;

              return FittedBox(
                fit: BoxFit.fitWidth,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _designWidth,
                  height: designHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(child: _screen()),
                      if (banner != null)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: _Banner(message: banner!, onDismiss: () => setState(() => banner = null)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _screen() {
    final user = me;
    return switch (screen) {
      WBScreen.loading => LoadingScreen(),
      // The retry needs no `busy` gate of its own: [_bootstrap] leaves this
      // screen for the spinner in the same `setState` that raises the flag, so
      // there is no repaint in which a disabled button could be drawn — and a
      // second tap inside that one frame still holds the callback this build
      // handed it. The guard inside [_bootstrap] is the one that can see it.
      WBScreen.offline => LoadingScreen(
          message: banner ?? "Serverga ulanib bo'lmadi",
          onRetry: _bootstrap,
        ),
      WBScreen.onb1 => Onboarding1Screen(
          onGoogle: loginWithGoogle,
          onDevLogin: ApiConfig.googleConfigured ? null : loginDev,
          onRegister: registerWithPassword,
          onLogin: loginWithPassword,
          busy: busy,
        ),
      WBScreen.onb2 => Onboarding2Screen(
          nickname: nickname,
          nickState: nickState,
          nickError: nickError,
          suggestions: nickSuggestions,
          onNickChanged: setNick,
          onPickSuggestion: setNick,
          onSubmit: nickState == NickState.free && !busy ? claimNickname : null,
        ),
      WBScreen.lobby => LobbyScreen(
          user: user,
          onlineCount: onlineCount,
          friendRequestCount: friendRequests.length,
          friendsOnlineCount: friends.where((f) => f.online).length,
          incoming: incomingInvite,
          tournamentInvite: tournamentInvite,
          tournamentMatchReady: tournamentMatchReady,
          activeTournament: activeTournament,
          onStartMatch: startMatchmaking,
          onBotBattle: openBotBattle,
          onFriends: () => go(WBScreen.friends),
          onPractice: () => go(WBScreen.practice),
          onIncoming: () => go(WBScreen.incoming),
          onBoard: () => go(WBScreen.board),
          onProfile: () => go(WBScreen.profile),
          onOpenTournamentInvite: openTournamentInvite,
          onStartTournamentMatch: startReadyTournamentMatch,
          onOpenTournamentBracket: () => openTournamentBracket(activeTournament!.id),
          onOpenTournamentsBrowse: openTournamentsBrowse,
          teamPartner: teamPartner,
          onStartTeamQueue: startTeamQueue,
          onCancelTeam: cancelTeam,
          incomingTeam: incomingTeamInvite,
          onIncomingTeam: () => go(WBScreen.teamIncoming),
          previousTab: previousNavTab,
        ),
      WBScreen.match => MatchmakingScreen(
          user: user,
          matchClock: _clock(queuedAt),
          onCancel: cancelMatchmaking,
        ),
      WBScreen.botSetup => BotBattleScreen(
          rating: botRating,
          myRating: user?.rating,
          themes: botThemes,
          theme: botTheme,
          onRatingChanged: (value) => setState(() => botRating = value),
          onThemeChanged: (value) => setState(() => botTheme = value),
          onStart: startBotBattle,
          onBack: () => go(WBScreen.lobby),
        ),
      WBScreen.duel => DuelScreen(
          duel: duel,
          me: user,
          error: duelError,
          scrollController: chainScrollController,
          onSubmit: submitWord,
          chatLog: duelChat,
          onSendChat: sendDuelChat,
          onSendReaction: sendDuelReaction,
          reaction: duelReaction,
          powerUps: duelPowerUps,
          onPowerUp: useDuelPowerUp,
          onLeave: confirmLeaveDuel,
        ),
      WBScreen.win => WinScreen(
          result: finished,
          onRematch: () {
            final result = finished;
            result == null ? startMatchmaking() : rematch(result);
          },
          onHome: () => go(WBScreen.lobby),
        ),
      WBScreen.lose => LoseScreen(
          result: finished,
          onRematch: () {
            final result = finished;
            result == null ? startMatchmaking() : rematch(result);
          },
          onPractice: () => go(WBScreen.practice),
        ),
      WBScreen.teamQueue => TeamQueueScreen(
          user: user,
          partner: teamPartner,
          matchClock: _clock(teamQueuedAt),
          onCancel: cancelTeamQueue,
        ),
      WBScreen.teamDuel => TeamDuelScreen(
          duel: teamDuel,
          me: user,
          error: teamDuelError,
          scrollController: teamChainScrollController,
          onSubmit: submitTeamWord,
          chatLog: teamChat,
          onSendChat: sendTeamChat,
          onSendReaction: sendTeamReaction,
          reaction: teamReaction,
          onLeave: confirmLeaveDuel,
        ),
      WBScreen.teamWin => TeamWinScreen(
          me: user,
          result: teamFinished,
          onRematch: rematchAsTeam,
          onHome: () => go(WBScreen.lobby),
        ),
      WBScreen.teamLose => TeamLoseScreen(
          me: user,
          result: teamFinished,
          onRematch: rematchAsTeam,
          onHome: () => go(WBScreen.lobby),
          onPractice: () => go(WBScreen.practice),
        ),
      WBScreen.spectateDuel => SpectateDuelScreen(
          state: spectating,
          scrollController: spectateScrollController,
          onBack: leaveSpectating,
        ),
      WBScreen.teamSpectateDuel => TeamSpectateDuelScreen(
          state: teamSpectating,
          scrollController: teamSpectateScrollController,
          onBack: leaveTeamSpectating,
        ),
      WBScreen.board => BoardScreen(
          board: board,
          tabGlobal: boardGlobal,
          onGlobalTab: () {
            setState(() {
              boardGlobal = true;
              board = null;
            });
            unawaited(_loadBoard());
          },
          onClassTab: () {
            setState(() {
              boardGlobal = false;
              board = null;
            });
            unawaited(_loadBoard());
          },
          onHome: () => go(WBScreen.lobby),
          onFriends: () => go(WBScreen.friends),
          onProfile: () => go(WBScreen.profile),
          friendRequestCount: friendRequests.length,
          previousTab: previousNavTab,
        ),
      WBScreen.profile => ProfileScreen(
          profile: profile,
          onHome: () => go(WBScreen.lobby),
          onFriends: () => go(WBScreen.friends),
          onBoard: () => go(WBScreen.board),
          friendRequestCount: friendRequests.length,
          onHistory: () => go(WBScreen.history),
          onLogout: logout,
          onDeleteAccount: deleteAccount,
          busy: busy,
          previousTab: previousNavTab,
        ),
      WBScreen.history => HistoryScreen(
          matches: history,
          onBack: () => go(WBScreen.profile),
        ),
      WBScreen.practice => PracticeScreen(
          word: practiceWord,
          hints: practiceHints,
          onHint: loadHints,
          onBack: () => go(WBScreen.lobby),
        ),
      WBScreen.friends => FriendsScreen(
          search: search,
          searchResults: searchResults,
          isRequestSent: requestSentTo,
          requests: friendRequests,
          friends: friends,
          onSearchChanged: setSearch,
          onSendRequest: sendFriendRequest,
          onAccept: acceptRequest,
          onDecline: declineRequest,
          onChallenge: challenge,
          onSpectate: spectate,
          onTeamInvite: inviteToTeam,
          onHome: () => go(WBScreen.lobby),
          onBoard: () => go(WBScreen.board),
          onProfile: () => go(WBScreen.profile),
          onOrganizeTournament: openOrganizeTournament,
          previousTab: previousNavTab,
        ),
      WBScreen.invite => InviteScreen(
          me: user,
          invite: outgoingInvite,
          clock: '0:${_inviteSecondsLeft.toString().padLeft(2, '0')}',
          onSkipToMatch: startMatchmaking,
          onCancel: cancelOutgoingInvite,
        ),
      WBScreen.incoming => IncomingScreen(
          invite: incomingInvite,
          secondsLeft: _inviteSecondsLeft,
          progress: incomingInvite == null || incomingInvite!.secondsLeft == 0
              ? 0
              : _inviteSecondsLeft / incomingInvite!.secondsLeft,
          onAccept: acceptIncoming,
          onDismiss: declineIncoming,
        ),
      WBScreen.teamInvite => TeamInviteScreen(
          me: user,
          invite: outgoingTeamInvite,
          clock: '0:${_teamInviteSecondsLeft.toString().padLeft(2, '0')}',
          onCancel: cancelOutgoingTeamInvite,
        ),
      WBScreen.teamIncoming => TeamIncomingScreen(
          invite: incomingTeamInvite,
          secondsLeft: _teamInviteSecondsLeft,
          progress: incomingTeamInvite == null || incomingTeamInvite!.secondsLeft == 0
              ? 0
              : _teamInviteSecondsLeft / incomingTeamInvite!.secondsLeft,
          onAccept: acceptIncomingTeamInvite,
          onDismiss: declineIncomingTeamInvite,
        ),
      WBScreen.tournamentInvite => TournamentInviteScreen(
          invite: tournamentInvite,
          onAccept: acceptTournamentInvite,
          onDecline: declineTournamentInvite,
        ),
      WBScreen.tournamentBracket => TournamentBracketScreen(
          detail: tournamentDetail,
          onBack: () => go(WBScreen.lobby),
          meId: me?.id,
          onCancel: cancelViewedTournament,
        ),
      WBScreen.organizeTournamentSetup => OrganizeTournamentScreen(
          friends: friends,
          busy: busy,
          onBack: () => go(WBScreen.friends),
          onSubmit: createAndInviteTournament,
          onSubmitTeams: createAndInviteTeamTournament,
        ),
      WBScreen.organizeTournamentManage => OrganizeTournamentManageScreen(
          tournament: organizingTournament,
          participants: organizingParticipants,
          busy: busy,
          onBack: leaveOrganizingTournament,
          onRefresh: () => unawaited(_loadOrganizingParticipants()),
          onStart: startOrganizedTournament,
          onCancel: cancelOrganizedTournament,
        ),
      WBScreen.tournamentsBrowse => TournamentsBrowseScreen(
          tournaments: tournamentBrowseList,
          loading: _tournamentBrowseLoading,
          loadingMore: _tournamentBrowseLoadingMore,
          busy: busy,
          meRating: user?.rating,
          onBack: () => go(WBScreen.lobby),
          onRefresh: () => unawaited(_loadTournamentsBrowse(0)),
          onLoadMore: _tournamentBrowseLoadingMore || !_tournamentBrowseHasMore ? null : loadMoreTournamentsBrowse,
          onSpectate: openTournamentBracket,
          onJoin: joinTournament,
        ),
    };
  }

  String _clock(DateTime? since) {
    if (since == null) return '0:00';
    final seconds = DateTime.now().difference(since).inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

/// A dismissible strip for connection trouble and refused actions. The design
/// has no such element — on a real network something has to say what went wrong.
class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: WBColors.bannerFill,
          border: Border.all(color: WBColors.redA(.35)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: WBText.grotesk(size: 12.5, weight: FontWeight.w500, color: WBColors.redSoft),
              ),
            ),
            const SizedBox(width: 10),
            Text('×', style: WBText.grotesk(size: 16, color: WBColors.textA(.5))),
          ],
        ),
      ),
    );
  }
}
