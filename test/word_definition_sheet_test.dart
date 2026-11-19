import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/duel_models.dart';
import 'package:word_battle/utils/word_definition_service.dart';
import 'package:word_battle/widgets/chain_bubble.dart';
import 'package:word_battle/widgets/post_match_words_sheet.dart';
import 'package:word_battle/widgets/word_definition_sheet.dart';

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

  group('WordDefinitionService unit tests', () {
    test('retrieves curated definition for standard dictionary words', () {
      final def = WordDefinitionService.getDefinition('KITOB');
      expect(def.word, 'KITOB');
      expect(def.partOfSpeech, 'Ot');
      expect(def.meaning, contains('Muqovalangan'));
      expect(def.syllables, 'ki · tob');
      expect(def.ipa, isNotNull);
    });

    test('normalizes lowercase and Cyrillic inputs to uppercase Latin', () {
      final defLatin = WordDefinitionService.getDefinition('anor');
      expect(defLatin.word, 'ANOR');
      expect(defLatin.partOfSpeech, 'Ot');

      final defCyrillic = WordDefinitionService.getDefinition('китоб');
      expect(defCyrillic.word, 'KITOB');
      expect(defCyrillic.meaning, contains('Muqovalangan'));
    });

    test('generates dynamic analysis definition for novel words', () {
      final defVerb = WordDefinitionService.getDefinition('YUGURMOQ');
      expect(defVerb.word, 'YUGURMOQ');
      expect(defVerb.partOfSpeech, "Fe'l");
      expect(defVerb.meaning, isNotEmpty);
      expect(defVerb.syllables, isNotEmpty);

      final defAdj = WordDefinitionService.getDefinition('QUVONCHLI');
      expect(defAdj.word, 'QUVONCHLI');
      expect(defAdj.partOfSpeech, 'Sifat');
    });

    test('computeSyllables breaks syllables based on vowels', () {
      expect(WordDefinition.computeSyllables('maktab'), 'mak · tab');
      expect(WordDefinition.computeSyllables('suv'), 'suv');
    });

    test('guessPartOfSpeech classifies words by affixes', () {
      expect(WordDefinition.guessPartOfSpeech('ishlamoq'), "Fe'l");
      expect(WordDefinition.guessPartOfSpeech('chiroyli'), 'Sifat');
      expect(WordDefinition.guessPartOfSpeech('tezkor'), 'Sifat');
      expect(WordDefinition.guessPartOfSpeech('do\'stona'), 'Ot');
    });
  });

  group('WordDefinitionSheet widget tests', () {
    testWidgets('renders word, syllables, part of speech, meaning and example', (tester) async {
      await tester.pumpWidget(
        wrap(
          const WordDefinitionSheet(
            word: 'KITOB',
            meaning: "Muqovalangan kitob ma'nosi.",
            partOfSpeech: 'Ot',
            example: 'Kitob mutolaa qilindi.',
            syllables: 'ki · tob',
            ipa: '[kʲɪˈtob]',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text("SO'Z IZOHI"), findsOneWidget);
      expect(find.text('KITOB'), findsOneWidget);
      expect(find.text('ki · tob'), findsOneWidget);
      expect(find.text('Ot'), findsOneWidget);
      expect(find.text('5 harf'), findsOneWidget);
      expect(find.text('[kʲɪˈtob]'), findsOneWidget);
      expect(find.text("Muqovalangan kitob ma'nosi."), findsOneWidget);
      expect(find.text('Kitob mutolaa qilindi.'), findsOneWidget);
      expect(find.text('Tushunarli'), findsOneWidget);
    });

    testWidgets('copies word to clipboard when copy button is tapped', (tester) async {
      final List<MethodCall> log = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          log.add(methodCall);
          if (methodCall.method == 'Clipboard.setData') {
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        wrap(
          const WordDefinitionSheet(
            word: 'ZAFAR',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Nusxa'), findsOneWidget);

      await tester.tap(find.text('Nusxa'));
      await tester.pump();

      expect(find.text('Nusxa olindi'), findsOneWidget);
      expect(log.any((call) => call.method == 'Clipboard.setData'), isTrue);

      // Drain copy timer
      await tester.pump(const Duration(milliseconds: 1700));
    });

    testWidgets('pops sheet when Tushunarli button is tapped', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => WordDefinitionSheet.show(context, word: 'VATAN'),
                child: const Text('Open'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(WordDefinitionSheet), findsOneWidget);
      expect(find.text('VATAN'), findsOneWidget);

      await tester.ensureVisible(find.text('Tushunarli'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tushunarli'));
      await tester.pumpAndSettle();

      expect(find.byType(WordDefinitionSheet), findsNothing);
    });

    testWidgets('pops sheet when close X button is tapped', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => WordDefinitionSheet.show(context, word: 'VATAN'),
                child: const Text('Open'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(WordDefinitionSheet), findsOneWidget);

      await tester.tap(find.text('✕'));
      await tester.pumpAndSettle();

      expect(find.byType(WordDefinitionSheet), findsNothing);
    });
  });

  group('ChainBubble and PostMatchWordsSheet integration tests', () {
    testWidgets('Tapping ChainBubble opens WordDefinitionSheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChainBubble(
                word: 'BILIM',
                isMe: true,
                ms: '2.1s',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ChainBubble), findsOneWidget);

      await tester.tap(find.byType(RichText).first);
      await tester.pumpAndSettle();

      expect(find.byType(WordDefinitionSheet), findsOneWidget);
      expect(find.text('BILIM'), findsOneWidget);
    });

    testWidgets('Tapping word in PostMatchWordsSheet opens WordDefinitionSheet', (tester) async {
      final words = [
        const ChainWord(word: 'GUL', mine: true, spentMs: 1500),
        const ChainWord(word: 'LOLA', mine: false, spentMs: 2500),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => PostMatchWordsSheet.show(context, words: words),
                  child: const Text('Open Words'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Words'));
      await tester.pumpAndSettle();

      expect(find.byType(PostMatchWordsSheet), findsOneWidget);
      expect(find.text('GUL'), findsOneWidget);

      await tester.tap(find.text('GUL'));
      await tester.pumpAndSettle();

      expect(find.byType(WordDefinitionSheet), findsOneWidget);
      expect(find.text('GUL'), findsWidgets);
    });
  });
}
