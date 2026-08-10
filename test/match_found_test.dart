import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/duel_models.dart';
import 'package:word_battle/app_root.dart';

/// The frame that starts a battle, and what it cost when the app could not read
/// one.
///
/// `match.found` is the only thing that puts a player on the duel screen at the
/// start of a duel, and it used to be pulled apart with bare casts from inside
/// the very `setState` that raised that screen. A payload whose `opponent` was
/// missing or shaped differently — the ordinary cost of a rolling deploy, where
/// two server versions answer for as long as it takes to roll — threw a
/// TypeError out of the middle of that call.
///
/// Nothing caught it. The socket handler had no boundary of its own, unlike
/// every REST call in the same class, so `duel` was never assigned and the
/// screen never changed: the player watched the search radar turn while the
/// server ran down the turn timer of a duel they were already in, and their
/// opponent spent the battle playing somebody who had stopped answering. It
/// ended in a forfeit the player was never shown.
///
/// So the frame is read the way [DuelView.fromDuelUpdate] is read — the two
/// fields that cannot be defaulted are checked, and half a frame raises no
/// board at all. The handler drops what it cannot use and says so; the duel is
/// live on the server either way, and its next `duel.update` raises the board
/// through the resume path.
void main() {
  /// A `match.found` shaped as the server sends it the moment two players are
  /// paired: nothing on the board yet, this player to move first.
  Map<String, dynamic> matchFound() => {
        'duelId': 'duel-3',
        'opponent': {
          'id': 42,
          'nickname': 'aziz',
          'displayName': 'Aziz',
          'initial': 'A',
          'city': 'Toshkent',
          'rating': 1310,
          'streakDays': 4,
        },
        'rated': true,
        'chain': [
          {'word': 'battle', 'mine': false, 'spentMs': 0},
        ],
        'yourTurn': true,
        'needLetter': 'e',
        'turnSeconds': 15,
      };

  test('a whole frame raises the whole board', () {
    final duel = DuelView.fromMatchFound(matchFound());

    expect(duel, isNotNull);
    expect(duel!.duelId, 'duel-3');
    expect(duel.opponent.label, 'aziz');
    expect(duel.opponent.rating, 1310);
    expect(duel.rated, isTrue);
    expect(duel.chain.single.word, 'battle');
    expect(duel.yourTurn, isTrue);
    expect(duel.needLetter, 'E');
    // The ring opens on a full turn: no time has been spent on it yet.
    expect(duel.timeLeftMs, 15000);
    expect(duel.turnSeconds, 15);
    expect(duel.opponentThinking, isFalse);
  });

  test('a frame that does not name the opponent raises no board', () {
    // The crash as it actually arrived. There is no honest board to draw
    // without knowing who is on the other side of it, and the old code did not
    // draw one either — it threw halfway through trying.
    expect(DuelView.fromMatchFound(matchFound()..remove('opponent')), isNull);
  });

  test('an opponent of the wrong shape raises no board', () {
    // Version skew does not only drop fields; it also changes them. A server
    // that starts sending the opponent as a bare nickname must not be read as
    // if it still sent an object.
    expect(DuelView.fromMatchFound(matchFound()..['opponent'] = 'aziz'), isNull);
    expect(DuelView.fromMatchFound(matchFound()..['opponent'] = 42), isNull);
  });

  test('a frame that does not name the duel raises no board', () {
    // The id is what defends the board afterwards — see [duelFrameApplies] —
    // and a duel that cannot be named cannot be defended: the result of the
    // previous duel would be free to wipe it.
    expect(DuelView.fromMatchFound(matchFound()..remove('duelId')), isNull);
    expect(DuelView.fromMatchFound(matchFound()..['duelId'] = 3), isNull);
  });

  test('the fields that were always optional still are', () {
    // Being strict about the two that matter is not an excuse to start
    // refusing frames over the rest: a duel with the bare minimum in it is
    // still a duel, and the defaults here are the ones the app has always used.
    final duel = DuelView.fromMatchFound({
      'duelId': 'duel-3',
      'opponent': {'id': 42, 'initial': 'A'},
    });

    expect(duel, isNotNull);
    expect(duel!.rated, isTrue);
    expect(duel.chain, isEmpty);
    expect(duel.yourTurn, isFalse);
    expect(duel.needLetter, 'A');
    expect(duel.turnSeconds, 15);
    // Not this player's turn means the other one is thinking — that is what
    // the duel screen draws while it waits.
    expect(duel.opponentThinking, isTrue);
  });

  test('a board it does raise is one the guards can defend', () {
    final duel = DuelView.fromMatchFound(matchFound())!;

    expect(duelFrameApplies(duel.duelId, 'duel-3'), isTrue);
    expect(duelFrameApplies(duel.duelId, 'duel-2'), isFalse);
  });
}
