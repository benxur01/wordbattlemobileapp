import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'socket_connect.dart';

/// One frame from the server.
class SocketEvent {
  const SocketEvent(this.type, this.payload);

  final String type;
  final Map<String, dynamic> payload;

  T? get<T>(String key) => payload[key] as T?;
}

enum SocketStatus { idle, connecting, connected, disconnected }

/// The realtime link to the duel server.
///
/// Reconnects on its own with a backoff — a phone loses its connection when it
/// changes network or sleeps, and the player should not have to restart the app
/// to get back into the game. The server replays the live duel state on
/// reconnect, so no state is kept here beyond the socket itself.
class GameSocket {
  /// [dial] stands in for the real handshake in tests, the way [ApiClient]'s
  /// `httpClient` does. What this class has to get right — a second dial while
  /// one socket is already up, a socket that dies after being replaced — is
  /// lifecycle, and none of it can be provoked against a live server.
  GameSocket({WebSocketChannel Function(String token)? dial}) : _dial = dial ?? openGameSocket;

  final WebSocketChannel Function(String token) _dial;

  static const _backoff = [1, 2, 4, 8, 15];

  final _events = StreamController<SocketEvent>.broadcast();
  final _status = StreamController<SocketStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeat;
  String? _token;
  int _attempt = 0;
  bool _closedByUs = false;

  /// Which socket the fields below currently describe.
  ///
  /// Every [_open] claims the next number and hands it to its own callbacks, so
  /// a callback can tell whether it still speaks for the connection. One that
  /// does not belongs to a socket already replaced or closed, and it must touch
  /// nothing: `_onDone` cancels `_subscription` and nulls `_channel`, and run
  /// late those two fields no longer name the socket that died — they name the
  /// live one, which it would then tear down.
  int _generation = 0;

  Stream<SocketEvent> get events => _events.stream;
  Stream<SocketStatus> get status => _status.stream;
  bool get isConnected => _channel != null;

  /// Reconnects tried since the last frame actually arrived. The app uses it to
  /// tell "the network blipped" from "this token is no longer accepted".
  int get failedAttempts => _attempt;

  /// Dials the server, and does nothing when a socket is already up or already
  /// on its way back up.
  ///
  /// Being called twice is not theoretical: the app dials on bootstrap and
  /// again on login, and the offline screen's retry can be tapped twice before
  /// the first attempt has finished. The second call used to open a second
  /// socket and overwrite the fields describing the first, which then stayed
  /// open — still connected, still pushing duplicate frames into the shared
  /// stream nobody could tell them apart in. Worse than the leak was what the
  /// leaked socket did on its way out: its `_onDone` ran against fields that by
  /// then named the *second* socket, so a healthy connection was cancelled,
  /// reported disconnected and reconnected on top of — mid-duel, if that is
  /// where the player was.
  void connect(String token) {
    _token = token;
    _closedByUs = false;
    if (_channel != null || (_reconnectTimer?.isActive ?? false)) return;
    _attempt = 0;
    _open();
  }

  void _open() {
    final token = _token;
    if (token == null) return;
    final generation = ++_generation;

    _status.add(SocketStatus.connecting);
    try {
      final channel = _dial(token);
      _channel = channel;
      _subscription = channel.stream.listen(
        (raw) => _onFrame(generation, raw),
        onDone: () => _onDone(generation),
        onError: (Object _) => _onDone(generation),
        cancelOnError: true,
      );
      // The first frame the server sends is `hello`; treating the socket as
      // connected only then would delay the UI, so trust the handshake here
      // and let `_onDone` undo it if it failed.
      _status.add(SocketStatus.connected);
      _startHeartbeat();
    } catch (_) {
      _onDone(generation);
    }
  }

  void _onFrame(int generation, dynamic raw) {
    // A frame from a socket that is no longer ours is a frame the app has
    // already been told, or is about to be told, by the one that is: passing it
    // on would duplicate it, and resetting the backoff below on its word would
    // credit the live socket with a delivery it never made.
    if (generation != _generation) return;
    // A frame is the only proof the socket really came up — the handshake
    // itself resolves before the server has accepted the token. Resetting the
    // backoff here (rather than never, as it was) matters: without it the
    // second drop of a session waited the full 15s, which is longer than the
    // server's disconnect grace, and the player lost a duel they were winning.
    _attempt = 0;
    if (raw is! String) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';
      final payload = (json['payload'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      if (type.isNotEmpty) _events.add(SocketEvent(type, payload));
    } catch (_) {
      // A frame we cannot parse is not worth tearing the socket down for.
    }
  }

  void _onDone(int generation) {
    // The socket that died has already been replaced; the fields this would
    // clear belong to the live one now. See [_generation].
    if (generation != _generation) return;
    _heartbeat?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _status.add(SocketStatus.disconnected);
    if (!_closedByUs) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final seconds = _backoff[_attempt.clamp(0, _backoff.length - 1)];
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), _open);
  }

  /// Keeps intermediaries from dropping an idle socket.
  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) => send('ping'));
  }

  /// Writes a frame, and says whether it actually went out.
  ///
  /// It silently did nothing on a socket that was down, which most callers can
  /// live with — a `ping`, a `queue.join` the `hello` handler repeats anyway.
  /// The two that cannot are `duel.forfeit` and `queue.leave`: those are the
  /// player telling the server they have stopped playing, and dropping one
  /// leaves the app sure the duel is over while the server has it still
  /// running. See `go` in `app_root.dart` for what is done with the answer.
  bool send(String type, [Map<String, dynamic> payload = const {}]) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add(jsonEncode({'type': type, 'payload': payload}));
      return true;
    } catch (_) {
      // Socket died between the check and the write; the reconnect handles it.
      return false;
    }
  }

  Future<void> disconnect() async {
    _closedByUs = true;
    // Nothing this socket does from here on speaks for the app, including the
    // `onDone` its own close is about to fire. See [_generation].
    _generation++;
    _reconnectTimer?.cancel();
    _heartbeat?.cancel();
    // Taken off the fields before the first `await`, so there is no window in
    // which [connect] or [send] can find a socket here that is already going
    // away — and so the close below cannot end up nulling a socket opened in
    // the meantime.
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    await channel?.sink.close();
    _status.add(SocketStatus.idle);
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _status.close();
  }
}
