import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/audio/sound_effects.dart';
import 'package:word_battle/widgets/confetti_cannon.dart';
import 'package:word_battle/widgets/milestone_reward_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child, {Size size = const Size(400, 800)}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    );
  }

  group('SunburstGlow tests', () {
    testWidgets('renders static sunburst glow when animate is false', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SunburstGlow(
            size: 260,
            rayCount: 16,
            color: Colors.amber,
            animate: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SunburstGlow), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders animated sunburst glow with active controller', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SunburstGlow(
            size: 260,
            animate: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SunburstGlow), findsOneWidget);
    });
  });

  group('ConfettiCannon tests', () {
    testWidgets('renders confetti cannon and paints particles without crash', (tester) async {
      final key = GlobalKey<ConfettiCannonState>();

      await tester.pumpWidget(
        wrap(
          ConfettiCannon(
            key: key,
            particleCount: 40,
            animate: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ConfettiCannon), findsOneWidget);
      expect(key.currentState, isNotNull);

      // Trigger blast manually
      key.currentState!.blast();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ConfettiCannon), findsOneWidget);
    });
  });

  group('MilestoneRewardDialog widget tests', () {
    testWidgets('renders default 7-day milestone celebration dialog content', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MilestoneRewardDialog(
            milestoneDays: 7,
            animate: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('7 KUNLIK CHEMPION!'), findsOneWidget);
      expect(
        find.text('Ajoyib mahorat! 7 kun ketma-ket g‘alaba qozonib, haftalik marrani zabt etdingiz!'),
        findsOneWidget,
      );
      expect(find.text('+50 Reyting Balli'), findsOneWidget);
      expect(find.text('Olovli Profil Ramkasi'), findsOneWidget);
      expect(find.text('1x Streak Himoyasi'), findsOneWidget);
      expect(find.text('QABUL QILISH'), findsOneWidget);
    });

    testWidgets('renders custom milestone title and subtitle', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MilestoneRewardDialog(
            milestoneDays: 14,
            title: '14 KUNLIK OLTIN SERIYA!',
            subtitle: 'Ikki haftalik chempionlik sovrini!',
            animate: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('14 KUNLIK OLTIN SERIYA!'), findsOneWidget);
      expect(find.text('Ikki haftalik chempionlik sovrini!'), findsOneWidget);
    });

    testWidgets('tapping QABUL QILISH invokes onClaim and updates status', (tester) async {
      var claimed = false;
      var closed = false;

      await tester.pumpWidget(
        wrap(
          MilestoneRewardDialog(
            milestoneDays: 7,
            animate: false,
            onClaim: () {
              claimed = true;
            },
            onClose: () {
              closed = true;
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('QABUL QILISH'), findsOneWidget);

      await tester.tap(find.text('QABUL QILISH'));
      await tester.pump();

      expect(claimed, isTrue);
      expect(find.text('MUKOFOT QABUL QILINDI!'), findsOneWidget);

      // Drain delayed auto-close timer
      await tester.pump(const Duration(milliseconds: 600));
      expect(closed, isTrue);
    });
  });

  group('MilestoneRewardDialog.show modal launch tests', () {
    testWidgets('MilestoneRewardDialog.show opens general modal dialog with victory audio', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var soundPlayed = false;
      SoundEffects.instance.testPlaybackHandler = (effect, volume) async {
        if (effect == SoundEffect.victory) {
          soundPlayed = true;
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => MilestoneRewardDialog.show(
                    context,
                    milestoneDays: 7,
                    animate: false,
                  ),
                  child: const Text('Celebrate'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Celebrate'));
      await tester.pump(); // Start dialog route build
      await tester.pump(const Duration(milliseconds: 400)); // Complete entrance transition

      expect(soundPlayed, isTrue);
      expect(find.byType(MilestoneRewardDialog), findsOneWidget);
      expect(find.text('7 KUNLIK CHEMPION!'), findsOneWidget);

      // Claim reward and allow auto-close to finish
      await tester.tap(find.text('QABUL QILISH'));
      await tester.pump();
      expect(find.text('MUKOFOT QABUL QILINDI!'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600)); // Trigger auto-close pop
      await tester.pump(const Duration(milliseconds: 400)); // Complete pop exit transition

      expect(find.byType(MilestoneRewardDialog), findsNothing);
    });
  });
}
