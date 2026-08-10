import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/duel_models.dart';
import 'package:word_battle/app_root.dart';

/// The duel that vanished when the app did.
///
/// Every other thing the app knows survives a relaunch: the token is on disk,
/// the session is restored from it, the profile and the friends list are
/// refetched. A live duel did not, and the reason was small — the only frame
/// that ever raised the duel screen was `match.found`, which a process started
/// after the duel began will never see. The server did its half correctly all
/// along and handed the state back the moment the new socket connected; the app
/// dropped that frame because it had no board to apply it to.
///
/// What the player saw: the lobby. What happened: their turn timer ran out
/// unwatched and charged them a rated loss for a battle they were never shown,
/// while their opponent finished playing somebody who had gone silent. Android
/// kills apps for memory and players swipe them away out of habit, so this was
/// not a rare corner — it was every relaunch mid-battle.
///
/// The fix is [DuelView.fromDuelUpdate]: the server now names the opponent and
/// says whether the duel is rated on every state frame, and those two fields
/// are the whole difference between a frame that can only update a board and
/// one that can raise it.
void main() {
  /// A `duel.update` shaped exactly as the server sends it to a socket that has
  /// just connected into a live duel: the seed word and one answer on the
  /// board, the returning player on turn with part of their fifteen seconds
  /// already spent.
  Map<String, dynamic> stateFrame() => {
        'duelId': 'duel-7',
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
          {'word': 'energy', 'mine': false, 'spentMs': 2400},
        ],
        'yourTurn': true,
        'needLetter': 'y',
        'timeLeftMs': 9200,
        'turnSeconds': 15,
        'yourWords': 0,
        'opponentWords': 1,
        'opponentThinking': false,
      };

  test('a relaunched app builds the whole board out of one state frame', () {
    final resumed = DuelView.fromDuelUpdate(stateFrame());

    // Nothing here is guessed or defaulted: a board drawn from half a frame
    // would be worse than none, because the player would trust it.
    expect(resumed, isNotNull);
    expect(resumed!.duelId, 'duel-7');
    expect(resumed.opponent.label, 'aziz');
    expect(resumed.opponent.rating, 1310);
    expect(resumed.rated, isTrue);
    expect(resumed.chain.map((w) => w.word).toList(), ['battle', 'energy']);
    expect(resumed.chain.last.mine, isFalse);
    expect(resumed.yourTurn, isTrue);
    expect(resumed.needLetter, 'Y');
    expect(resumed.timeLeftMs, 9200);
    expect(resumed.turnSeconds, 15);
    expect(resumed.yourWords, 0);
    expect(resumed.opponentWords, 1);
    expect(resumed.opponentThinking, isFalse);
  });

  test('the countdown picks up where the server has it, not at the start', () {
    // The ring has to show what is actually left of the turn. Restarting it at
    // fifteen seconds would be a lie the player loses on: the server's timer is
    // the one that ends the duel, and it has been running the whole time the
    // app was being reopened.
    expect(DuelView.fromDuelUpdate(stateFrame())!.secondsLeft, 9.2);
  });

  test('the ticker takes its usual bite out of a board that just appeared', () {
    // The 100ms ticker has been running since the app started, and its clock
    // moves whether or not there is a duel to spend it on — so the first tick
    // after a resume subtracts one tick, not the age of the process. Worth
    // pinning: the opposite would empty the ring the instant the board arrived
    // and hand the duel away.
    final resumed = DuelView.fromDuelUpdate(stateFrame())!;
    expect(resumed.tick(100).timeLeftMs, 9100);
    // And it still stops at zero rather than running negative.
    expect(resumed.tick(20000).timeLeftMs, 0);
  });

  test('the rare-letter note survives the relaunch with the board', () {
    final frame = stateFrame()
      ..['chain'] = [
        {'word': 'battle', 'mine': false, 'spentMs': 0},
        {'word': 'relax', 'mine': false, 'spentMs': 3100},
      ]
      ..['needLetter'] = 'a'
      ..['substitutedFrom'] = 'x';

    final resumed = DuelView.fromDuelUpdate(frame)!;
    expect(resumed.needLetter, 'A');
    // Without it the returning player is asked for an "A" after a word ending
    // in "X" and has nothing telling them why.
    expect(resumed.substitutedFrom, 'X');
  });

  test('a frame that does not name the opponent raises no board', () {
    // A server older than the field. There is no honest board to draw without
    // knowing who is on the other side of it, so the app stays as it was rather
    // than inventing one.
    final old = stateFrame()..remove('opponent');
    expect(DuelView.fromDuelUpdate(old), isNull);
  });

  test('a frame that does not name the duel raises no board', () {
    // The id is what protects the board afterwards — see [duelFrameApplies] —
    // and a live duel that cannot be named cannot be defended.
    final anonymous = stateFrame()..remove('duelId');
    expect(DuelView.fromDuelUpdate(anonymous), isNull);
  });

  test('a resumed board is guarded like any other', () {
    // The resume path is the one place a board appears without `match.found`,
    // so it is worth proving it lands with a real id: `duelFrameApplies` is
    // what stops a result for a duel already left behind from wiping it, and it
    // waves everything through while the id is missing.
    final resumed = DuelView.fromDuelUpdate(stateFrame())!;
    expect(duelFrameApplies(resumed.duelId, 'duel-7'), isTrue);
    expect(duelFrameApplies(resumed.duelId, 'duel-9'), isFalse);
  });

  test('an update for the resumed duel is applied to it as usual', () {
    // Resuming must leave an ordinary live board behind, not a special one:
    // the next move on it goes through the same `applyUpdate` every other frame
    // does.
    final resumed = DuelView.fromDuelUpdate(stateFrame())!;
    final next = resumed.applyUpdate({
      'duelId': 'duel-7',
      'chain': [
        {'word': 'battle', 'mine': false, 'spentMs': 0},
        {'word': 'energy', 'mine': false, 'spentMs': 2400},
        {'word': 'yellow', 'mine': true, 'spentMs': 1800},
      ],
      'yourTurn': false,
      'needLetter': 'w',
      'timeLeftMs': 15000,
      'turnSeconds': 15,
      'yourWords': 1,
      'opponentWords': 1,
      'opponentThinking': true,
    });

    expect(next.chain.last.word, 'yellow');
    expect(next.yourWords, 1);
    expect(next.opponentThinking, isTrue);
    // The two fields only the resume frame carries are kept across it.
    expect(next.opponent.label, 'aziz');
    expect(next.rated, isTrue);
  });
}
