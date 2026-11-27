import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/theme.dart';
import 'package:word_battle/utils/hint_filter.dart';
import 'package:word_battle/widgets/hint_filter_bar.dart';

Widget _wrapFilterBar({
  String? selectedLetter = 'r',
  String? defaultLetter = 'r',
  HintLengthFilter selectedLength = HintLengthFilter.all,
  ValueChanged<String>? onLetterSelected,
  ValueChanged<HintLengthFilter>? onLengthSelected,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: WBColors.bg),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: HintFilterBar(
          selectedLetter: selectedLetter,
          defaultLetter: defaultLetter,
          selectedLength: selectedLength,
          onLetterSelected: onLetterSelected ?? (_) {},
          onLengthSelected: onLengthSelected ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  group('HintFilterBar UI & Sliding Indicator', () {
    testWidgets('slides indicator pill to selected length segment position', (tester) async {
      HintLengthFilter current = HintLengthFilter.all;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _wrapFilterBar(
            selectedLength: current,
            onLengthSelected: (next) => setState(() => current = next),
          ),
        ),
      );

      final pillFinder = find.byKey(const ValueKey('hint_length_sliding_pill'));
      expect(pillFinder, findsOneWidget);
      final initialLeft = tester.widget<AnimatedPositioned>(pillFinder).left!;
      expect(initialLeft, closeTo(0.0, 0.1));

      await tester.tap(find.text('Uzun'));
      await tester.pumpAndSettle();

      final movedLeft = tester.widget<AnimatedPositioned>(pillFinder).left!;
      expect(movedLeft, greaterThan(initialLeft + 100));
      expect(current, HintLengthFilter.long);
    });

    testWidgets('pins word-of-the-day default letter first and resets from custom letter', (tester) async {
      String currentLetter = 'r';

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _wrapFilterBar(
            selectedLetter: currentLetter,
            defaultLetter: 'r',
            onLetterSelected: (next) => setState(() => currentLetter = next),
          ),
        ),
      );

      expect(find.text('Asl harf (R)'), findsNothing);

      // Pick 'A' and verify custom letter + reset action appear
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      expect(currentLetter, 'a');
      expect(find.text('Asl harf (R)'), findsOneWidget);

      await tester.tap(find.text('Asl harf (R)'));
      await tester.pumpAndSettle();

      expect(currentLetter, 'r');
      expect(find.text('Asl harf (R)'), findsNothing);
    });

    testWidgets('renders crisp segmented controls in light theme without exceptions', (tester) async {
      WBTheme.followPlatform(Brightness.light);
      addTearDown(() => WBTheme.followPlatform(Brightness.dark));

      await tester.pumpWidget(_wrapFilterBar(selectedLength: HintLengthFilter.medium));
      await tester.pumpAndSettle();

      expect(find.text('Barchasi'), findsOneWidget);
      expect(find.text('Qisqa'), findsOneWidget);
      expect(find.text("O'rta"), findsOneWidget);
      expect(find.text('Uzun'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected pill uses solid surface in light and dark mode without indigo gradient', (tester) async {
      await tester.pumpWidget(_wrapFilterBar(selectedLetter: 'r', selectedLength: HintLengthFilter.short));
      await tester.pumpAndSettle();

      final pill = tester.widget<AnimatedPositioned>(find.byKey(const ValueKey('hint_length_sliding_pill')));
      final pillBox = (pill.child as Container).decoration! as BoxDecoration;
      expect(pillBox.gradient, isNull);
      expect(pillBox.color, WBColors.bgPressed);

      WBTheme.followPlatform(Brightness.light);
      addTearDown(() => WBTheme.followPlatform(Brightness.dark));
      await tester.pumpWidget(_wrapFilterBar(selectedLetter: 'r', selectedLength: HintLengthFilter.short));
      await tester.pumpAndSettle();

      final lightPill = tester.widget<AnimatedPositioned>(find.byKey(const ValueKey('hint_length_sliding_pill')));
      final lightBox = (lightPill.child as Container).decoration! as BoxDecoration;
      expect(lightBox.gradient, isNull);
      expect(lightBox.color, Colors.white);
    });
  });
}
