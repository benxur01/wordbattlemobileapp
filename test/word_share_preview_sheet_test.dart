import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/audio/sound_effects.dart';
import 'package:word_battle/theme.dart';
import 'package:word_battle/utils/word_share_service.dart';
import 'package:word_battle/widgets/word_share_card.dart';
import 'package:word_battle/widgets/word_share_preview_sheet.dart';

void main() {
  const sampleWord = PracticeWordDto(
    word: 'lantern',
    ipa: '/ˈlæntən/',
    meaning: 'fonar — shamoldan himoyalangan chiroq',
  );

  setUp(() {
    SoundEffects.instance.testPlaybackHandler = (_, _) async {};
  });

  tearDown(() {
    WordShareService.testShareHandler = null;
    SoundEffects.instance.testPlaybackHandler = null;
    WBTheme.followPlatform(Brightness.dark);
  });

  group('WordSharePreviewSheet modal interactions', () {
    testWidgets('switches card themes, copies caption text, and dispatches PNG share', (tester) async {
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      Uint8List? sharedBytes;
      String? sharedCaption;
      String? sharedWord;
      WordShareService.testShareHandler = (bytes, caption, word) async {
        sharedBytes = bytes;
        sharedCaption = caption;
        sharedWord = word;
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: WBColors.bg),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => WordSharePreviewSheet.show(
                    context,
                    word: sampleWord,
                    practicedCount: 4,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Kartani ulashish'), findsOneWidget);
      expect(find.byType(WordShareCard), findsOneWidget);

      // Switch style to Oltin
      await tester.tap(find.text('Oltin'));
      await tester.pumpAndSettle();
      expect(tester.widget<WordShareCard>(find.byType(WordShareCard)).style, WordShareStyle.amberGlow);

      // Copy caption text
      await tester.tap(find.text('Matn'));
      await tester.pump();
      expect(find.text('Nusxalandi'), findsOneWidget);
      expect(clipboardText, contains('LANTERN'));
      expect(clipboardText, contains("4 ta so'z"));

      // Dispatch PNG image export and share
      await tester.runAsync(() async {
        await tester.tap(find.text('Rasmni ulashish'));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pumpAndSettle();

      expect(sharedBytes, isNotNull);
      expect(sharedBytes!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
      expect(sharedCaption, contains('LANTERN'));
      expect(sharedWord, 'lantern');

      // Advance past copy badge timer
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('renders cleanly in light theme on compact height without overflow', (tester) async {
      WBTheme.followPlatform(Brightness.light);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light, scaffoldBackgroundColor: WBColors.bg),
          home: const Scaffold(
            body: WordSharePreviewSheet(word: sampleWord, practicedCount: 2),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kartani ulashish'), findsOneWidget);
      expect(find.text('Zumrad'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
