import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/screens/bot_battle_screen.dart';
import 'package:word_battle/widgets/bot_difficulty_card.dart';

void main() {
  group('BotDifficultyTier unit tests', () {
    test('correct default ratings for all tiers', () {
      expect(BotDifficultyTier.novice.defaultRating, 600);
      expect(BotDifficultyTier.tactician.defaultRating, 1200);
      expect(BotDifficultyTier.master.defaultRating, 1800);
    });

    test('correct labels and descriptions', () {
      expect(BotDifficultyTier.novice.label, 'Boshlovchi');
      expect(BotDifficultyTier.tactician.label, 'Taktik');
      expect(BotDifficultyTier.master.label, 'Usta');

      expect(BotDifficultyTier.novice.englishLabel, 'Novice');
      expect(BotDifficultyTier.tactician.englishLabel, 'Tactician');
      expect(BotDifficultyTier.master.englishLabel, 'Master');

      expect(BotDifficultyTier.novice.subtitle, contains('Oddiy'));
      expect(BotDifficultyTier.tactician.subtitle, contains('chaqqon'));
      expect(BotDifficultyTier.master.subtitle, contains('kamyob'));
    });

    test('fromRating classifies boundaries accurately', () {
      expect(BotDifficultyTier.fromRating(200), BotDifficultyTier.novice);
      expect(BotDifficultyTier.fromRating(600), BotDifficultyTier.novice);
      expect(BotDifficultyTier.fromRating(899), BotDifficultyTier.novice);

      expect(BotDifficultyTier.fromRating(900), BotDifficultyTier.tactician);
      expect(BotDifficultyTier.fromRating(1200), BotDifficultyTier.tactician);
      expect(BotDifficultyTier.fromRating(1499), BotDifficultyTier.tactician);

      expect(BotDifficultyTier.fromRating(1500), BotDifficultyTier.master);
      expect(BotDifficultyTier.fromRating(1800), BotDifficultyTier.master);
      expect(BotDifficultyTier.fromRating(2000), BotDifficultyTier.master);
    });
  });

  group('BotDifficultyCard widget tests', () {
    testWidgets('renders tier title, default rating badge, and icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                BotDifficultyCard(
                  tier: BotDifficultyTier.novice,
                  isSelected: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Boshlovchi'), findsOneWidget);
      expect(find.text('600'), findsOneWidget);
      expect(find.byIcon(Icons.eco_rounded), findsOneWidget);
    });

    testWidgets('tapping BotDifficultyCard triggers onTap callback', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                BotDifficultyCard(
                  tier: BotDifficultyTier.tactician,
                  isSelected: false,
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Taktik'));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  group('BotBattleScreen tiered difficulty integration tests', () {
    testWidgets('renders all 3 tier cards and activates correct tier based on rating', (tester) async {
      int? changedRating;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BotBattleScreen(
              rating: 1200,
              myRating: 1100,
              themes: const [
                WordThemeDto(id: 't1', name: 'IT & Texnologiya'),
              ],
              theme: null,
              onRatingChanged: (r) => changedRating = r,
              onThemeChanged: (_) {},
              onStart: () {},
              onBack: () {},
            ),
          ),
        ),
      );

      expect(find.text('Boshlovchi'), findsOneWidget);
      expect(find.text('Taktik'), findsOneWidget);
      expect(find.text('Usta'), findsOneWidget);

      expect(find.text('1200'), findsNWidgets(2)); // Card badge + Rating display
      expect(find.text('sizniki: 1100 · jang reytingsiz'), findsOneWidget);

      // Tap Novice card
      await tester.tap(find.text('Boshlovchi'));
      await tester.pump();
      expect(changedRating, 600);

      // Tap Master card
      await tester.tap(find.text('Usta'));
      await tester.pump();
      expect(changedRating, 1800);
    });

    testWidgets('calls onStart and onBack callbacks correctly', (tester) async {
      var started = false;
      var backed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BotBattleScreen(
              rating: 600,
              myRating: null,
              themes: const [],
              theme: null,
              onRatingChanged: (_) {},
              onThemeChanged: (_) {},
              onStart: () => started = true,
              onBack: () => backed = true,
            ),
          ),
        ),
      );

      // Tap start button
      await tester.tap(find.text('Jangni boshlash'));
      await tester.pump();
      expect(started, isTrue);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pump();
      expect(backed, isTrue);
    });
  });
}
