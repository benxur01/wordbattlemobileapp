import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/app_root.dart';
import 'package:word_battle/models.dart';

/// When the lobby and the friends screen go back to the server for the friend
/// list and requests. They used to ask only on the way in, so a player who sat
/// on either never saw the badge for a request sent to them, and the online
/// count went stale under them.
void main() {
  test('the lobby and the friends screen keep asking while the app is on screen', () {
    for (final screen in [WBScreen.lobby, WBScreen.friends]) {
      expect(socialOnScreen(AppLifecycleState.resumed, screen), isTrue);
    }
  });

  test('a notification banner is not backgrounding', () {
    // As for the queue: iOS raises `inactive` for banners and the app switcher
    // preview, with the screen still in front of the player.
    for (final screen in [WBScreen.lobby, WBScreen.friends]) {
      expect(socialOnScreen(AppLifecycleState.inactive, screen), isTrue);
    }
  });

  test('a backgrounded app stops asking', () {
    for (final screen in [WBScreen.lobby, WBScreen.friends]) {
      expect(socialOnScreen(AppLifecycleState.paused, screen), isFalse);
      expect(socialOnScreen(AppLifecycleState.hidden, screen), isFalse);
      expect(socialOnScreen(AppLifecycleState.detached, screen), isFalse);
    }
  });

  test('every other screen is left alone', () {
    for (final screen in WBScreen.values.where((s) => s != WBScreen.lobby && s != WBScreen.friends)) {
      for (final state in AppLifecycleState.values) {
        expect(socialOnScreen(state, screen), isFalse, reason: '$state on $screen must not poll the friend list');
      }
    }
  });
}
