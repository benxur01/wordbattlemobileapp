import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/screens/lobby_screen.dart';
import 'package:word_battle/theme.dart';
import 'package:word_battle/widgets/provisional_badge.dart';

UserDto _sampleUser({bool provisional = false, int streakDays = 3}) => UserDto(
      id: 7,
      nickname: 'sardor',
      displayName: 'Sardor',
      initial: 'S',
      city: 'Toshkent',
      rating: 1240,
      streakDays: streakDays,
      provisional: provisional,
    );

Widget _buildHarness({
  required UserDto? user,
  VoidCallback? onStartMatch,
  VoidCallback? onBotBattle,
  VoidCallback? onFriends,
  VoidCallback? onPractice,
  VoidCallback? onOpenTournamentsBrowse,
}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: WBTheme.isLight ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: WBColors.bg,
    ),
    home: Scaffold(
      backgroundColor: WBColors.bg,
      body: LobbyScreen(
        user: user,
        onlineCount: 18,
        friendRequestCount: 2,
        friendsOnlineCount: 4,
        incoming: null,
        onStartMatch: onStartMatch ?? () {},
        onBotBattle: onBotBattle ?? () {},
        onFriends: onFriends ?? () {},
        onPractice: onPractice ?? () {},
        onIncoming: () {},
        onBoard: () {},
        onProfile: () {},
        onOpenTournamentsBrowse: onOpenTournamentsBrowse ?? () {},
      ),
    ),
  );
}

void main() {
  group('LobbyScreen obsidian UI & interactions', () {
    testWidgets('renders flush header, Hero Duel Card, and unified mode tiles without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 784);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildHarness(user: _sampleUser(provisional: true)));
      await tester.pump();

      expect(find.text(_sampleUser().label), findsOneWidget);
      expect(find.text('Toshkent'), findsOneWidget);
      expect(find.text('1240'), findsOneWidget);
      expect(find.byType(ProvisionalBadge), findsOneWidget);
      expect(find.text('ONLAYN · 18'), findsOneWidget);
      expect(find.text("So'z jangiga kiring"), findsOneWidget);
      expect(find.text('JANG BOSHLASH'), findsOneWidget);
      expect(find.text('3 / 7 KUN'), findsOneWidget);
      expect(find.text('Bot bilan jang'), findsOneWidget);
      expect(find.text("Do'stlar"), findsWidgets);
      expect(find.text('Mashq'), findsOneWidget);
      expect(find.text("Barchasini ko'rish"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Hero CTA and mode cards trigger their respective callbacks', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var starts = 0;
      var bots = 0;
      var friends = 0;
      var practices = 0;
      var tournaments = 0;

      await tester.pumpWidget(
        _buildHarness(
          user: _sampleUser(),
          onStartMatch: () => starts++,
          onBotBattle: () => bots++,
          onFriends: () => friends++,
          onPractice: () => practices++,
          onOpenTournamentsBrowse: () => tournaments++,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('JANG BOSHLASH'));
      await tester.tap(find.text('Bot bilan jang'));
      await tester.tap(find.text("Do'stlar").first);
      await tester.tap(find.text('Mashq'));
      await tester.ensureVisible(find.text("Barchasini ko'rish"));
      await tester.tap(find.text("Barchasini ko'rish"));
      await tester.pump();

      expect(starts, 1);
      expect(bots, 1);
      expect(friends, 1);
      expect(practices, 1);
      expect(tournaments, 1);
    });

    testWidgets('uses calm obsidian surfaces without glowing radial portal gradients', (tester) async {
      await tester.pumpWidget(_buildHarness(user: _sampleUser()));
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasRadialPortal = containers.any((c) {
        final dec = c.decoration;
        return dec is BoxDecoration && dec.gradient is RadialGradient;
      });
      expect(hasRadialPortal, isFalse);
    });

    testWidgets('renders cleanly in light mode without layout or paint errors', (tester) async {
      WBTheme.followPlatform(Brightness.light);
      addTearDown(() => WBTheme.followPlatform(Brightness.dark));

      tester.view.physicalSize = const Size(360, 784);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildHarness(user: _sampleUser(streakDays: 7)));
      await tester.pump();

      expect(find.text('7 / 7 KUN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
