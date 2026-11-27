import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/utils/word_share_service.dart';
import 'package:word_battle/widgets/word_share_card.dart';

void main() {
  const sampleWord = PracticeWordDto(
    word: 'harbour',
    ipa: '/ˈhɑːbə/',
    meaning: "bandargoh, port — kemalar to'xtaydigan joy",
  );

  group('WordShareCard widget', () {
    testWidgets('renders word of the day, IPA, meaning, target letter, and brand footer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: WordShareCard(word: sampleWord),
            ),
          ),
        ),
      );

      expect(find.text('WORD OF THE DAY'), findsOneWidget);
      expect(find.text('harbour'), findsOneWidget);
      expect(find.text('/ˈhɑːbə/'), findsOneWidget);
      expect(find.text("bandargoh, port — kemalar to'xtaydigan joy"), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      expect(find.text('Word Battle'), findsOneWidget);
      expect(find.text('KUNLIK MASHQ'), findsOneWidget);
      expect(find.textContaining("+"), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('displays practicedCount pill across styles without overflowing long definitions', (tester) async {
      const longWord = PracticeWordDto(
        word: 'extraordinarily',
        ipa: '/ɪkˌstrɔːdɪˈnerəli/',
        meaning:
            "favqulodda darajada, juda ham ajoyib va odatdagidan tashqari ko'rinishga ega bo'lgan hodisa yoki narsa haqida gapirilganda ishlatiladigan so'z",
      );

      for (final style in WordShareStyle.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: WordShareCard(
                  word: longWord,
                  style: style,
                  practicedCount: 7,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text("+7 so'z"), findsOneWidget);
        expect(find.text('Y'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
