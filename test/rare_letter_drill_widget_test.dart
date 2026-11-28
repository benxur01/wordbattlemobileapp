import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/audio/sound_effects.dart';
import 'package:word_battle/screens/practice_screen.dart';
import 'package:word_battle/theme.dart';
import 'package:word_battle/widgets/circular_mastery_ring.dart';
import 'package:word_battle/widgets/rare_letter_drill_panel.dart';

Widget _wrapScreen({
  PracticeWordDto? word = const PracticeWordDto(
    word: 'harbour',
    ipa: '/ˈhɑːbə/',
    meaning: 'bandargoh',
  ),
  List<RareLetterDrillDto> rareDrills = const [],
  VoidCallback? onRotateDrillPrompt,
  Future<PracticeCheckDto> Function(String letter, String word)? onCheckDrillWord,
  double bottomInset = 0,
}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: WBTheme.isLight ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: WBColors.bg,
    ),
    home: Scaffold(
      backgroundColor: WBColors.bg,
      body: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 784),
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: PracticeScreen(
          word: word,
          hints: const ['river', 'rocket'],
          onHint: () {},
          onBack: () {},
          rareDrills: rareDrills,
          onRotateDrillPrompt: onRotateDrillPrompt,
          onCheckDrillWord: onCheckDrillWord,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffects.instance.resetForTesting();
  });

  group('CircularMasteryRing & RareLetterDrillPanel', () {
    testWidgets('animates ring progress, emits semantics percentage, and plays particle burst', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var progress = 0.2;
        var burst = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    CircularMasteryRing(
                      letter: 'x',
                      progress: progress,
                      accentColor: WBColors.cta,
                      burstNonce: burst,
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        progress = 0.6;
                        burst++;
                      }),
                      child: const Text('Boost'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(find.text('X'), findsOneWidget);
        expect(find.bySemanticsLabel('X harfi mahorati: 20 foiz'), findsOneWidget);

        await tester.tap(find.text('Boost'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel('X harfi mahorati: 60 foiz'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('switches between X and Q drill tiles, submits rare words, and rotates prompts', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var rotations = 0;
      final checkedRequests = <(String, String)>[];

      await tester.pumpWidget(
        _wrapScreen(
          onRotateDrillPrompt: () => rotations++,
          onCheckDrillWord: (letter, word) async {
            checkedRequests.add((letter, word));
            return const PracticeCheckDto(valid: true);
          },
        ),
      );
      await tester.pump();

      // Switch header pill to X · Q drill mode.
      await tester.tap(find.text('X · Q'));
      await tester.pumpAndSettle();

      expect(find.byType(RareLetterDrillPanel), findsOneWidget);
      expect(find.text('NOYOB · X'), findsOneWidget);
      expect(find.text('NOYOB · Q'), findsOneWidget);
      expect(find.text('apex'), findsOneWidget);

      // Tap sample hint 'xenon' -> prefill -> submit -> updates X mastery to 1/5 (20%).
      await tester.ensureVisible(find.text('xenon'));
      await tester.tap(find.text('xenon'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(checkedRequests, [('x', 'xenon')]);
      expect(find.text('1/5 so\'z'), findsOneWidget);
      expect(find.text('20% mahorat'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));

      // Switch to Q drill -> required letter updates to 'Q'.
      await tester.ensureVisible(find.text('NOYOB · Q'));
      await tester.tap(find.text('NOYOB · Q'));
      await tester.pumpAndSettle();

      expect(find.text('quartz'), findsOneWidget);
      expect(find.text('MAQSAD: Q-SO\'Z'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'quorum');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(checkedRequests.last, ('q', 'quorum'));
      expect(find.text('Qayta boshlash'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));

      // Rotate prompt word (card button is the first 'Keyingi' above the bottom dock).
      await tester.ensureVisible(find.text('Keyingi').first);
      await tester.tap(find.text('Keyingi').first);
      await tester.pump();
      expect(rotations, 1);

      // Reset Q mastery back to 0/5.
      await tester.ensureVisible(find.text('Qayta boshlash'));
      await tester.tap(find.text('Qayta boshlash'));
      await tester.pumpAndSettle();
      expect(find.text('Qayta boshlash'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out cleanly on 360x784 with open keyboard and light theme', (tester) async {
      WBTheme.followPlatform(Brightness.light);
      addTearDown(() => WBTheme.followPlatform(Brightness.dark));

      tester.view.physicalSize = const Size(360, 784);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapScreen(word: null, bottomInset: 320));
      await tester.pump();

      await tester.tap(find.text('X · Q'));
      await tester.pumpAndSettle();

      expect(find.byType(RareLetterDrillPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
