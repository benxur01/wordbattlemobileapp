import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';

/// Browsers cannot set headers on a WebSocket upgrade, so the token has to ride
/// in the query string here. Same server endpoint, weaker guarantee.
WebSocketChannel openGameSocket(String token) => WebSocketChannel.connect(ApiConfig.socketWithToken(token));
