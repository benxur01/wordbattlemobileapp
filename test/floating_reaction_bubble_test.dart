import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/audio/sound_effects.dart';
import 'package:word_battle/widgets/floating_reaction_bubble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 390, height: 400, child: child),
        ),
      ),
    );
  }

  group('FloatingReactionBubble widget tests', () {
    testWidgets('renders emoji text properly inside bubble', (tester) async {
      await tester.pumpWidget(
        wrap(
          const FloatingReactionBubble(
            emoji: '🔥',
          ),
        ),
      );

      expect(find.text('🔥'), findsOneWidget);
      expect(find.byType(FloatingReactionBubble), findsOneWidget);
    });

    testWidgets('renders sender label when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          const FloatingReactionBubble(
            emoji: '👏',
            sender: 'Jasur',
          ),
        ),
      );

      expect(find.text('👏'), findsOneWidget);
      expect(find.text('Jasur'), findsOneWidget);
    });

    testWidgets('omits sender pill when sender is null', (tester) async {
      await tester.pumpWidget(
        wrap(
          const FloatingReactionBubble(
            emoji: '😮',
            sender: null,
          ),
        ),
      );

      expect(find.text('😮'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget); // Only the emoji Text widget
    });

    testWidgets('invokes onComplete after duration completes', (tester) async {
      var completed = false;

      await tester.pumpWidget(
        wrap(
          FloatingReactionBubble(
            emoji: '😂',
            duration: const Duration(milliseconds: 600),
            onComplete: () => completed = true,
          ),
        ),
      );

      expect(completed, isFalse);

      // Advance halfway
      await tester.pump(const Duration(milliseconds: 300));
      expect(completed, isFalse);

      // Finish duration
      await tester.pump(const Duration(milliseconds: 350));
      expect(completed, isTrue);
    });

    testWidgets('plays audio chime on appearance when enableSound is true', (tester) async {
      SoundEffect? played;
      SoundEffects.instance.testPlaybackHandler = (effect, _) async {
        played = effect;
      };

      await tester.pumpWidget(
        wrap(
          const FloatingReactionBubble(
            emoji: '🤝',
            enableSound: true,
          ),
        ),
      );

      expect(played, SoundEffect.tap);

      // Cleanup mock handler
      SoundEffects.instance.testPlaybackHandler = null;
    });

    testWidgets('renders with custom size without layout overflow', (tester) async {
      await tester.pumpWidget(
        wrap(
          const FloatingReactionBubble(
            emoji: '😢',
            size: 72.0,
            sender: 'TeamPartner',
          ),
        ),
      );

      expect(find.text('😢'), findsOneWidget);
      expect(find.text('TeamPartner'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  });
}
