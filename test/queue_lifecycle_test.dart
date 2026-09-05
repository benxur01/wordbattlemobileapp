import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/app_root.dart';
import 'package:word_battle/models.dart';

/// Leaving the queue when the app goes away, and — the half that was missing —
/// claiming it back on the way in. Without the return trip a player who locked
/// their phone on the search screen came back to a radar that would turn
/// forever: the server had dropped them, so no opponent and not even the bot
/// fallback was ever coming.
void main() {
  test('backgrounding the search screen gives up the queue', () {
    expect(queueActionFor(AppLifecycleState.paused, WBScreen.match), QueueAction.leave);
    expect(queueActionFor(AppLifecycleState.hidden, WBScreen.match), QueueAction.leave);
    expect(queueActionFor(AppLifecycleState.detached, WBScreen.match), QueueAction.leave);
  });

  test('returning to the search screen claims it back', () {
    expect(queueActionFor(AppLifecycleState.resumed, WBScreen.match), QueueAction.rejoin);
  });

  test('a notification banner is not backgrounding', () {
    // iOS raises `inactive` for the app switcher preview and for banners;
    // treating those as a departure would restart the search constantly.
    expect(queueActionFor(AppLifecycleState.inactive, WBScreen.match), QueueAction.none);
  });

  test('backgrounding the team-queue screen gives up the queue', () {
    // The 2v2 queue is a standing claim on the server the same way the 1v1
    // one is — see `exitFrameFor`'s `team.queue.leave`.
    expect(queueActionFor(AppLifecycleState.paused, WBScreen.teamQueue), QueueAction.leave);
    expect(queueActionFor(AppLifecycleState.hidden, WBScreen.teamQueue), QueueAction.leave);
    expect(queueActionFor(AppLifecycleState.detached, WBScreen.teamQueue), QueueAction.leave);
  });

  test('returning to the team-queue screen claims it back', () {
    expect(queueActionFor(AppLifecycleState.resumed, WBScreen.teamQueue), QueueAction.rejoin);
  });

  test('every other screen is left alone', () {
    for (final screen in WBScreen.values.where((s) => s != WBScreen.match && s != WBScreen.teamQueue)) {
      for (final state in AppLifecycleState.values) {
        expect(queueActionFor(state, screen), QueueAction.none,
            reason: '$state on $screen must not touch the queue');
      }
    }
  });
}
