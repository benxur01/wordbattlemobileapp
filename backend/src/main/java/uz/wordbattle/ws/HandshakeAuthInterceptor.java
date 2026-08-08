package uz.wordbattle.ws;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.http.server.ServletServerHttpRequest;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;
import uz.wordbattle.auth.JwtService;

/**
 * Authenticates the socket during the handshake.
 *
 * <p>The header is preferred: a token in the query string is written to every
 * proxy and load-balancer access log it passes through, and those logs outlive
 * the session. Native clients can set headers on an upgrade, and ours does.
 *
 * <p>The {@code ?token=} form stays supported because a browser cannot set
 * headers on a WebSocket upgrade at all — a web build has no other option.
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

        String token = bearerToken(request);
        if (token == null && request instanceof ServletServerHttpRequest servletRequest) {
            token = servletRequest.getServletRequest().getParameter("token");
        }
        if (token == null) {
            String query = request.getURI().getQuery();
            if (query != null) {
                for (String pair : query.split("&")) {
                    if (pair.startsWith("token=")) {
                        token = URLDecoder.decode(pair.substring("token=".length()), StandardCharsets.UTF_8);
                    }
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

    private String bearerToken(ServerHttpRequest request) {
        String header = request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
        return header != null && header.startsWith("Bearer ") ? header.substring("Bearer ".length()) : null;
    }

    @Override
    public void afterHandshake(
            ServerHttpRequest request, ServerHttpResponse response, WebSocketHandler wsHandler, Exception exception) {
        // nothing to do
    }
}
