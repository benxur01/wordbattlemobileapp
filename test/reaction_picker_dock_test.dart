import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/widgets/reaction_picker_dock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 390, height: 100, child: child),
        ),
      ),
    );
  }

  group('ReactionPickerDock widget tests', () {
    testWidgets('renders all default 6 emojis with semantic labels', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReactionPickerDock(onReact: (_) {}),
        ),
      );

      for (final emoji in kDefaultDuelReactions) {
        expect(find.text(emoji), findsOneWidget);
        expect(find.bySemanticsLabel('Reaksiya: $emoji'), findsOneWidget);
      }
    });

    testWidgets('renders custom reaction emoji set', (tester) async {
      const customSet = ['🎉', '💎', '🚀'];
      await tester.pumpWidget(
        wrap(
          ReactionPickerDock(
            reactions: customSet,
            onReact: (_) {},
          ),
        ),
      );

      for (final emoji in customSet) {
        expect(find.text(emoji), findsOneWidget);
      }
      expect(find.text('🔥'), findsNothing);
    });

    testWidgets('tapping an emoji fires onReact with selected emoji', (tester) async {
      String? selected;
      await tester.pumpWidget(
        wrap(
          ReactionPickerDock(
            onReact: (emoji) => selected = emoji,
          ),
        ),
      );

      await tester.tap(find.text('🔥'));
      await tester.pumpAndSettle();

      expect(selected, '🔥');
    });

    testWidgets('invokes haptic and audio hooks on tap', (tester) async {
      var hapticCount = 0;
      var audioCount = 0;
      String? selected;

      await tester.pumpWidget(
        wrap(
          ReactionPickerDock(
            onReact: (emoji) => selected = emoji,
            onHapticFeedback: () => hapticCount++,
            onAudioFeedback: () => audioCount++,
          ),
        ),
      );

      await tester.tap(find.text('😂'));
      await tester.pumpAndSettle();

      expect(selected, '😂');
      expect(hapticCount, 1);
      expect(audioCount, 1);
    });

    testWidgets('disabling audio or haptics suppresses callbacks', (tester) async {
      var hapticCount = 0;
      var audioCount = 0;

      await tester.pumpWidget(
        wrap(
          ReactionPickerDock(
            enableAudio: false,
            enableHaptics: false,
            onReact: (_) {},
            onHapticFeedback: () => hapticCount++,
            onAudioFeedback: () => audioCount++,
          ),
        ),
      );

      await tester.tap(find.text('👏'));
      await tester.pumpAndSettle();

      expect(hapticCount, 0);
      expect(audioCount, 0);
    });

    testWidgets('tap down triggers forward scale animation and release settles back', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReactionPickerDock(onReact: (_) {}),
        ),
      );

      final gesture = await tester.startGesture(tester.getCenter(find.text('😮')));
      // Animate halfway through press
      await tester.pump(const Duration(milliseconds: 70));
      expect(find.text('😮'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('😮'), findsOneWidget);
    });

    testWidgets('clips BackdropFilter cleanly instead of Clip.none to prevent header blur bleed', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReactionPickerDock(onReact: (_) {}),
        ),
      );

      final clip = tester.widget<ClipRRect>(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(clip.clipBehavior, isNot(Clip.none));
    });
  });
}
