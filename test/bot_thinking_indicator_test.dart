import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/duel_models.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/screens/duel_screen.dart';

const _me = UserDto(
  id: 1,
  nickname: 'jasur_07',
  displayName: 'jasur_07',
  initial: 'J',
  city: 'Andijon',
  rating: 1200,
  streakDays: 3,
);

const _botOpponent = UserDto(
  id: 0,
  nickname: 'wordbot',
  displayName: 'Word Bot',
  initial: 'B',
  city: null,
  rating: 1200,
  streakDays: 0,
);

const _humanOpponent = UserDto(
  id: 2,
  nickname: 'aziza_k',
  displayName: 'aziza_k',
  initial: 'A',
  city: 'Toshkent',
  rating: 1250,
  streakDays: 5,
);

DuelView _createDuel({required bool yourTurn, required bool isBot}) {
  return DuelView(
    duelId: 'duel-test-1',
    opponent: isBot ? _botOpponent : _humanOpponent,
    rated: !isBot,
    theme: null,
    chain: const [
      ChainWord(word: 'apple', mine: true, spentMs: 1500),
    ],
    yourTurn: yourTurn,
    needLetter: 'E',
    substitutedFrom: null,
    substitutionReason: null,
    timeLeftMs: 12000,
    turnSeconds: 15,
    yourWords: 1,
    opponentWords: 0,
    opponentThinking: !yourTurn,
  );
}

void main() {
  group('Bot thinking indicator in DuelScreen', () {
    testWidgets('renders specialized bot thinking indicator and hint when bot turn is active', (tester) async {
      final duel = _createDuel(yourTurn: false, isBot: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuelScreen(
              me: _me,
              duel: duel,
              error: '',
              scrollController: ScrollController(),
              onSubmit: (_) {},
              chatLog: const [],
              onSendChat: (_) {},
              onSendReaction: (_) {},
              reaction: null,
              powerUps: const DuelPowerUps(),
              onPowerUp: (_) {},
              onLeave: () {},
              onOpponentActions: (_) {},
            ),
          ),
        ),
      );

      // Verify the bot thinking bubble appears with icon and text
      expect(find.text("Bot o'ylayapti"), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy_rounded), findsOneWidget);

      // Verify input hint shows bot thinking label
      expect(find.text("🤖 Bot o'ylayapti…"), findsOneWidget);
    });

    testWidgets('renders standard human thinking indicator and hint when human opponent turn is active', (tester) async {
      final duel = _createDuel(yourTurn: false, isBot: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuelScreen(
              me: _me,
              duel: duel,
              error: '',
              scrollController: ScrollController(),
              onSubmit: (_) {},
              chatLog: const [],
              onSendChat: (_) {},
              onSendReaction: (_) {},
              reaction: null,
              powerUps: const DuelPowerUps(),
              onPowerUp: (_) {},
              onLeave: () {},
              onOpponentActions: (_) {},
            ),
          ),
        ),
      );

      // Human duel does not say "Bot o'ylayapti"
      expect(find.text("Bot o'ylayapti"), findsNothing);
      expect(find.byIcon(Icons.smart_toy_rounded), findsNothing);

      // Verify human opponent input hint
      expect(find.text("raqib o'ylayapti…"), findsOneWidget);
    });

    testWidgets('does not render thinking bubble on player turn and shows write hint', (tester) async {
      final duel = _createDuel(yourTurn: true, isBot: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuelScreen(
              me: _me,
              duel: duel,
              error: '',
              scrollController: ScrollController(),
              onSubmit: (_) {},
              chatLog: const [],
              onSendChat: (_) {},
              onSendReaction: (_) {},
              reaction: null,
              powerUps: const DuelPowerUps(),
              onPowerUp: (_) {},
              onLeave: () {},
              onOpponentActions: (_) {},
            ),
          ),
        ),
      );

      // No thinking bubble on your own turn
      expect(find.text("Bot o'ylayapti"), findsNothing);

      // Shows your turn write hint
      expect(find.text("so'zni yoz…"), findsOneWidget);
    });
  });
}
