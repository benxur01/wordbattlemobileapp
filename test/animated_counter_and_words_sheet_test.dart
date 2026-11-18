import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/duel_models.dart';
import 'package:word_battle/screens/lose_screen.dart';
import 'package:word_battle/screens/win_screen.dart';
import 'package:word_battle/widgets/animated_counter.dart';
import 'package:word_battle/widgets/post_match_words_sheet.dart';

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

  group('AnimatedCounter widget tests', () {
    testWidgets('renders initial value and prefix/suffix properly', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedCounter(
            value: 42,
            prefix: '+',
            suffix: ' ball',
            duration: Duration(milliseconds: 300),
          ),
        ),
      );

      // Settle animation
      await tester.pumpAndSettle();

      expect(find.text('+42 ball'), findsOneWidget);
    });

    testWidgets('handles negative numbers properly', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedCounter(
            value: -25,
            duration: Duration(milliseconds: 300),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('-25'), findsOneWidget);
    });

    testWidgets('animates progressively and invokes onComplete callback', (tester) async {
      var completed = false;

      await tester.pumpWidget(
        wrap(
          AnimatedCounter(
            value: 100,
            duration: const Duration(milliseconds: 500),
            onComplete: (_) => completed = true,
          ),
        ),
      );

      expect(completed, isFalse);

      // Advance halfway
      await tester.pump(const Duration(milliseconds: 250));
      expect(completed, isFalse);

      // Complete animation
      await tester.pump(const Duration(milliseconds: 350));
      expect(completed, isTrue);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('animates value transition when widget updates', (tester) async {
      var currentValue = 10;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return wrap(
              GestureDetector(
                onTap: () => setState(() => currentValue = 50),
                child: AnimatedCounter(
                  value: currentValue,
                  duration: const Duration(milliseconds: 300),
                ),
              ),
            );
          },
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('10'), findsOneWidget);

      // Trigger update
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      // Mid-transition
      await tester.pumpAndSettle();
      expect(find.text('50'), findsOneWidget);
    });
  });

  group('PostMatchWordsSheet widget tests', () {
    final List<ChainWord> sampleWords = [
      const ChainWord(word: 'KITOB', mine: true, spentMs: 3000),
      const ChainWord(word: 'BOLA', mine: false, spentMs: 4000),
      const ChainWord(word: 'ANOR', mine: true, spentMs: 2000),
      const ChainWord(word: 'RAQAM', mine: false, spentMs: 5000),
    ];

    testWidgets('renders all words and summary counts properly', (tester) async {
      await tester.pumpWidget(
        wrap(
          PostMatchWordsSheet(
            words: sampleWords,
            opponentName: 'Aziz',
          ),
        ),
      );

      expect(find.text("JANG SO'ZLARI TAHLILI"), findsOneWidget);
      expect(find.text("4 ta aytilgan so'z"), findsOneWidget);

      // Verify words are visible
      expect(find.text('KITOB'), findsOneWidget);
      expect(find.text('BOLA'), findsOneWidget);
      expect(find.text('ANOR'), findsOneWidget);
      expect(find.text('RAQAM'), findsOneWidget);

      // Verify tabs
      expect(find.text('Barchasi'), findsOneWidget);
      expect(find.text('Seniki'), findsOneWidget);
      expect(find.text('Aziz'), findsOneWidget);
    });

    testWidgets('filtering by tab switches visible word lists', (tester) async {
      await tester.pumpWidget(
        wrap(
          PostMatchWordsSheet(
            words: sampleWords,
            opponentName: 'Aziz',
          ),
        ),
      );

      // Tap "Seniki" tab
      await tester.tap(find.text('Seniki'));
      await tester.pumpAndSettle();

      // Only player words should be visible
      expect(find.text('KITOB'), findsOneWidget);
      expect(find.text('ANOR'), findsOneWidget);
      expect(find.text('BOLA'), findsNothing);
      expect(find.text('RAQAM'), findsNothing);

      // Tap "Aziz" tab
      await tester.tap(find.text('Aziz'));
      await tester.pumpAndSettle();

      // Only opponent words should be visible
      expect(find.text('BOLA'), findsOneWidget);
      expect(find.text('RAQAM'), findsOneWidget);
      expect(find.text('KITOB'), findsNothing);
      expect(find.text('ANOR'), findsNothing);
    });

    testWidgets('tapping word invokes onWordTap callback', (tester) async {
      String? tappedWord;

      await tester.pumpWidget(
        wrap(
          PostMatchWordsSheet(
            words: sampleWords,
            onWordTap: (w) => tappedWord = w,
          ),
        ),
      );

      await tester.tap(find.text('KITOB'));
      await tester.pump();

      expect(tappedWord, 'KITOB');
    });

    testWidgets('shows empty state when word list is empty', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PostMatchWordsSheet(
            words: [],
          ),
        ),
      );

      expect(find.text("Bu toifada so'z topilmadi"), findsOneWidget);
    });
  });

  group('Post-match screens integration tests', () {
    const duelResultWin = FinishedDuel(
      duelId: 'test-duel-1',
      won: true,
      reason: 'opponent_timeout',
      delta: 32,
      ratingBefore: 1200,
      ratingAfter: 1232,
      chainLength: 3,
      rated: true,
      streakDays: 5,
      yourWords: 3,
      newWords: 1,
      averageMs: 2800,
      stuckLetter: null,
      hints: [],
      opponentId: 42,
      opponentIsBot: false,
      words: [
        ChainWord(word: 'OLMA', mine: true, spentMs: 2000),
        ChainWord(word: 'ASAL', mine: false, spentMs: 3000),
        ChainWord(word: 'LOLA', mine: true, spentMs: 1000),
      ],
    );

    const duelResultLose = FinishedDuel(
      duelId: 'test-duel-2',
      won: false,
      reason: 'timeout',
      delta: -18,
      ratingBefore: 1232,
      ratingAfter: 1214,
      chainLength: 2,
      rated: true,
      streakDays: 5,
      yourWords: 2,
      newWords: 0,
      averageMs: 3200,
      stuckLetter: 'A',
      hints: ['ANOR', 'ASAL'],
      opponentId: 43,
      opponentIsBot: false,
      words: [
        ChainWord(word: 'KITOB', mine: true, spentMs: 2000),
        ChainWord(word: 'BOLA', mine: false, spentMs: 4000),
      ],
    );

    testWidgets('WinScreen renders AnimatedCounter and post-match words button', (tester) async {
      await tester.pumpWidget(
        wrap(
          WinScreen(
            result: duelResultWin,
            onRematch: () {},
            onHome: () {},
          ),
        ),
      );

      // Pump duration for counters rather than pumpAndSettle due to ConfettiRain infinite loop
      await tester.pump(const Duration(milliseconds: 1000));

      expect(find.byType(AnimatedCounter), findsWidgets);
      expect(find.byKey(const ValueKey('post_match_words_button')), findsOneWidget);
      expect(find.text("So'zlar tahlili (3)"), findsOneWidget);
    });

    testWidgets('LoseScreen renders AnimatedCounter and post-match words button', (tester) async {
      await tester.pumpWidget(
        wrap(
          LoseScreen(
            result: duelResultLose,
            onRematch: () {},
            onHome: () {},
            onPractice: () {},
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 1000));

      expect(find.byType(AnimatedCounter), findsWidgets);
      expect(find.byKey(const ValueKey('post_match_words_button')), findsOneWidget);
      expect(find.text("So'zlar tahlili (2)"), findsOneWidget);
    });

    testWidgets('Tapping words button in WinScreen opens bottom sheet', (tester) async {
      await tester.pumpWidget(
        wrap(
          WinScreen(
            result: duelResultWin,
            onRematch: () {},
            onHome: () {},
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byKey(const ValueKey('post_match_words_button')));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PostMatchWordsSheet), findsOneWidget);
      expect(find.text('OLMA'), findsOneWidget);
      expect(find.text('ASAL'), findsOneWidget);
      expect(find.text('LOLA'), findsOneWidget);
    });
  });
}
