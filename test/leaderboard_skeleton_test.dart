import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/screens/board_screen.dart';
import 'package:word_battle/widgets/leaderboard_skeleton.dart';
import 'package:word_battle/widgets/shimmer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 390, height: 844, child: child),
        ),
      ),
    );
  }

  group('Shimmer and ShimmerBox widget tests', () {
    testWidgets('renders ShimmerBox inside ShimmerScope', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ShimmerScope(
            child: Column(
              children: [
                ShimmerBox(width: 100, height: 20),
                SizedBox(height: 10),
                ShimmerBox(width: 150, height: 30),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(find.byType(ShimmerBox), findsNWidgets(2));

      // Advance animation slightly to verify smooth continuous ticking
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ShimmerBox), findsNWidgets(2));
    });

    testWidgets('renders standalone ShimmerBox with fallback controller', (tester) async {
      await tester.pumpWidget(
        wrap(
          ShimmerBox.circle(size: 40),
        ),
      );

      expect(find.byType(ShimmerBox), findsOneWidget);
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.shape, BoxShape.circle);
    });
  });

  group('LeaderboardSkeletonLoader widget tests', () {
    testWidgets('renders default 6 skeleton rows', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LeaderboardSkeletonLoader(),
        ),
      );

      expect(find.byType(LeaderboardSkeletonLoader), findsOneWidget);
      expect(find.byType(ShimmerScope), findsOneWidget);

      // In each row: rank, avatar, name, city, rating = 5 ShimmerBoxes * 6 rows = 30 ShimmerBoxes
      expect(find.byType(ShimmerBox), findsNWidgets(30));
    });

    testWidgets('supports custom row count', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LeaderboardSkeletonLoader(itemCount: 3),
        ),
      );

      // 5 ShimmerBoxes * 3 rows = 15 ShimmerBoxes
      expect(find.byType(ShimmerBox), findsNWidgets(15));
    });
  });

  group('BoardScreen shimmer skeleton integration tests', () {
    testWidgets('shows LeaderboardSkeletonLoader while board is null (loading)', (tester) async {
      await tester.pumpWidget(
        wrap(
          BoardScreen(
            board: null,
            tabGlobal: true,
            onGlobalTab: () {},
            onClassTab: () {},
            onHome: () {},
            onFriends: () {},
            onProfile: () {},
            friendRequestCount: 0,
          ),
        ),
      );

      expect(find.byType(LeaderboardSkeletonLoader), findsOneWidget);
      expect(find.text('Liderlar taxtasi'), findsOneWidget);
    });

    testWidgets('hides skeleton and renders actual rows when board arrives', (tester) async {
      const mockUser = UserDto(
        id: 1,
        nickname: 'SuperPlayer',
        displayName: 'SuperPlayer',
        initial: 'S',
        city: 'Toshkent',
        rating: 1450,
        streakDays: 5,
      );
      const mockRow = LeaderboardRow(
        rank: 1,
        user: mockUser,
        self: false,
      );
      const mockBoard = LeaderboardDto(rows: [mockRow]);

      await tester.pumpWidget(
        wrap(
          BoardScreen(
            board: mockBoard,
            tabGlobal: true,
            onGlobalTab: () {},
            onClassTab: () {},
            onHome: () {},
            onFriends: () {},
            onProfile: () {},
            friendRequestCount: 0,
          ),
        ),
      );

      expect(find.byType(LeaderboardSkeletonLoader), findsNothing);
      expect(find.text('SuperPlayer'), findsOneWidget);
      expect(find.text('1450'), findsOneWidget);
    });
  });
}
