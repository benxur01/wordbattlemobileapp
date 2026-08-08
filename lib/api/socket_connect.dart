/// Opens the game socket the best way the platform allows.
///
/// On a phone the token goes in an `Authorization` header, because a token in
/// the query string is written to every proxy and load-balancer access log the
/// handshake passes through, and those logs outlive the session. A browser
/// cannot set headers on a WebSocket upgrade at all, so the web build falls
/// back to `?token=` — the server accepts both.
library;

export 'socket_connect_web.dart' if (dart.library.io) 'socket_connect_io.dart';
