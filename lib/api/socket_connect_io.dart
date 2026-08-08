import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';

/// Phone and desktop: the token travels in a header, never in the URL.
WebSocketChannel openGameSocket(String token) => IOWebSocketChannel.connect(
      ApiConfig.socket(),
      headers: {'Authorization': 'Bearer $token'},
      pingInterval: const Duration(seconds: 20),
    );
