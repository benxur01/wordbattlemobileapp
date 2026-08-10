import 'dart:async';

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
import 'models.dart';
import 'theme.dart';
import 'screens/onboarding1_screen.dart';
import 'screens/onboarding2_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/matchmaking_screen.dart';
import 'screens/duel_screen.dart';
import 'screens/win_screen.dart';
import 'screens/lose_screen.dart';
import 'screens/board_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/history_screen.dart';
import 'screens/practice_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/invite_screen.dart';
import 'screens/incoming_screen.dart';
import 'screens/loading_screen.dart';
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
  if (screen != WBScreen.match) return QueueAction.none;
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
    WBScreen.duel || WBScreen.match || WBScreen.win || WBScreen.lose => InviteSentAction.withdraw,
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
  DateTime _lastTick = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _onTick());
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _nickDebounce?.cancel();
    _searchDebounce?.cancel();
    _socketEvents?.cancel();
    _socketStatus?.cancel();
    _socket.dispose();
    _api.close();
    chainScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (queueActionFor(state, screen)) {
      case QueueAction.leave:
        _socket.send('queue.leave');
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
    if (screen != WBScreen.match) return;
    _socket.send('queue.join');
  }

  // -------------------------------------------------------------- bootstrap

  Future<void> _bootstrap() async {
    setState(() {
      screen = WBScreen.loading;
      banner = null;
    });
    try {
      final restored = await _session.restore();
      if (!mounted) return;
      if (restored) {
        me = _session.user;
        _connectSocket();
        setState(() => screen = me?.nickname == null ? WBScreen.onb2 : WBScreen.lobby);
        unawaited(_refreshSocial());
      } else {
        setState(() => screen = WBScreen.onb1);
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
      screen = WBScreen.offline;
      banner = message;
    });
  }

  void _connectSocket() {
    final token = _session.token;
    if (token == null) return;

    _socketEvents?.cancel();
    _socketStatus?.cancel();
    _socketEvents = _socket.events.listen(_onSocketEvent);
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
    }
  }

  Future<void> _loadBoard() async {
    try {
      final data = boardGlobal ? await _api.globalLeaderboard() : await _api.friendsLeaderboard();
      if (!mounted) return;
      setState(() => board = data);
    } on ApiException catch (e) {
      _onApiError(e);
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

  void _onSocketEvent(SocketEvent event) {
    if (!mounted) return;
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
        setState(() {
          duel = DuelView.fromMatchFound(event.payload);
          duelError = '';
          finished = null;
          queuedAt = null;
          outgoingInvite = null;
          incomingInvite = null;
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
        });
        _scrollChainToBottom();
      case 'duel.rejected':
        setState(() => duelError = event.payload['message'] as String? ?? "So'z qabul qilinmadi");
      case 'duel.finished':
        final result = FinishedDuel.fromJson(event.payload);
        if (!duelFrameApplies(duel?.duelId, result.duelId)) return;
        setState(() {
          finished = result;
          duel = null;
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
          // Never interrupt a live duel with a challenge sheet.
          if (screen != WBScreen.duel) screen = WBScreen.incoming;
        });
      case 'invite.declined':
        _settleInvite(event.payload['inviteId'] as String?, refused: true);
      case 'invite.expired':
        _settleInvite(event.payload['inviteId'] as String?, refused: false);
      case 'duel.aborted':
        // The server is going away mid-duel. Nobody won; say so plainly rather
        // than leaving the duel screen frozen on a turn that will never end.
        setState(() {
          duel = null;
          finished = null;
          banner = event.payload['message'] as String? ?? 'Jang bekor qilindi';
          if (screen == WBScreen.duel) screen = WBScreen.lobby;
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
    if (resumed == null) return;
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

  void _onTick() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTick).inMilliseconds;
    _lastTick = now;
    if (!mounted) return;

    final current = duel;
    if (screen == WBScreen.duel && current != null && current.timeLeftMs > 0) {
      setState(() => duel = current.tick(elapsed));
    } else if (screen == WBScreen.match && queuedAt != null) {
      setState(() {}); // redraw the elapsed clock
    } else if (screen == WBScreen.invite || screen == WBScreen.incoming) {
      _tickInvite();
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

  void submitWord(String word) {
    if (word.trim().isEmpty) return;
    _socket.send('duel.submit', {'word': word.trim()});
  }

  void challenge(FriendDto friend) => _socket.send('invite.send', {'userId': friend.user.id});

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
    if (screen == WBScreen.duel && next != WBScreen.duel) _socket.send('duel.forfeit');
    if (screen == WBScreen.match && next != WBScreen.match) _socket.send('queue.leave');

    setState(() {
      screen = next;
      banner = null;
      duelError = '';
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
      case WBScreen.friends:
      case WBScreen.lobby:
        unawaited(_refreshSocial());
      default:
        break;
    }
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
      WBScreen.loading => const LoadingScreen(),
      WBScreen.offline => LoadingScreen(
          message: banner ?? "Serverga ulanib bo'lmadi",
          onRetry: _bootstrap,
        ),
      WBScreen.onb1 => Onboarding1Screen(
          onGoogle: loginWithGoogle,
          onDevLogin: ApiConfig.googleConfigured ? null : loginDev,
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
          onStartMatch: startMatchmaking,
          onFriends: () => go(WBScreen.friends),
          onPractice: () => go(WBScreen.practice),
          onIncoming: () => go(WBScreen.incoming),
          onBoard: () => go(WBScreen.board),
          onProfile: () => go(WBScreen.profile),
          previousTab: previousNavTab,
        ),
      WBScreen.match => MatchmakingScreen(
          user: user,
          matchClock: _clock(queuedAt),
          onCancel: cancelMatchmaking,
        ),
      WBScreen.duel => DuelScreen(
          duel: duel,
          me: user,
          error: duelError,
          scrollController: chainScrollController,
          onSubmit: submitWord,
        ),
      WBScreen.win => WinScreen(
          result: finished,
          onRematch: startMatchmaking,
          onHome: () => go(WBScreen.lobby),
        ),
      WBScreen.lose => LoseScreen(
          result: finished,
          onRematch: startMatchmaking,
          onPractice: () => go(WBScreen.practice),
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
          onHome: () => go(WBScreen.lobby),
          onBoard: () => go(WBScreen.board),
          onProfile: () => go(WBScreen.profile),
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
          color: const Color(0xFF241B1D),
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
