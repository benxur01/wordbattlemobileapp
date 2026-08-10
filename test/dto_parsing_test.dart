import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/models.dart';

/// The screens that never stopped loading.
///
/// `DateTime.parse` throws on anything it does not recognise, and the loaders
/// behind the profile, the history and the friends list catch `ApiException`
/// and nothing else. A date whose shape the server changed — the ordinary cost
/// of a rolling deploy, where two versions answer for as long as it takes to
/// roll — therefore left the `try` as a `FormatException`, matched no clause,
/// and escaped an `unawaited` future with nobody behind it to notice. The
/// screen kept its spinner: no banner, no retry, and no way off it but leaving
/// and coming back to the same failure.
///
/// Two things changed. The loaders grew the generic `catch` that `_bootstrap`
/// has always had, so a body that will not parse becomes a line on the screen
/// rather than a hang; and the dates below stopped throwing at all, because a
/// date is a label — one row saying "bugun" when it means last Tuesday is a far
/// smaller lie than a history screen that never arrives.
void main() {
  Map<String, dynamic> user() => {
        'id': 42,
        'nickname': 'aziz',
        'displayName': 'Aziz',
        'initial': 'A',
        'city': 'Toshkent',
        'rating': 1310,
        'streakDays': 4,
      };

  group('a point on the rating chart', () {
    test('a date the server sends properly is read exactly', () {
      final point = RatingPoint.fromJson({'at': '2026-08-09T12:30:00Z', 'rating': 1310});

      expect(point.at.toUtc(), DateTime.utc(2026, 8, 9, 12, 30));
      expect(point.rating, 1310);
    });

    test('a date it cannot read costs the point its label, not the screen', () {
      // Only the first and last points of the chart are ever labelled with a
      // day; the line itself is drawn from the ratings. So the rating is the
      // part worth keeping, and it is kept.
      final point = RatingPoint.fromJson({'at': '09.08.2026', 'rating': 1310});

      expect(point.rating, 1310);
      expect(point.at, isNotNull);
    });

    test('a point with no date at all still parses', () {
      expect(RatingPoint.fromJson({'rating': 1288}).rating, 1288);
    });

    test('a whole profile survives one bad point in its history', () {
      // The failure as it reached the player: one row of a rating history the
      // server had already sent and the app had already received, and the
      // entire profile screen sat on its spinner for it.
      final profile = ProfileDto.fromJson({
        'user': user(),
        'globalRank': 12,
        'battles': 40,
        'ratingHistory': [
          {'at': '2026-08-08T12:00:00Z', 'rating': 1300},
          {'at': 'not a date', 'rating': 1310},
        ],
      });

      expect(profile.ratingHistory, hasLength(2));
      expect(profile.ratingHistory.last.rating, 1310);
      expect(profile.globalRank, 12);
    });
  });

  group('a battle in the history list', () {
    Map<String, dynamic> match() => {
          'id': 7,
          'opponent': user(),
          'won': true,
          'rated': true,
          'delta': 18,
          'ratingAfter': 1328,
          'chainLength': 14,
          'endReason': 'timeout',
          'finishedAt': '2026-08-09T18:04:00Z',
        };

    test('a date the server sends properly is read exactly', () {
      expect(MatchSummaryDto.fromJson(match()).finishedAt.toUtc(), DateTime.utc(2026, 8, 9, 18, 4));
    });

    test('a date it cannot read leaves the rest of the row intact', () {
      final summary = MatchSummaryDto.fromJson(match()..['finishedAt'] = '2026-08-09 18:04 +05');

      expect(summary.id, 7);
      expect(summary.won, isTrue);
      expect(summary.delta, 18);
      expect(summary.chainLength, 14);
      expect(summary.opponent.label, 'aziz');
    });

    test('a missing date does not take the history down with it', () {
      expect(MatchSummaryDto.fromJson(match()..remove('finishedAt')).id, 7);
    });
  });

  group('a friend in the list', () {
    test('a last-seen the server sends properly is read exactly', () {
      final friend = FriendDto.fromJson({
        'user': user(),
        'online': false,
        'lastSeenAt': '2026-08-09T18:04:00Z',
      });

      expect(friend.lastSeenAt?.toUtc(), DateTime.utc(2026, 8, 9, 18, 4));
    });

    test('a last-seen it cannot read is treated as one that was not sent', () {
      // This field already had an answer for absence, and it is the right one
      // here too: the friend is simply shown as offline.
      final friend = FriendDto.fromJson({
        'user': user(),
        'online': false,
        'lastSeenAt': 'yesterday',
      });

      expect(friend.lastSeenAt, isNull);
      expect(friend.status, 'oflayn');
    });

    test('an online friend is unaffected either way', () {
      final friend = FriendDto.fromJson({'user': user(), 'online': true, 'lastSeenAt': 'yesterday'});

      expect(friend.status, 'onlayn · jangga tayyor');
    });
  });
}
