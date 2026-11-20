import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/duel_models.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/screens/duel_screen.dart';
import 'package:word_battle/utils/word_combo_evaluator.dart';
import 'package:word_battle/widgets/chain_bubble.dart';
import 'package:word_battle/widgets/word_combo_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 400, height: 750, child: child),
        ),
      ),
    );
  }

  group('WordComboEvaluator unit tests', () {
    test('awards long word combo for 7-8 letter words', () {
      final res8 = WordComboEvaluator.evaluateWord('BILIMLAR');
      expect(res8, isNotNull);
      expect(res8!.type, WordComboType.longWord);
      expect(res8.title, "UZUN SO'Z!");
      expect(res8.bonusPoints, greaterThanOrEqualTo(8));
      expect(res8.multiplier, 1.5);
    });

    test('awards mega combo for 9+ letter epic words', () {
      final res9 = WordComboEvaluator.evaluateWord('BILIMDONLAR');
      expect(res9, isNotNull);
      expect(res9!.type, WordComboType.megaCombo);
      expect(res9.title, "AQLBOVAR QILMAS!");
      expect(res9.bonusPoints, greaterThanOrEqualTo(15));
      expect(res9.multiplier, 2.0);
    });

    test('awards rare letter combo for words with Q, X, F, H, J, V', () {
      final resSingle = WordComboEvaluator.evaluateWord('QALAM');
      expect(resSingle, isNotNull);
      expect(resSingle!.type, WordComboType.rareLetter);
      expect(resSingle.title, "NOYOB HARF!");
      expect(resSingle.rareLetters, contains('Q'));

      final resMulti = WordComboEvaluator.evaluateWord('QALQON');
      expect(resMulti, isNotNull);
      expect(resMulti!.type, WordComboType.rareLetter);
      expect(resMulti.rareLetters.length, 2);
    });

    test('awards speed demon combo for fast answers within 2.2 seconds', () {
      final resSpeed = WordComboEvaluator.evaluateWord('OLMA', spentMs: 1400);
      expect(resSpeed, isNotNull);
      expect(resSpeed!.type, WordComboType.speedDemon);
      expect(resSpeed.title, "CHAQMOQ TEZKOR!");
      expect(resSpeed.subtitle, contains('1.4 soniyada'));
    });

    test('returns null for common words below thresholds', () {
      // 4-letter word with no rare letters and slow speed
      final resCommon = WordComboEvaluator.evaluateWord('BOLA', spentMs: 4500);
      expect(resCommon, isNull);

      // Too short word (< 4 letters)
      final resShort = WordComboEvaluator.evaluateWord('GUL', spentMs: 1000);
      expect(resShort, isNull);
    });
  });

  group('WordComboBadge widget tests', () {
    testWidgets('renders combo badge title, subtitle and bonus points', (tester) async {
      await tester.pumpWidget(
        wrap(
          const WordComboBadge(
            type: WordComboType.longWord,
            title: "UZUN SO'Z!",
            subtitle: '8 ta harf',
            bonusPoints: 12,
            enableSound: false,
          ),
        ),
      );

      // Step animation forward
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text("UZUN SO'Z!"), findsOneWidget);
      expect(find.text('8 ta harf'), findsOneWidget);
      expect(find.text('+12'), findsOneWidget);
      expect(find.byType(WordComboBadge), findsOneWidget);
    });

    testWidgets('invokes onComplete callback after lifespan duration', (tester) async {
      var completed = false;

      await tester.pumpWidget(
        wrap(
          WordComboBadge(
            type: WordComboType.megaCombo,
            duration: const Duration(milliseconds: 600),
            onComplete: () => completed = true,
            enableSound: false,
          ),
        ),
      );

      expect(completed, isFalse);

      await tester.pump(const Duration(milliseconds: 300));
      expect(completed, isFalse);

      // Finish duration
      await tester.pump(const Duration(milliseconds: 350));
      expect(completed, isTrue);
    });
  });

  group('ChainBubble and DuelScreen combo integration tests', () {
    testWidgets('ChainBubble renders combo sparkle icon for long/rare words', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ChainBubble(
            word: 'QALAM',
            isMe: true,
            ms: '1.8s',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ChainBubble), findsOneWidget);
      expect(find.byIcon(Icons.stars_rounded), findsOneWidget);
    });

    testWidgets('ChainBubble renders auto awesome icon for 7+ letter words', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ChainBubble(
            word: 'BILIMLAR',
            isMe: false,
            ms: '2.5s',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    });

    testWidgets('DuelScreen shows WordComboBadge when player submits combo word', (tester) async {
      const testOpponent = UserDto(
        id: 2,
        nickname: 'Raqib',
        displayName: 'Raqib',
        initial: 'R',
        city: 'Samarqand',
        rating: 1200,
        streakDays: 4,
      );

      const testMe = UserDto(
        id: 1,
        nickname: 'Jasur',
        displayName: 'Jasur',
        initial: 'J',
        city: 'Toshkent',
        rating: 1250,
        streakDays: 5,
      );

      final initialDuel = DuelView(
        duelId: 'test-duel-combo',
        opponent: testOpponent,
        rated: true,
        theme: null,
        chain: const [
          ChainWord(word: 'KITOB', mine: false, spentMs: 3000),
        ],
        yourTurn: true,
        needLetter: 'B',
        substitutedFrom: null,
        substitutionReason: null,
        timeLeftMs: 15000,
        turnSeconds: 15,
        yourWords: 0,
        opponentWords: 1,
        opponentThinking: false,
      );

      final updatedDuel = DuelView(
        duelId: 'test-duel-combo',
        opponent: testOpponent,
        rated: true,
        theme: null,
        chain: const [
          ChainWord(word: 'KITOB', mine: false, spentMs: 3000),
          ChainWord(word: 'QALQON', mine: true, spentMs: 1800), // 2 rare Q's!
        ],
        yourTurn: false,
        needLetter: 'N',
        substitutedFrom: null,
        substitutionReason: null,
        timeLeftMs: 15000,
        turnSeconds: 15,
        yourWords: 1,
        opponentWords: 1,
        opponentThinking: true,
      );

      final controller = ScrollController();

      await tester.pumpWidget(
        wrap(
          DuelScreen(
            duel: initialDuel,
            me: testMe,
            error: '',
            scrollController: controller,
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
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(WordComboBadge), findsNothing);

      // Rebuild with updated duel containing combo word
      await tester.pumpWidget(
        wrap(
          DuelScreen(
            duel: updatedDuel,
            me: testMe,
            error: '',
            scrollController: controller,
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
      );

      // Advance animation halfway
      await tester.pump(const Duration(milliseconds: 250));

      // WordComboBadge should now be visible on screen celebrating the combo!
      expect(find.byType(WordComboBadge), findsOneWidget);
      expect(find.text("NOYOB HARFLAR!"), findsOneWidget);

      // Finish lifespan and clean up timers
      await tester.pump(const Duration(milliseconds: 2500));
    });
  });
}
