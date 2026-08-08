package uz.wordbattle.ws;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

/** Keeps one live socket per player and serialises outbound frames. */
@Component
public class SocketRegistry {

    private static final Logger log = LoggerFactory.getLogger(SocketRegistry.class);

    private final Map<Long, WebSocketSession> sessions = new ConcurrentHashMap<>();
    private final ObjectMapper mapper;

    public SocketRegistry(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    public void register(Long userId, WebSocketSession session) {
        WebSocketSession previous = sessions.put(userId, session);
        if (previous != null && previous.isOpen() && !previous.getId().equals(session.getId())) {
            // Second device / reconnect: drop the stale socket.
            try {
                previous.close();
            } catch (IOException ignored) {
                // nothing useful to do, the socket is already gone
            }
        }
    }

    /**
     * Drops the session, but only if it is still the one registered for this
     * player, and says whether it was. A reconnect swaps the entry before the
     * old socket's close callback arrives, so {@code false} means "this close
     * belongs to a socket that has already been replaced" — the caller must
     * then leave the player's state alone.
     */
    public boolean unregister(Long userId, WebSocketSession session) {
        return sessions.remove(userId, session);
    }

    /** Closes the player's socket, if they have one. */
    public void disconnect(Long userId) {
        WebSocketSession session = sessions.remove(userId);
        if (session == null) return;
        try {
            session.close();
        } catch (IOException ignored) {
            // already gone
        }
    }

    public boolean isConnected(Long userId) {
        WebSocketSession session = sessions.get(userId);
        return session != null && session.isOpen();
    }

    public void send(Long userId, String type, Object payload) {
        WebSocketSession session = sessions.get(userId);
        if (session == null || !session.isOpen()) return;
        try {
            String json = mapper.writeValueAsString(Map.of("type", type, "payload", payload));
            synchronized (session) {
                session.sendMessage(new TextMessage(json));
            }
        } catch (IOException e) {
            log.debug("Frame to {} dropped: {}", userId, e.getMessage());
        }
    }

    public void sendError(Long userId, String code, String message) {
        send(userId, "error", Map.of("code", code, "message", message));
    }
}
