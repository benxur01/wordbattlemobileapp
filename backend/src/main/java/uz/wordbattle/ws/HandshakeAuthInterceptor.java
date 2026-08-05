package uz.wordbattle.ws;

import java.util.Map;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.http.server.ServletServerHttpRequest;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;
import uz.wordbattle.auth.JwtService;

/**
 * Authenticates the socket during the handshake. Browsers cannot set headers on
 * a WebSocket upgrade, so the token travels in the query string:
 * {@code /ws?token=<jwt>}.
 */
@Component
public class HandshakeAuthInterceptor implements HandshakeInterceptor {

    public static final String USER_ID = "userId";

    private final JwtService jwt;

    public HandshakeAuthInterceptor(JwtService jwt) {
        this.jwt = jwt;
    }

    @Override
    public boolean beforeHandshake(
            ServerHttpRequest request,
            ServerHttpResponse response,
            WebSocketHandler wsHandler,
            Map<String, Object> attributes) {

        String token = null;
        if (request instanceof ServletServerHttpRequest servletRequest) {
            token = servletRequest.getServletRequest().getParameter("token");
        }
        if (token == null) {
            String query = request.getURI().getQuery();
            if (query != null) {
                for (String pair : query.split("&")) {
                    if (pair.startsWith("token=")) token = pair.substring(6);
                }
            }
        }

        return jwt.userIdFrom(token)
                .map(userId -> {
                    attributes.put(USER_ID, userId);
                    return true;
                })
                .orElse(false);
    }

    @Override
    public void afterHandshake(
            ServerHttpRequest request, ServerHttpResponse response, WebSocketHandler wsHandler, Exception exception) {
        // nothing to do
    }
}
