import 'package:flutter/material.dart';

import 'package:word_battle/api/duel_models.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/models.dart';
import 'package:word_battle/theme.dart';
import 'package:word_battle/screens/board_screen.dart';
import 'package:word_battle/screens/duel_screen.dart';
import 'package:word_battle/screens/friends_screen.dart';
import 'package:word_battle/screens/history_screen.dart';
import 'package:word_battle/screens/incoming_screen.dart';
import 'package:word_battle/screens/invite_screen.dart';
import 'package:word_battle/screens/loading_screen.dart';
import 'package:word_battle/screens/lobby_screen.dart';
import 'package:word_battle/screens/lose_screen.dart';
import 'package:word_battle/screens/matchmaking_screen.dart';
import 'package:word_battle/screens/onboarding1_screen.dart';
import 'package:word_battle/screens/onboarding2_screen.dart';
import 'package:word_battle/screens/practice_screen.dart';
import 'package:word_battle/screens/profile_screen.dart';
import 'package:word_battle/screens/win_screen.dart';

/// The test phone: Infinix X6833B, 1080×2460 @480dpi → 360×784dp logical,
/// 36dp status bar. Every screen is pumped at that size, and again with the
/// keyboard open, so a RenderFlex overflow shows up here rather than as black
/// and yellow stripes on the device.
const _device = Size(360, 784);
const _statusBar = 36.0;
const keyboard = 320.0;

Widget canvas(Widget screen, {double keyboardInset = 0}) {
  const designWidth = 412.0;
  return MediaQuery(
    data: MediaQueryData(
      size: _device,
      padding: const EdgeInsets.only(top: _statusBar),
      viewPadding: const EdgeInsets.only(top: _statusBar),
      viewInsets: EdgeInsets.only(bottom: keyboardInset),
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: WBColors.bg),
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = constraints.maxWidth / designWidth;
                final height = (constraints.maxHeight - keyboardInset) / scale;
                return FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: designWidth, height: height, child: screen),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

// ---- fixtures shaped exactly like the server's JSON ----

UserDto _user(int id, String nickname, {int rating = 1284, String? city, int streak = 0}) => UserDto(
      id: id,
      nickname: nickname,
      displayName: nickname,
      initial: nickname.substring(0, 1).toUpperCase(),
      city: city,
      rating: rating,
      streakDays: streak,
    );

final _me = _user(1, 'jasur_07', city: 'Andijon', streak: 7);
final _opponent = _user(2, 'malika_x', rating: 1301, city: 'Toshkent');

DuelView _duel({bool yourTurn = true, int timeLeftMs = 12000, bool thinking = false}) => DuelView(
      duelId: 'duel-1',
      opponent: _opponent,
      rated: true,
      chain: const [
        ChainWord(word: 'battle', mine: false, spentMs: 1800),
        ChainWord(word: 'elephant', mine: true, spentMs: 2400),
        ChainWord(word: 'tomorrow', mine: false, spentMs: 1900),
      ],
      yourTurn: yourTurn,
      needLetter: 'W',
      substitutedFrom: null,
      timeLeftMs: timeLeftMs,
      turnSeconds: 15,
      yourWords: 1,
      opponentWords: 1,
      opponentThinking: thinking,
    );

/// The chain has run into a rare letter, so the server handed over the one
/// before it and the screen has to say why. Paired with a rejection because
/// that is the tallest the input bar ever gets: note and error at once.
final _substitutedDuel = DuelView(
  duelId: 'duel-1',
  opponent: _opponent,
  rated: true,
  chain: const [
    ChainWord(word: 'battle', mine: false, spentMs: 1800),
    ChainWord(word: 'elephant', mine: true, spentMs: 2400),
    ChainWord(word: 'tomorrow', mine: false, spentMs: 1900),
    ChainWord(word: 'wax', mine: true, spentMs: 2100),
  ],
  yourTurn: false,
  needLetter: 'A',
  substitutedFrom: 'X',
  timeLeftMs: 9000,
  turnSeconds: 15,
  yourWords: 2,
  opponentWords: 1,
  opponentThinking: true,
);

const _win = FinishedDuel(
  duelId: 'duel-1',
  won: true,
  reason: 'words_limit',
  rated: true,
  delta: 24,
  ratingBefore: 1284,
  ratingAfter: 1308,
  chainLength: 9,
  yourWords: 5,
  averageMs: 2400,
  newWords: 3,
  streakDays: 8,
  stuckLetter: null,
  hints: [],
  opponentId: 2,
  opponentIsBot: false,
);

const _lose = FinishedDuel(
  duelId: 'duel-1',
  won: false,
  reason: 'timeout',
  rated: true,
  delta: -18,
  ratingBefore: 1284,
  ratingAfter: 1266,
  chainLength: 6,
  yourWords: 3,
  averageMs: 4100,
  newWords: 1,
  streakDays: 7,
  stuckLetter: 'Y',
  hints: ['yellow', 'yesterday', 'young'],
  opponentId: 2,
  opponentIsBot: false,
);

final _profile = ProfileDto(
  user: _me,
  globalRank: 247,
  battles: 128,
  wins: 91,
  winPercent: 71,
  longestChain: 24,
  wordsLearned: 412,
  streakDays: 7,
  weeklyDelta: 42,
  ratingHistory: [
    for (var i = 0; i < 10; i++) RatingPoint(DateTime(2026, 7, 1 + i * 3), 1200 + i * 9),
  ],
  badges: const [
    BadgeDto(code: 'first_battle', label: 'Ilk jang', unlocked: true, progress: 1, target: 1),
    BadgeDto(code: 'streak_7', label: '7 kun', unlocked: true, progress: 7, target: 7),
    BadgeDto(code: 'wins_50', label: "50 g'alaba", unlocked: true, progress: 50, target: 50),
    BadgeDto(code: 'chain_20', label: '20 zanjir', unlocked: true, progress: 24, target: 20),
    BadgeDto(code: 'rating_1500', label: '1500', unlocked: false, progress: 1284, target: 1500),
    BadgeDto(code: 'streak_30', label: '30 kun', unlocked: false, progress: 7, target: 30),
    BadgeDto(code: 'friend_top', label: "Do'st №1", unlocked: false, progress: 0, target: 1),
    BadgeDto(code: 'words_1000', label: "1000 so'z", unlocked: false, progress: 412, target: 1000),
  ],
);

final _board = LeaderboardDto(
  rows: [
    LeaderboardRow(rank: 1, user: _opponent, self: false),
    LeaderboardRow(rank: 2, user: _user(3, 'sardor.eng', rating: 1740, city: 'Samarqand'), self: false),
    LeaderboardRow(rank: 3, user: _user(4, 'nodira_w', rating: 1703, city: "Farg'ona"), self: false),
    LeaderboardRow(rank: 246, user: _user(5, 'aziza.m', rating: 1291, city: 'Andijon'), self: false),
    LeaderboardRow(rank: 247, user: _me, self: true),
  ],
  me: LeaderboardRow(rank: 247, user: _me, self: true),
);

final _friends = [
  FriendDto(user: _user(6, 'otabek_z', rating: 1188), online: true, inBattle: false),
  FriendDto(user: _user(7, 'aziza.m', rating: 1291), online: true, inBattle: true),
  FriendDto(
    user: _user(8, 'shahzod.b', rating: 1102),
    online: false,
    inBattle: false,
    lastSeenAt: DateTime.now().subtract(const Duration(hours: 2)),
  ),
];

final _requests = [
  FriendRequestDto(id: 1, user: _user(9, 'nodira_w', rating: 1703), mutualFriends: 2),
  FriendRequestDto(id: 2, user: _user(10, 'sardor.eng', rating: 1740), mutualFriends: 3),
];

final _invite = PendingInvite(inviteId: 'inv-1', user: _user(6, 'otabek_z', rating: 1188), secondsLeft: 12);

/// An opponent who has since deleted their account, exactly as the server sends
/// one: the row is anonymised, so there is no nickname left and the name it
/// carries is the label the server puts there instead.
const _deletedOpponent = UserDto(
  id: 13,
  nickname: null,
  displayName: "O'chirilgan akkaunt",
  initial: '?',
  city: null,
  rating: 1200,
  streakDays: 0,
);

/// Every history row shape at once: a win and a loss, all four end reasons, an
/// unrated bot duel, a deleted opponent, the longest name a row can carry and a
/// battle old enough to carry its year — the widest each line can get.
final _history = [
  MatchSummaryDto(
    id: 1,
    opponent: _opponent,
    botOpponent: false,
    won: true,
    rated: true,
    delta: 24,
    ratingAfter: 1308,
    chainLength: 12,
    endReason: 'words_limit',
    finishedAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  MatchSummaryDto(
    id: 2,
    opponent: _user(3, 'sardor.eng', rating: 1740),
    botOpponent: false,
    won: false,
    rated: true,
    delta: -18,
    ratingAfter: 1284,
    chainLength: 7,
    endReason: 'timeout',
    finishedAt: DateTime.now().subtract(const Duration(days: 1)),
  ),
  MatchSummaryDto(
    id: 3,
    opponent: _user(-1, 'wordbot', rating: 1200),
    botOpponent: true,
    won: true,
    rated: false,
    delta: 0,
    ratingAfter: 1284,
    chainLength: 9,
    endReason: 'forfeit',
    finishedAt: DateTime.now().subtract(const Duration(days: 4)),
  ),
  MatchSummaryDto(
    id: 4,
    opponent: _deletedOpponent,
    botOpponent: false,
    won: false,
    rated: true,
    delta: -14,
    ratingAfter: 1249,
    chainLength: 5,
    endReason: 'forfeit',
    finishedAt: DateTime.now().subtract(const Duration(days: 6)),
  ),
  MatchSummaryDto(
    id: 5,
    opponent: _user(12, 'shahzod_the_best', rating: 1455),
    botOpponent: false,
    won: false,
    rated: true,
    delta: -21,
    ratingAfter: 1263,
    chainLength: 14,
    endReason: 'no_moves',
    finishedAt: DateTime.utc(2025, 11, 23, 18, 40),
  ),
];

Map<String, Widget> buildScreens() => {
      'loading': const LoadingScreen(),
      'offline': LoadingScreen(message: "Serverga ulanib bo'lmadi", onRetry: () {}),
      'onb1': Onboarding1Screen(onGoogle: () {}, onRegister: (_, _) {}, onLogin: (_, _) {}),
      'onb1-dev': Onboarding1Screen(onGoogle: () {}, onDevLogin: () {}, onRegister: (_, _) {}, onLogin: (_, _) {}),
      'onb1-busy': Onboarding1Screen(onGoogle: () {}, onRegister: (_, _) {}, onLogin: (_, _) {}, busy: true),
      'onb2-idle': Onboarding2Screen(
        nickname: '',
        nickState: NickState.idle,
        nickError: '',
        suggestions: const [],
        onNickChanged: (_) {},
        onPickSuggestion: (_) {},
        onSubmit: null,
      ),
      'onb2-taken': Onboarding2Screen(
        nickname: 'malika_x',
        nickState: NickState.taken,
        nickError: '',
        suggestions: const ['malika_x_uz', 'malika_x42', 'the_malika_x'],
        onNickChanged: (_) {},
        onPickSuggestion: (_) {},
        onSubmit: null,
      ),
      'lobby': LobbyScreen(
        user: _me,
        onlineCount: 1248,
        friendRequestCount: 2,
        friendsOnlineCount: 2,
        incoming: _invite,
        onStartMatch: () {},
        onFriends: () {},
        onPractice: () {},
        onIncoming: () {},
        onBoard: () {},
        onProfile: () {},
      ),
      'lobby-empty': LobbyScreen(
        user: _me,
        onlineCount: 1,
        friendRequestCount: 0,
        friendsOnlineCount: 0,
        incoming: null,
        onStartMatch: () {},
        onFriends: () {},
        onPractice: () {},
        onIncoming: () {},
        onBoard: () {},
        onProfile: () {},
      ),
      'match': MatchmakingScreen(user: _me, matchClock: '0:02', onCancel: () {}),
      'duel': DuelScreen(
        duel: _duel(),
        me: _me,
        error: '',
        scrollController: ScrollController(),
        onSubmit: (_) {},
        chatLog: const [],
        onSendChat: (_) {},
        onSendReaction: (_) {},
        reaction: null,
      ),
      'duel-error': DuelScreen(
        duel: _duel(yourTurn: false, timeLeftMs: 3000, thinking: true),
        me: _me,
        error: '«W» harfi bilan boshlanishi kerak',
        scrollController: ScrollController(),
        onSubmit: (_) {},
        chatLog: const [],
        onSendChat: (_) {},
        onSendReaction: (_) {},
        reaction: null,
      ),
      'duel-substituted': DuelScreen(
        duel: _substitutedDuel,
        me: _me,
        error: '«A» harfi bilan boshlanishi kerak',
        scrollController: ScrollController(),
        onSubmit: (_) {},
        chatLog: const [],
        onSendChat: (_) {},
        onSendReaction: (_) {},
        reaction: null,
      ),
      'win': WinScreen(result: _win, onRematch: () {}, onHome: () {}),
      'lose': LoseScreen(result: _lose, onRematch: () {}, onPractice: () {}),
      'board-global': BoardScreen(
        board: _board,
        tabGlobal: true,
        onGlobalTab: () {},
        onClassTab: () {},
        onHome: () {},
        onFriends: () {},
        onProfile: () {},
        friendRequestCount: 2,
      ),
      'board-loading': BoardScreen(
        board: null,
        tabGlobal: false,
        onGlobalTab: () {},
        onClassTab: () {},
        onHome: () {},
        onFriends: () {},
        onProfile: () {},
        friendRequestCount: 2,
      ),
      'profile': ProfileScreen(
        profile: _profile,
        onHome: () {},
        onFriends: () {},
        onBoard: () {},
        friendRequestCount: 2,
        onHistory: () {},
        onLogout: () {},
        onDeleteAccount: () {},
      ),
      'profile-loading': ProfileScreen(
        profile: null,
        onHome: () {},
        onFriends: () {},
        onBoard: () {},
        friendRequestCount: 0,
        onHistory: () {},
        onLogout: () {},
        onDeleteAccount: () {},
      ),
      'history': HistoryScreen(matches: _history, onBack: () {}),
      'history-empty': HistoryScreen(matches: const [], onBack: () {}),
      'history-loading': HistoryScreen(matches: null, onBack: () {}),
      'practice': PracticeScreen(
        word: const PracticeWordDto(
          word: 'harbour',
          ipa: '/ˈhɑːbə/',
          meaning: "bandargoh, port — kemalar to'xtaydigan joy",
        ),
        hints: const ['river', 'rocket', 'ribbon'],
        onHint: () {},
        onBack: () {},
      ),
      'friends': FriendsScreen(
        search: 'diyor',
        searchResults: [_user(11, 'diyor_k', rating: 1610, city: 'Namangan')],
        isRequestSent: (_) => false,
        requests: _requests,
        friends: _friends,
        onSearchChanged: (_) {},
        onSendRequest: (_) {},
        onAccept: (_) {},
        onDecline: (_) {},
        onChallenge: (_) {},
        onHome: () {},
        onBoard: () {},
        onProfile: () {},
        onOrganizeTournament: () {},
      ),
      'friends-empty': FriendsScreen(
        search: '',
        searchResults: const [],
        isRequestSent: (_) => false,
        requests: const [],
        friends: const [],
        onSearchChanged: (_) {},
        onSendRequest: (_) {},
        onAccept: (_) {},
        onDecline: (_) {},
        onChallenge: (_) {},
        onHome: () {},
        onBoard: () {},
        onProfile: () {},
        onOrganizeTournament: () {},
      ),
      'invite': InviteScreen(
        me: _me,
        invite: _invite,
        clock: '0:07',
        onSkipToMatch: () {},
        onCancel: () {},
      ),
      'incoming': IncomingScreen(
        invite: _invite,
        secondsLeft: 9,
        progress: .75,
        onAccept: () {},
        onDismiss: () {},
      ),
    };
