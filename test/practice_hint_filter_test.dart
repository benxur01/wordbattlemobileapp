import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/screens/practice_screen.dart';
import 'package:word_battle/theme.dart';
import 'package:word_battle/utils/hint_filter.dart';

const _practiceWord = PracticeWordDto(
  word: 'harbour',
  ipa: '/ˈhɑːbə/',
  meaning: "bandargoh, port — kemalar to'xtaydigan joy",
);

Widget _wrapScreen({
  List<String> hints = const ['red', 'rain', 'river', 'rocket', 'rainbow'],
  String? selectedHintLetter,
  HintLengthFilter selectedLengthFilter = HintLengthFilter.all,
  void Function(String letter, HintLengthFilter length)? onHintFilterChanged,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: WBColors.bg),
    home: Scaffold(
      body: SafeArea(
        child: PracticeScreen(
          word: _practiceWord,
          hints: hints,
          onHint: () {},
          onBack: () {},
          selectedHintLetter: selectedHintLetter,
          selectedLengthFilter: selectedLengthFilter,
          onHintFilterChanged: onHintFilterChanged,
        ),
      ),
    ),
  );
}

void main() {
  group('PracticeScreen Hint Filters', () {
    testWidgets('filters hint chips client-side when switching length segments', (tester) async {
      await tester.pumpWidget(_wrapScreen());

      // All 'r' words shown initially
      expect(find.text('red', findRichText: true), findsOneWidget);
      expect(find.text('river', findRichText: true), findsOneWidget);
      expect(find.text('rainbow', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Qisqa'));
      await tester.pumpAndSettle();

      expect(find.text('red', findRichText: true), findsOneWidget);
      expect(find.text('rain', findRichText: true), findsOneWidget);
      expect(find.text('river', findRichText: true), findsNothing);
      expect(find.text('rainbow', findRichText: true), findsNothing);

      await tester.tap(find.text('Uzun'));
      await tester.pumpAndSettle();

      expect(find.text('rainbow', findRichText: true), findsOneWidget);
      expect(find.text('red', findRichText: true), findsNothing);
    });

    testWidgets('shows filtered empty state and Filtrni tiklash action when no hints match', (tester) async {
      await tester.pumpWidget(_wrapScreen(hints: const ['river', 'rocket']));

      await tester.tap(find.text('Qisqa'));
      await tester.pumpAndSettle();

      expect(find.text("Ushbu filtr bo'yicha maslahat topilmadi"), findsOneWidget);
      expect(find.text('Filtrni tiklash'), findsOneWidget);

      await tester.tap(find.text('Filtrni tiklash'));
      await tester.pumpAndSettle();

      expect(find.text('river', findRichText: true), findsOneWidget);
      expect(find.text('rocket', findRichText: true), findsOneWidget);
    });

    testWidgets('forwards filter selection changes to onHintFilterChanged when wired', (tester) async {
      final changes = <(String, HintLengthFilter)>[];

      await tester.pumpWidget(
        _wrapScreen(
          selectedHintLetter: 'r',
          selectedLengthFilter: HintLengthFilter.all,
          onHintFilterChanged: (letter, length) => changes.add((letter, length)),
        ),
      );

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("O'rta"));
      await tester.pumpAndSettle();

      expect(changes, [
        ('b', HintLengthFilter.all),
        ('r', HintLengthFilter.medium),
      ]);
    });
  });
}
