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
import uz.wordbattle.friend.PresenceService;

/**
 * Keeps one live socket per player and serialises outbound frames.
 *
 * <p>Also the answer to who is online: this map is the only place that knows,
 * so {@link PresenceService} asks it rather than keeping a list beside it —
 * see there for the count that once climbed and never came down.
 */
@Component
public class SocketRegistry implements PresenceService.ConnectedPlayers {

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

    /**
     * Closes the player's socket, if they have one.
     *
     * <p>The entry goes now rather than when the close callback runs, because
     * the caller is account deletion and nothing more may be sent to a player
     * being erased. That leaves the callback with no session to recognise, so
     * it reads its own close as a replaced socket and returns early — meaning
     * whoever calls this owns the teardown that callback would have done.
     * {@code SocketSessionEnder} does: matchmaking, invites and the duel, all
     * before this point. It did not own presence, and could not have known it
     * had to, which is why presence is read from here instead.
     */
    public void disconnect(Long userId) {
        WebSocketSession session = sessions.remove(userId);
        if (session == null) return;
        try {
            session.close();
        } catch (IOException ignored) {
            // already gone
        }
    }

    @Override
    public boolean isConnected(Long userId) {
        WebSocketSession session = sessions.get(userId);
        return session != null && session.isOpen();
    }

    /**
     * How many players are reachable. A walk over the sessions rather than
     * {@code size()}, so that it answers the same question {@link #isConnected}
     * does — a socket already reported closed is nobody's presence. The map
     * holds one entry per connected player, and this is asked twice per
     * connection, so the cost is not worth a counter to go wrong.
     */
    @Override
    public int connectedCount() {
        return (int) sessions.values().stream().filter(WebSocketSession::isOpen).count();
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
