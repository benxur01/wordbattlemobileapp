import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/screens/practice_screen.dart';
import 'package:word_battle/theme.dart';
import 'package:word_battle/widgets/practice_test_input.dart';

const _wordOfTheDay = PracticeWordDto(
  word: 'harbour',
  ipa: '/ˈhɑːbə/',
  meaning: "bandargoh, port — kemalar to'xtaydigan joy",
);

Widget _wrapPractice({
  PracticeWordDto? word = _wordOfTheDay,
  List<String> hints = const ['river', 'rocket', 'ribbon'],
  Future<PracticeCheckDto> Function(String word)? onCheckWord,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: WBColors.bg),
    home: Scaffold(
      body: SafeArea(
        child: PracticeScreen(
          word: word,
          hints: hints,
          onHint: () {},
          onBack: () {},
          onCheckWord: onCheckWord,
        ),
      ),
    ),
  );
}

BoxDecoration? _inputContainerDecoration(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(PracticeTestInput),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedContainer &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).borderRadius == BorderRadius.circular(18) &&
          (widget.decoration! as BoxDecoration).gradient == null,
    ),
  );
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<AnimatedContainer>(finder.first).decoration as BoxDecoration?;
}

double _shakeDx(WidgetTester tester) {
  final transform = tester.widget<Transform>(find.byKey(const ValueKey('practice_shake_transform')));
  return transform.transform.getTranslation().x;
}

void main() {
  group('PracticeWordValidator', () {
    test('handles empty, invalid characters, wrong starting letter, short, duplicate, and valid words', () {
      expect(
        PracticeWordValidator.validateLive('', needLetter: 'r').phase,
        PracticeInputPhase.idle,
      );
      expect(
        PracticeWordValidator.validateSubmit('', needLetter: 'r').phase,
        PracticeInputPhase.invalid,
      );

      final badChars = PracticeWordValidator.validateLive('riv3r', needLetter: 'r');
      expect(badChars.phase, PracticeInputPhase.invalid);
      expect(badChars.message, 'Faqat ingliz harflari');

      final wrongFirst = PracticeWordValidator.validateLive('apple', needLetter: 'r');
      expect(wrongFirst.phase, PracticeInputPhase.invalid);
      expect(wrongFirst.message, '«R» harfi bilan boshlanishi kerak');

      final shortLive = PracticeWordValidator.validateLive('ri', needLetter: 'r');
      expect(shortLive.phase, PracticeInputPhase.incomplete);
      final shortSubmit = PracticeWordValidator.validateSubmit('ri', needLetter: 'r');
      expect(shortSubmit.phase, PracticeInputPhase.invalid);

      final valid = PracticeWordValidator.validateLive('River', needLetter: 'r');
      expect(valid.phase, PracticeInputPhase.valid);
      expect(valid.normalizedWord, 'river');

      final duplicate = PracticeWordValidator.validateLive(
        'river',
        needLetter: 'r',
        triedWords: const {'river'},
      );
      expect(duplicate.phase, PracticeInputPhase.invalid);
    });
  });

  group('PracticeTestInput & PracticeScreen UI', () {
    testWidgets('shows soft green glow when typing a valid word starting with target letter', (tester) async {
      await tester.pumpWidget(_wrapPractice());

      await tester.enterText(find.byType(TextField), 'rainbow');
      await tester.pump(const Duration(milliseconds: 250));

      final state = tester.state<PracticeTestInputState>(find.byType(PracticeTestInput));
      expect(state.phase, PracticeInputPhase.valid);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text("Qoidaga mos — tekshirish uchun yuboring"), findsOneWidget);

      final decoration = _inputContainerDecoration(tester);
      expect(decoration, isNotNull);
      expect(decoration!.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.color, WBColors.green.withValues(alpha: .26));
    });

    testWidgets('shows soft red glow and elastic shake when typing wrong first letter', (tester) async {
      await tester.pumpWidget(_wrapPractice());

      await tester.enterText(find.byType(TextField), 'apple');
      // First frame initializes the ticker, second advances it into the elastic shake.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));

      // Elastic shake should displace horizontally mid-animation
      expect(_shakeDx(tester).abs(), greaterThan(0.5));

      await tester.pumpAndSettle();
      expect(_shakeDx(tester), closeTo(0.0, 0.01));

      final state = tester.state<PracticeTestInputState>(find.byType(PracticeTestInput));
      expect(state.phase, PracticeInputPhase.invalid);
      expect(find.text('«R» harfi bilan boshlanishi kerak'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      final decoration = _inputContainerDecoration(tester);
      expect(decoration, isNotNull);
      expect(decoration!.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.color, WBColors.red.withValues(alpha: .28));
    });

    testWidgets('triggers elastic shake on short word submit', (tester) async {
      await tester.pumpWidget(_wrapPractice());

      await tester.enterText(find.byType(TextField), 'ri');
      await tester.pump();
      expect(
        tester.state<PracticeTestInputState>(find.byType(PracticeTestInput)).phase,
        PracticeInputPhase.incomplete,
      );

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));

      expect(_shakeDx(tester).abs(), greaterThan(0.5));
      await tester.pumpAndSettle();

      expect(
        tester.state<PracticeTestInputState>(find.byType(PracticeTestInput)).phase,
        PracticeInputPhase.invalid,
      );
      expect(find.text('Kamida 3 ta harf yozing'), findsOneWidget);
    });

    testWidgets('submitting valid word clears box, records chip, and rejects duplicates', (tester) async {
      await tester.pumpWidget(_wrapPractice());

      await tester.enterText(find.byType(TextField), 'rainbow');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(find.text("SINALGAN SO'ZLAR"), findsOneWidget);
      expect(find.text('rainbow'), findsOneWidget);
      expect(find.text("«rainbow» to'g'ri so'z! (+7 harf)"), findsOneWidget);

      // Trying the same word again is rejected with red validation & shake
      await tester.enterText(find.byType(TextField), 'rainbow');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      expect(_shakeDx(tester).abs(), greaterThan(0.5));
      await tester.pumpAndSettle();

      expect(find.text("Bu so'z allaqachon sinab ko'rildi"), findsOneWidget);

      // Advance past the status timer so no pending timers remain
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('auto-transliterates Cyrillic input into Latin for real-time check', (tester) async {
      await tester.pumpWidget(_wrapPractice());

      await tester.enterText(find.byType(TextField), 'ривер');
      await tester.pump();

      expect(find.text('river', findRichText: true), findsNWidgets(2)); // one in TextField, one in hints wrap
      expect(
        tester.state<PracticeTestInputState>(find.byType(PracticeTestInput)).phase,
        PracticeInputPhase.valid,
      );

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('supports async dictionary validation callback rejection and acceptance', (tester) async {
      await tester.pumpWidget(
        _wrapPractice(
          onCheckWord: (word) async {
            if (word == 'rzzzz') {
              return const PracticeCheckDto(valid: false, reason: "Bu so'z ingliz lug'atida yo'q");
            }
            return const PracticeCheckDto(valid: true);
          },
        ),
      );

      await tester.enterText(find.byType(TextField), 'rzzzz');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump(); // flush async onCheckWord microtask
      await tester.pump(); // initialize shake ticker
      await tester.pump(const Duration(milliseconds: 35));

      expect(_shakeDx(tester).abs(), greaterThan(0.5));
      await tester.pumpAndSettle();

      expect(find.text("Bu so'z ingliz lug'atida yo'q"), findsOneWidget);
      expect(
        tester.state<PracticeTestInputState>(find.byType(PracticeTestInput)).phase,
        PracticeInputPhase.invalid,
      );

      // Now enter a valid word and verify acceptance
      await tester.enterText(find.byType(TextField), 'rain');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(find.text('rain'), findsOneWidget);
      expect(find.text("SINALGAN SO'ZLAR"), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('tapping a hint chip fills the input field cleanly', (tester) async {
      await tester.pumpWidget(_wrapPractice());

      await tester.tap(find.text('rocket', findRichText: true));
      await tester.pump();

      expect(
        tester.state<PracticeTestInputState>(find.byType(PracticeTestInput)).phase,
        PracticeInputPhase.valid,
      );
      expect(find.text("Qoidaga mos — tekshirish uchun yuboring"), findsOneWidget);
    });

    testWidgets('displays OXIRGI HARF badge, live length pill, and Tozalash clear action', (tester) async {
      await tester.pumpWidget(_wrapPractice());

      expect(find.text('OXIRGI HARF: R'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'rocket');
      await tester.pump();
      expect(find.text('6'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(find.text('1 · +6 harf'), findsOneWidget);
      expect(find.text('Tozalash'), findsOneWidget);

      await tester.tap(find.text('Tozalash'));
      await tester.pumpAndSettle();

      expect(find.text("SINALGAN SO'ZLAR"), findsNothing);
      expect(find.text('Tozalash'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
