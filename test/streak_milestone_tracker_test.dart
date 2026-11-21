import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/widgets/flame_badge.dart';
import 'package:word_battle/widgets/streak_milestone_tracker.dart';

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

  group('StreakFlameTier unit tests', () {
    test('calculates correct flame tier from streak day count', () {
      expect(StreakFlameTier.fromDays(0), StreakFlameTier.gentle);
      expect(StreakFlameTier.fromDays(1), StreakFlameTier.gentle);
      expect(StreakFlameTier.fromDays(2), StreakFlameTier.gentle);
      expect(StreakFlameTier.fromDays(3), StreakFlameTier.vibrant);
      expect(StreakFlameTier.fromDays(5), StreakFlameTier.vibrant);
      expect(StreakFlameTier.fromDays(6), StreakFlameTier.vibrant);
      expect(StreakFlameTier.fromDays(7), StreakFlameTier.blazing);
      expect(StreakFlameTier.fromDays(14), StreakFlameTier.blazing);
      expect(StreakFlameTier.fromDays(30), StreakFlameTier.blazing);
      expect(StreakFlameTier.fromDays(100), StreakFlameTier.blazing);
    });

    test('primaryColor provides vibrant color for each tier', () {
      expect(StreakFlameTier.gentle.primaryColor, isNotNull);
      expect(StreakFlameTier.vibrant.primaryColor, isNotNull);
      expect(StreakFlameTier.blazing.primaryColor, isNotNull);

      // Colors should be distinct across tiers
      expect(
        StreakFlameTier.gentle.primaryColor != StreakFlameTier.vibrant.primaryColor,
        isTrue,
      );
      expect(
        StreakFlameTier.vibrant.primaryColor != StreakFlameTier.blazing.primaryColor,
        isTrue,
      );
    });
  });

  group('LiveStreakFlame and FlameIcon tests', () {
    testWidgets('LiveStreakFlame renders with animate: false without errors', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Row(
            children: [
              LiveStreakFlame(size: 24, tier: StreakFlameTier.gentle, animate: false),
              LiveStreakFlame(size: 40, tier: StreakFlameTier.vibrant, animate: false),
              LiveStreakFlame(size: 64, tier: StreakFlameTier.blazing, animate: false),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LiveStreakFlame), findsNWidgets(3));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('FlameIcon delegates to LiveStreakFlame when width >= 12', (tester) async {
      await tester.pumpWidget(
        wrap(
          const FlameIcon(
            width: 14,
            height: 18,
            animate: false,
            tier: StreakFlameTier.blazing,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LiveStreakFlame), findsOneWidget);
    });

    testWidgets('FlameIcon uses classic compact container when width < 12', (tester) async {
      await tester.pumpWidget(
        wrap(
          const FlameIcon(
            width: 8,
            height: 11,
            animate: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LiveStreakFlame), findsNothing);
      expect(find.byType(FlameIcon), findsOneWidget);
    });
  });

  group('StreakMilestoneTracker widget tests', () {
    testWidgets('renders zero streak state correctly', (tester) async {
      await tester.pumpWidget(
        wrap(
          const StreakMilestoneTracker(
            streakDays: 0,
            hasFreeze: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('0'), findsOneWidget);
      expect(find.text('KUNLIK SERIYA'), findsOneWidget);
      expect(find.text('0 / 7 kun'), findsOneWidget);
      expect(find.text('YANGI SERIYA'), findsOneWidget);
      expect(
        find.text("Bugun 1 ta o'yinda g'alaba qozoning va birinchi seriyangizni yoqing!"),
        findsOneWidget,
      );
      expect(find.text('Yana 7 kunlik seriya kerak'), findsOneWidget);
      expect(find.text('YO‘Q'), findsOneWidget);
    });

    testWidgets('renders active 4-day streak state with progress', (tester) async {
      await tester.pumpWidget(
        wrap(
          const StreakMilestoneTracker(
            streakDays: 4,
            hasFreeze: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('4'), findsOneWidget);
      expect(find.text('KUNLIK SERIYA'), findsOneWidget);
      expect(find.text('4 / 7 kun'), findsOneWidget);
      expect(find.text('QIZG‘IN SERIYA'), findsOneWidget);
      expect(
        find.text('Olov alangalamoqda! 7 kunlik marraga oz qoldi!'),
        findsOneWidget,
      );
      expect(find.text('Yana 3 kunlik seriya kerak'), findsOneWidget);
      expect(find.text('FAOL'), findsOneWidget);
    });

    testWidgets('displays claim button and triggers onClaim when 7-day milestone is hit', (tester) async {
      var claimed = false;

      await tester.pumpWidget(
        wrap(
          StreakMilestoneTracker(
            streakDays: 7,
            hasFreeze: false,
            onClaim: () {
              claimed = true;
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('7'), findsOneWidget);
      expect(find.text('7 / 7 kun'), findsOneWidget);
      expect(find.text('ALANGALI SERIYA'), findsOneWidget);
      expect(find.text('MUKOFOTNI OLISH'), findsOneWidget);

      await tester.ensureVisible(find.text('MUKOFOTNI OLISH'));
      await tester.tap(find.text('MUKOFOTNI OLISH'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(claimed, isTrue);
      expect(find.text('Mukofot qabul qilindi'), findsOneWidget);
    });

    testWidgets('StreakMilestoneTracker.show opens frosted glass modal bottom sheet', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => StreakMilestoneTracker.show(
                    context,
                    streakDays: 5,
                    hasFreeze: true,
                  ),
                  child: const Text('Open Tracker'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Tracker'));
      await tester.pump(); // Build modal sheet at t=0
      await tester.pump(const Duration(milliseconds: 400)); // Complete entrance slide animation

      expect(find.byType(StreakMilestoneTracker), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('5 / 7 kun'), findsOneWidget);
      expect(find.text('FAOL'), findsOneWidget);

      // Dismiss with Tushunarli button
      await tester.ensureVisible(find.text('TUSHUNARLI'));
      await tester.tap(find.text('TUSHUNARLI'));
      await tester.pump(); // Start pop exit transition
      await tester.pump(const Duration(milliseconds: 400)); // Finish pop
      await tester.pump(); // Settle removal from tree

      expect(find.byType(StreakMilestoneTracker), findsNothing);
    });
  });
}
