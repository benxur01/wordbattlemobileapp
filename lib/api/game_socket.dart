import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';

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
  GameSocket();

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

  Stream<SocketEvent> get events => _events.stream;
  Stream<SocketStatus> get status => _status.stream;
  bool get isConnected => _channel != null;

  void connect(String token) {
    _token = token;
    _closedByUs = false;
    _attempt = 0;
    _open();
  }

  void _open() {
    final token = _token;
    if (token == null) return;

    _status.add(SocketStatus.connecting);
    try {
      final channel = WebSocketChannel.connect(ApiConfig.socket(token));
      _channel = channel;
      _subscription = channel.stream.listen(
        _onFrame,
        onDone: _onDone,
        onError: (Object _) => _onDone(),
        cancelOnError: true,
      );
      // The first frame the server sends is `hello`; treating the socket as
      // connected only then would delay the UI, so trust the handshake here
      // and let `_onDone` undo it if it failed.
      _status.add(SocketStatus.connected);
      _startHeartbeat();
    } catch (_) {
      _onDone();
    }
  }

  void _onFrame(dynamic raw) {
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

  void _onDone() {
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

  void send(String type, [Map<String, dynamic> payload = const {}]) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({'type': type, 'payload': payload}));
    } catch (_) {
      // Socket died between the check and the write; the reconnect handles it.
    }
  }

  Future<void> disconnect() async {
    _closedByUs = true;
    _reconnectTimer?.cancel();
    _heartbeat?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _status.add(SocketStatus.idle);
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _status.close();
  }
}
