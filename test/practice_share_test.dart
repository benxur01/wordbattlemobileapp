import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/screens/practice_screen.dart';
import 'package:word_battle/theme.dart';
import 'package:word_battle/widgets/word_share_card.dart';
import 'package:word_battle/widgets/word_share_preview_sheet.dart';

void main() {
  const sampleWord = PracticeWordDto(
    word: 'summit',
    ipa: '/ˈsʌmɪt/',
    meaning: "cho'qqi — tog'ning eng yuqori nuqtasi",
  );

  testWidgets('PracticeScreen share button opens preview sheet with tested word count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: WBColors.bg),
        home: Scaffold(
          body: SafeArea(
            child: PracticeScreen(
              word: sampleWord,
              hints: const ['thunder'],
              onHint: () {},
              onBack: () {},
            ),
          ),
        ),
      ),
    );

    // Practice one valid word first so practicedCount becomes 1
    await tester.enterText(find.byType(TextField), 'treasure');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(find.byType(WordSharePreviewSheet), findsOneWidget);
    expect(find.byType(WordShareCard), findsOneWidget);
    expect(find.text("+1 so'z"), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('PracticeScreen disables share action while word of the day is loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: WBColors.bg),
        home: Scaffold(
          body: SafeArea(
            child: PracticeScreen(
              word: null,
              hints: const [],
              onHint: () {},
              onBack: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(find.byType(WordSharePreviewSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
