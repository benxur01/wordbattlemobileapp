import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/api_client.dart';
import 'api/api_exception.dart';
import 'api/duel_models.dart';
import 'api/game_socket.dart';
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
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  final ApiClient _api = ApiClient();
  late final Session _session = Session(_api);
  final GameSocket _socket = GameSocket();

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
    // Backgrounding the app mid-search should not leave a ghost in the queue.
    if (state == AppLifecycleState.paused && screen == WBScreen.match) {
      _socket.send('queue.leave');
    }
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
      if (!mounted) return;
      setState(() {
        screen = WBScreen.offline;
        banner = e.message;
      });
    }
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
      } else if (status == SocketStatus.connected) {
        setState(() => banner = null);
      }
    });
    _socket.connect(token);
  }

  // ------------------------------------------------------------------- auth

  /// The design's Telegram button. Until a bot token is configured the backend
  /// only offers the development login, which is what this uses.
  Future<void> login() async {
    if (busy) return;
    setState(() {
      busy = true;
      banner = null;
    });
    try {
      final id = DateTime.now().millisecondsSinceEpoch % 1000000000;
      final result = await _api.loginDev(id, 'player$id');
      await _session.save(result.token, result.user);
      if (!mounted) return;
      me = result.user;
      _connectSocket();
      setState(() {
        busy = false;
        screen = result.needsNickname ? WBScreen.onb2 : WBScreen.lobby;
      });
      unawaited(_refreshSocial());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        banner = e.message;
      });
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
    } on ApiException catch (_) {
      // The lobby still works without the counters; no need to shout.
    }
  }

  Future<void> _loadBoard() async {
    try {
      final data = boardGlobal ? await _api.globalLeaderboard() : await _api.friendsLeaderboard();
      if (!mounted) return;
      setState(() => board = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => banner = e.message);
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
      if (mounted) setState(() => banner = e.message);
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
      if (mounted) setState(() => banner = e.message);
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
      } on ApiException catch (_) {
        if (mounted) setState(() => searchResults = const []);
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
      if (mounted) setState(() => banner = e.message);
    }
    await _refreshSocial();
  }

  Future<void> declineRequest(FriendRequestDto request) async {
    setState(() => friendRequests = friendRequests.where((r) => r.id != request.id).toList());
    try {
      await _api.declineFriendRequest(request.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => banner = e.message);
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
      case 'queue.joined':
        setState(() => queuedAt = DateTime.now());
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
        if (current == null) return;
        setState(() {
          duel = current.applyUpdate(event.payload);
          duelError = '';
        });
        _scrollChainToBottom();
      case 'duel.rejected':
        setState(() => duelError = event.payload['message'] as String? ?? "So'z qabul qilinmadi");
      case 'duel.finished':
        final result = FinishedDuel.fromJson(event.payload);
        setState(() {
          finished = result;
          duel = null;
          screen = result.won ? WBScreen.win : WBScreen.lose;
        });
        unawaited(_refreshSocial());
      case 'invite.sent':
        setState(() {
          outgoingInvite = PendingInvite(
            inviteId: event.payload['inviteId'] as String,
            user: UserDto.fromJson(event.payload['to'] as Map<String, dynamic>),
            secondsLeft: (event.payload['expiresInSeconds'] as num?)?.toInt() ?? 12,
          );
          _inviteStartedAt = DateTime.now();
          _inviteSecondsLeft = outgoingInvite!.secondsLeft;
          screen = WBScreen.invite;
        });
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
        setState(() {
          outgoingInvite = null;
          banner = 'Chaqiruv rad etildi';
          if (screen == WBScreen.invite) screen = WBScreen.friends;
        });
      case 'invite.expired':
        setState(() {
          outgoingInvite = null;
          incomingInvite = null;
          if (screen == WBScreen.invite) screen = WBScreen.friends;
          if (screen == WBScreen.incoming) screen = WBScreen.lobby;
        });
      case 'error':
        setState(() => banner = event.payload['message'] as String? ?? 'Xatolik');
    }
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

  void _tickInvite() {
    final started = _inviteStartedAt;
    final invite = screen == WBScreen.invite ? outgoingInvite : incomingInvite;
    if (started == null || invite == null) return;
    final left = invite.secondsLeft - DateTime.now().difference(started).inSeconds;
    setState(() => _inviteSecondsLeft = left < 0 ? 0 : left);
  }

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

  void startMatchmaking() {
    setState(() {
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
      WBScreen.onb1 => Onboarding1Screen(onNext: login, busy: busy),
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
          previousTab: previousNavTab,
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
