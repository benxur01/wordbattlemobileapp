import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/duel_models.dart';
import 'package:word_battle/app_root.dart';

/// The frame that could end the wrong duel.
///
/// Backing out of a battle forfeits it, and the app leaves the screen without
/// waiting for anything; the server writes the result to the database first and
/// only then says so. Long enough, in other words, for the player to have
/// queued again and been dropped into a second duel — whose socket the first
/// duel's `duel.finished` then came down. The app applied it to whatever duel
/// it was holding, so the live board vanished onto a lose screen and the new
/// opponent was left playing somebody who never answered again.
///
/// The duel id is the only thing that tells those frames apart, which is why
/// [FinishedDuel] now carries one.
void main() {
  group('duelFrameApplies', () {
    test('a frame for the duel on screen is applied', () {
      expect(duelFrameApplies('duel-2', 'duel-2'), isTrue);
    });

    test('a frame for a duel already left behind is ignored', () {
      expect(duelFrameApplies('duel-2', 'duel-1'), isFalse);
    });

    test('a result arriving with no duel on screen is still shown', () {
      // The missed-finish path: a player reconnects after their duel ended
      // while they were offline and the server hands them the result. There is
      // no live board to protect, and dropping this frame would leave them on a
      // duel screen that never moves again.
      expect(duelFrameApplies(null, 'duel-1'), isTrue);
    });

    test('a frame from a server too old to name the duel is obeyed', () {
      // Being strict here would cost a player their result rather than save
      // anyone's duel, so an unnamed frame is treated as it always was.
      expect(duelFrameApplies('duel-1', null), isTrue);
      expect(duelFrameApplies(null, null), isTrue);
    });
  });

  test('a finish frame says which duel it settled', () {
    final finished = FinishedDuel.fromJson(const {
      'duelId': 'duel-1',
      'result': 'lose',
      'reason': 'forfeit',
      'rated': true,
      'delta': -18,
      'stuckLetter': 'Y',
      'hints': ['yellow'],
    });

    expect(finished.duelId, 'duel-1');
    expect(finished.won, isFalse);
    // And a live duel started after it does not answer to that name.
    expect(duelFrameApplies('duel-2', finished.duelId), isFalse);
  });

  test('a finish frame without a duel id parses as one', () {
    expect(FinishedDuel.fromJson(const {'result': 'win'}).duelId, isNull);
  });
}
