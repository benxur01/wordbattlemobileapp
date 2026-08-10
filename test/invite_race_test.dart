import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/app_root.dart';
import 'package:word_battle/models.dart';

/// The challenge that was answered before the app knew it had been sent.
///
/// An invite makes two frames and they leave on two different sockets: the
/// player being challenged is told first, the player who challenged second. A
/// scripted client run against the live server declined instantly, and what
/// came down the inviter's socket was `invite.declined` — with `invite.sent`
/// never arriving at all. Server ordering is being fixed separately, but no
/// ordering the server can promise reaches across two sockets, so the app is
/// not allowed to assume one.
///
/// Everything below is the app's half: a reply that names an invite the app has
/// not heard of yet, a confirmation that arrives after the player has moved on,
/// and a countdown that used to be the only thing left running on a wait that
/// was already over.
void main() {
  group('which invite a reply is about', () {
    test('a reply naming the invite in the slot settles it', () {
      expect(inviteFrameApplies('inv-1', 'inv-1'), isTrue);
    });

    test('a reply about the other direction leaves this one alone', () {
      // `invite.declined` is one frame type for two different events: the
      // server sends it to whichever player did not press the button, so it
      // means "your challenge was refused" on the inviter's socket and "the
      // challenge you were offered has been taken back" on the receiver's.
      // Read against both slots, the id is the only thing that says which.
      expect(inviteFrameApplies('inv-mine', 'inv-theirs'), isFalse);
      expect(inviteFrameApplies('inv-theirs', 'inv-theirs'), isTrue);
    });

    test('a reply about an invite the app is not holding settles nothing', () {
      // Deliberately not the free pass `duelFrameApplies` gives an absent duel.
      // A duel frame with no board to protect still has to be shown; an invite
      // reply with no invite to clear must not tear a screen down — it is the
      // race, and it is remembered instead.
      expect(inviteFrameApplies(null, 'inv-1'), isFalse);
      expect(inviteFrameApplies(null, null), isFalse);
    });

    test('a reply from a server too old to name the invite is obeyed', () {
      // Being strict here would strand the invite screen rather than protect
      // anything, so an unnamed reply clears whatever is waiting, as it always
      // did.
      expect(inviteFrameApplies('inv-1', null), isTrue);
    });
  });

  group('what a confirmation does by the time it lands', () {
    test('a confirmation for an invite already refused opens nothing', () {
      // The observed race. Without this the app raised "waiting for X" over an
      // invite the server had already dropped — and having dropped it, the
      // server would never expire it either, so nothing was ever coming to
      // close that screen again.
      expect(
        inviteSentActionFor(screen: WBScreen.friends, inviteId: 'inv-1', settledInviteId: 'inv-1'),
        InviteSentAction.drop,
      );
    });

    test('a refusal remembered for one invite does not silence the next', () {
      expect(
        inviteSentActionFor(screen: WBScreen.friends, inviteId: 'inv-2', settledInviteId: 'inv-1'),
        InviteSentAction.open,
      );
    });

    test('a confirmation that arrives mid-duel is taken back, not shown', () {
      // Tap Jang, give up waiting, search, get paired: `match.found` and the
      // late `invite.sent` arrive in that order and the second one used to set
      // the screen unconditionally. The player was pulled off a live board with
      // their turn timer still running on it, and because the screen was
      // changed by a frame rather than by `go`, no forfeit was sent either.
      expect(
        inviteSentActionFor(screen: WBScreen.duel, inviteId: 'inv-1', settledInviteId: null),
        InviteSentAction.withdraw,
      );
    });

    test('the same goes for a search and for a result just delivered', () {
      // All three are states the player was put in by something else they
      // chose, and in all three a friend accepting the forgotten invite would
      // start a duel nobody is watching.
      for (final screen in [WBScreen.match, WBScreen.win, WBScreen.lose]) {
        expect(
          inviteSentActionFor(screen: screen, inviteId: 'inv-1', settledInviteId: null),
          InviteSentAction.withdraw,
          reason: 'an invite confirmed on $screen must be withdrawn',
        );
      }
    });

    test('everywhere else the wait is shown', () {
      // The invite screen is the only place a live challenge can be seen and
      // cancelled, so anywhere nothing is at stake it is raised — including the
      // lobby and the leaderboard, which the player may well have wandered to
      // in the moment between tapping Jang and the server answering.
      for (final screen in [WBScreen.friends, WBScreen.lobby, WBScreen.board, WBScreen.profile]) {
        expect(
          inviteSentActionFor(screen: screen, inviteId: 'inv-1', settledInviteId: null),
          InviteSentAction.open,
          reason: 'an invite confirmed on $screen has nothing to interrupt',
        );
      }
    });
  });

  group('the countdown under an invite', () {
    final started = DateTime(2026, 8, 9, 12, 0, 0);

    test('it counts the server\'s window down', () {
      expect(inviteSecondsLeftAt(started, 12, started), 12);
      expect(inviteSecondsLeftAt(started, 12, started.add(const Duration(seconds: 5))), 7);
    });

    test('running out ends the wait instead of resting on 0:00', () {
      // What the stuck invite screen actually looked like: the clock reached
      // zero and stayed there. The frame that should have closed it was never
      // coming, because the server expires invites out of its own map and had
      // already dropped this one.
      expect(inviteSecondsLeftAt(started, 12, started.add(const Duration(seconds: 12))), isNull);
      expect(inviteSecondsLeftAt(started, 12, started.add(const Duration(seconds: 30))), isNull);
    });

    test('a wait with no start time is over', () {
      expect(inviteSecondsLeftAt(null, 12, started), isNull);
    });

    test('a start time left over from an older invite can only end a wait', () {
      // One clock serves both directions, so a stale start is possible. It is
      // always in the past, which makes the count too small and never too
      // large — the screen closes early rather than waiting on nothing.
      expect(inviteSecondsLeftAt(started.subtract(const Duration(minutes: 5)), 12, started), isNull);
    });
  });
}
