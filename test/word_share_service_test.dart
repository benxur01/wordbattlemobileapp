import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/utils/word_share_service.dart';

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
}
