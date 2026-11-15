import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/screens/friends_screen.dart';
import 'package:word_battle/screens/profile_screen.dart';
import 'package:word_battle/widgets/friends_skeleton.dart';
import 'package:word_battle/widgets/profile_skeleton.dart';
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

  group('BadgesGridSkeleton widget tests', () {
    testWidgets('renders default 4 badge placeholders', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ShimmerScope(
            child: BadgesGridSkeleton(),
          ),
        ),
      );

      expect(find.byType(BadgesGridSkeleton), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      // Each badge has 2 ShimmerBox widgets (mark + label) -> 8 total
      expect(find.byType(ShimmerBox), findsNWidgets(8));
    });

    testWidgets('renders custom count of badge placeholders', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ShimmerScope(
            child: BadgesGridSkeleton(itemCount: 8),
          ),
        ),
      );

      expect(find.byType(ShimmerBox), findsNWidgets(16));
    });
  });

  group('ProfileSkeletonLoader widget tests', () {
    testWidgets('renders full profile skeleton layout', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ProfileSkeletonLoader(),
        ),
      );

      expect(find.byType(ProfileSkeletonLoader), findsOneWidget);
      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(find.byType(BadgesGridSkeleton), findsOneWidget);
      expect(find.byType(ShimmerBox), findsWidgets);

      // Verify smooth animation ticking
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ProfileSkeletonLoader), findsOneWidget);
    });

    testWidgets('ProfileScreen renders ProfileSkeletonLoader while profile is null', (tester) async {
      await tester.pumpWidget(
        wrap(
          ProfileScreen(
            profile: null,
            onHome: () {},
            onFriends: () {},
            onBoard: () {},
            friendRequestCount: 0,
            onHistory: () {},
            onBlockedUsers: () {},
            onPrivacyPolicy: () {},
            onTerms: () {},
            onLogout: () {},
            onDeleteAccount: () {},
          ),
        ),
      );

      expect(find.byType(ProfileSkeletonLoader), findsOneWidget);
      expect(find.byType(ShimmerScope), findsOneWidget);
      expect(find.byType(BadgesGridSkeleton), findsOneWidget);
    });
  });

  group('FriendsSkeletonLoader widget tests', () {
    testWidgets('renders default 5 rows of friend skeletons', (tester) async {
      await tester.pumpWidget(
        wrap(
          const FriendsSkeletonLoader(),
        ),
      );

      expect(find.byType(FriendsSkeletonLoader), findsOneWidget);
      expect(find.byType(ShimmerScope), findsOneWidget);
      // 5 items * 4 ShimmerBox per row (avatar, name, status, button) = 20 ShimmerBox
      expect(find.byType(ShimmerBox), findsNWidgets(20));
    });

    testWidgets('FriendsSkeletonLoader.search renders 2 rows', (tester) async {
      await tester.pumpWidget(
        wrap(
          const FriendsSkeletonLoader.search(),
        ),
      );

      expect(find.byType(FriendsSkeletonLoader), findsOneWidget);
      // 2 items * 4 ShimmerBox per row = 8 ShimmerBox
      expect(find.byType(ShimmerBox), findsNWidgets(8));
    });

    testWidgets('FriendsScreen renders search skeleton when searchLoading is true', (tester) async {
      await tester.pumpWidget(
        wrap(
          FriendsScreen(
            search: 'Ali',
            searchResults: const [],
            searchLoading: true,
            isRequestSent: (_) => false,
            requests: const [],
            friends: const [],
            onSearchChanged: (_) {},
            onSendRequest: (_) {},
            onAccept: (_) {},
            onDecline: (_) {},
            onChallenge: (_) {},
            onSpectate: (_) {},
            onTeamInvite: (_) {},
            onPlayerActions: (_) {},
            onHome: () {},
            onBoard: () {},
            onProfile: () {},
            onOrganizeTournament: () {},
          ),
        ),
      );

      expect(find.byType(FriendsSkeletonLoader), findsOneWidget);
      expect(find.text('QIDIRUV NATIJASI'), findsOneWidget);
    });

    testWidgets('FriendsScreen renders friends skeleton when friendsLoading is true', (tester) async {
      await tester.pumpWidget(
        wrap(
          FriendsScreen(
            search: '',
            searchResults: const [],
            searchLoading: false,
            friendsLoading: true,
            isRequestSent: (_) => false,
            requests: const [],
            friends: const [],
            onSearchChanged: (_) {},
            onSendRequest: (_) {},
            onAccept: (_) {},
            onDecline: (_) {},
            onChallenge: (_) {},
            onSpectate: (_) {},
            onTeamInvite: (_) {},
            onPlayerActions: (_) {},
            onHome: () {},
            onBoard: () {},
            onProfile: () {},
            onOrganizeTournament: () {},
          ),
        ),
      );

      expect(find.byType(FriendsSkeletonLoader), findsOneWidget);
    });
  });
}
