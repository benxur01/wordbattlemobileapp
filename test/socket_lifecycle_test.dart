import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:word_battle/api/game_socket.dart';
import 'package:word_battle/app_root.dart';
import 'package:word_battle/models.dart';

/// The second connection, and the frame that never left the phone.
///
/// Two separate ways the app and the server stopped agreeing about what the
/// player was doing, both of them on the duel path.
///
/// The first: `connect` was not reentrant. Two taps on the offline screen's
/// retry started two bootstraps and two dials, and the second overwrote the
/// fields describing the first. The first socket did not close — it stayed
/// connected, doubling every frame into a stream nobody could tell the copies
/// apart in — and when it eventually died, its `onDone` cancelled and nulled
/// whatever those fields pointed at by then: the second, healthy connection. A
/// good socket was marked disconnected and reconnected on top of, possibly in
/// the middle of a duel.
///
/// The second: `send` returned nothing. `duel.forfeit` and `queue.leave` are
/// the player saying they have stopped playing, and on a socket that was
/// reconnecting at that moment they were dropped in silence while the app moved
/// to the lobby as if the server had been told. It had not, and the next
/// `duel.update` for the duel it still had running pulled the player back onto
/// a board they had walked away from.
void main() {
  /// A socket wired to fakes, with the list of connections it has really
  /// opened. Counting those is the whole point: the leak was invisible from
  /// outside precisely because a second socket looks exactly like the first.
  ({GameSocket socket, List<FakeChannel> opened}) socketWithFakes() {
    final opened = <FakeChannel>[];
    final socket = GameSocket(dial: (token) {
      final channel = FakeChannel(token);
      opened.add(channel);
      return channel;
    });
    return (socket: socket, opened: opened);
  }

  group('dialling twice', () {
    test('a second connect while a socket is up opens nothing', () async {
      final (:socket, :opened) = socketWithFakes();

      socket.connect('token');
      socket.connect('token');
      socket.connect('token');

      expect(opened, hasLength(1), reason: 'two taps on retry must not leave a socket behind');
      expect(socket.isConnected, isTrue);
      await socket.dispose();
    });

    test('the socket already up is the one still being written to', () async {
      // The leak was only half of it. The second dial also took the first
      // socket off the fields, so the app talked to the new one while the old
      // one kept delivering — and the old one was the one holding the queue and
      // the duel the server had granted.
      final (:socket, :opened) = socketWithFakes();

      socket.connect('token');
      socket.connect('token');

      expect(socket.send('queue.join'), isTrue);
      expect(opened.single.sent, hasLength(1));
      expect((jsonDecode(opened.single.sent.single) as Map)['type'], 'queue.join');
      await socket.dispose();
    });

    test('a connect during the backoff leaves the pending dial to do it', () async {
      // The same retry button, tapped between attempts. `_channel` is null
      // there, so the only thing saying a dial is already coming is the timer —
      // and without asking it, this call opened a socket the backoff then
      // opened a second one alongside.
      final (:socket, :opened) = socketWithFakes();
      socket.connect('token');
      opened.single.die();
      await pumpEventQueue();
      expect(socket.isConnected, isFalse, reason: 'the drop has been noticed');

      socket.connect('token');

      expect(opened, hasLength(1), reason: 'the backoff already owns the next dial');
      await socket.dispose();
    });

    test('a socket taken down deliberately lets the next connect through', () async {
      // The guard must not become a lock: logging out and back in has to reach
      // the server again.
      final (:socket, :opened) = socketWithFakes();
      socket.connect('token');
      await socket.disconnect();
      expect(socket.isConnected, isFalse);

      socket.connect('another-token');

      expect(opened, hasLength(2));
      expect(opened.last.token, 'another-token');
      expect(socket.isConnected, isTrue);
      await socket.dispose();
    });

    test('closing a socket leaves nothing of it behind to reconnect', () async {
      // `disconnect` used to leave `_subscription` set and clear `_channel`
      // only after its awaits, which is a window with a half-dead socket in the
      // fields. Nothing may reconnect off the back of a close we asked for.
      final (:socket, :opened) = socketWithFakes();
      socket.connect('token');
      await socket.disconnect();
      await pumpEventQueue();

      expect(opened.single.closed, isTrue);
      expect(opened, hasLength(1), reason: 'a close we asked for is not a drop to recover from');
      await socket.dispose();
    });
  });

  group('whether a frame went out', () {
    test('a send with no socket says so instead of pretending', () async {
      final (:socket, :opened) = socketWithFakes();

      expect(socket.send('duel.forfeit'), isFalse, reason: 'never dialled');

      socket.connect('token');
      expect(socket.send('duel.forfeit'), isTrue);
      await socket.dispose();
    });

    test('a send after the socket drops under it says so too', () async {
      // The exact moment that mattered: the player backs out of a duel while
      // the socket is down and reconnecting. The forfeit goes nowhere, and the
      // app used to walk to the lobby as though it had arrived.
      final (:socket, :opened) = socketWithFakes();
      socket.connect('token');
      opened.single.die();
      await pumpEventQueue();

      expect(socket.send('duel.forfeit'), isFalse);
      await socket.dispose();
    });

    test('what a delivered frame actually carries is unchanged', () async {
      final (:socket, :opened) = socketWithFakes();
      socket.connect('token');

      expect(socket.send('invite.decline', {'inviteId': 'inv-1'}), isTrue);

      final frame = jsonDecode(opened.single.sent.single) as Map<String, dynamic>;
      expect(frame['type'], 'invite.decline');
      expect(frame['payload'], {'inviteId': 'inv-1'});
      await socket.dispose();
    });
  });

  group('what walking off a screen owes the server', () {
    test('leaving a duel is a forfeit', () {
      expect(exitFrameFor(WBScreen.duel, WBScreen.lobby), 'duel.forfeit');
    });

    test('leaving the search gives up the queue', () {
      expect(exitFrameFor(WBScreen.match, WBScreen.lobby), 'queue.leave');
    });

    test('the duel screen is left by a forfeit wherever it is left for', () {
      // Including the win and lose screens: those are raised by the server's
      // own `duel.finished`, which does not go through here, so anything that
      // reaches this call from a duel really is the player walking out.
      for (final next in WBScreen.values.where((s) => s != WBScreen.duel)) {
        expect(exitFrameFor(WBScreen.duel, next), 'duel.forfeit', reason: 'duel -> $next is still a forfeit');
      }
    });

    test('staying put owes nothing', () {
      expect(exitFrameFor(WBScreen.duel, WBScreen.duel), isNull);
      expect(exitFrameFor(WBScreen.match, WBScreen.match), isNull);
    });

    test('leaving a team duel is a forfeit', () {
      expect(exitFrameFor(WBScreen.teamDuel, WBScreen.lobby), 'team_duel.forfeit');
    });

    test('leaving the team search gives up the queue', () {
      expect(exitFrameFor(WBScreen.teamQueue, WBScreen.lobby), 'team.queue.leave');
    });

    test('the team-duel screen is left by a forfeit wherever it is left for', () {
      for (final next in WBScreen.values.where((s) => s != WBScreen.teamDuel)) {
        expect(
          exitFrameFor(WBScreen.teamDuel, next),
          'team_duel.forfeit',
          reason: 'teamDuel -> $next is still a forfeit',
        );
      }
    });

    test('staying put on a team screen owes nothing', () {
      expect(exitFrameFor(WBScreen.teamDuel, WBScreen.teamDuel), isNull);
      expect(exitFrameFor(WBScreen.teamQueue, WBScreen.teamQueue), isNull);
    });

    test('every other screen owes nothing', () {
      // Only the duel and the search — 1v1 or team — are standing claims on
      // the server. Sending a forfeit from the leaderboard would end a duel
      // nobody left.
      final claims = {WBScreen.duel, WBScreen.match, WBScreen.teamDuel, WBScreen.teamQueue};
      for (final from in WBScreen.values.where((s) => !claims.contains(s))) {
        expect(exitFrameFor(from, WBScreen.lobby), isNull, reason: '$from is not a claim on the server');
      }
    });
  });
}

/// A socket that never touches the network: it keeps what is written to it and
/// dies when told to.
///
/// Stands in for the real handshake through [GameSocket.dial], the way
/// `MockClient` stands in for HTTP in `api_client_test.dart`. None of the
/// lifecycle above — two dials racing, a connection dropping on cue — can be
/// provoked against a live server.
class FakeChannel implements WebSocketChannel {
  FakeChannel(this.token);

  final String token;
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final List<String> sent = [];
  bool closed = false;

  /// The connection going away, as the stream sees it.
  void die() => incoming.close();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  late final WebSocketSink sink = FakeSink(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSink implements WebSocketSink {
  FakeSink(this.channel);

  final FakeChannel channel;

  @override
  void add(dynamic data) => channel.sent.add(data as String);

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    channel.closed = true;
    return channel.incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
