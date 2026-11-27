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

  group('WordShareStyle & WordShareService caption formatting', () {
    test('exposes distinct theme metadata across all share card styles', () {
      expect(WordShareStyle.values.map((s) => s.label), ['Indigo', 'Oltin', 'Zumrad']);
      expect(WordShareStyle.indigoGlass.accent, isNot(WordShareStyle.amberGlow.accent));
      expect(WordShareStyle.amberGlow.accent, isNot(WordShareStyle.emeraldNight.accent));
    });

    test('builds bilingual caption with word, IPA, meaning, and challenge letter', () {
      final caption = WordShareService.buildCaption(sampleWord);

      expect(caption, contains('HARBOUR'));
      expect(caption, contains('/ˈhɑːbə/'));
      expect(caption, contains("bandargoh, port — kemalar to'xtaydigan joy"));
      expect(caption, contains('«R»'));
      expect(caption, isNot(contains('mashqda')));
    });

    test('includes practiced count line when practicedCount > 0 and omits empty IPA', () {
      const noIpa = PracticeWordDto(word: 'meadow', ipa: '', meaning: "o'tloq");
      final caption = WordShareService.buildCaption(noIpa, practicedCount: 5);

      expect(caption, contains('MEADOW'));
      expect(caption, contains("5 ta so'z topdim"));
      expect(caption, contains('«W»'));
      expect(caption, isNot(contains('  \n')));
    });
  });

  group('WordShareService PNG image export', () {
    tearDown(() {
      WordShareService.testShareHandler = null;
    });

    testWidgets('captures mounted RepaintBoundary into valid 3x PNG bytes', (tester) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: const WordShareCard(word: sampleWord, practicedCount: 3),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bytes = await tester.runAsync(
        () => WordShareService.captureBoundaryToPng(boundaryKey, pixelRatio: 2.0),
      );

      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(1000));
      // Valid PNG magic signature: 0x89 P N G
      expect(bytes.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);

      String? seenWord;
      int? seenLength;
      WordShareService.testShareHandler = (pngBytes, caption, word) async {
        seenWord = word;
        seenLength = pngBytes.length;
      };

      final shared = await tester.runAsync(
        () => WordShareService.shareWordCard(
          boundaryKey: boundaryKey,
          word: sampleWord,
          practicedCount: 3,
          pixelRatio: 2.0,
        ),
      );

      expect(shared, isTrue);
      expect(seenWord, 'harbour');
      expect(seenLength, greaterThan(1000));
    });
  });
}
