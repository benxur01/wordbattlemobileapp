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
     * of which it runs after this rather than before, so that nothing new can
     * be started for a player who can no longer be reached — see there. It did
     * not own presence, and could not have known it had to, which is why
     * presence is read from here instead.
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

    /**
     * Writes a frame to the player's socket.
     *
     * <p>{@code false} means it did not go — there was no socket, it had closed
     * since, or the write itself failed. Most callers have nothing to do about
     * any of the three and ignore the answer, which is why this stayed void for
     * so long. A duel's finish frame is the exception: it is the only thing a
     * player is ever owed rather than merely sent, and its caller has a shelf to
     * put it on for their return — but only if it is told the write did not
     * land. It was not, so a socket that closed between being looked up and
     * being written to swallowed the result, at DEBUG, and the duel ended with
     * the rating moved and the player never told which way. See {@code
     * DuelService.deliverFinish}.
     */
    public boolean send(Long userId, String type, Object payload) {
        WebSocketSession session = sessions.get(userId);
        if (session == null || !session.isOpen()) return false;
        try {
            String json = mapper.writeValueAsString(Map.of("type", type, "payload", payload));
            synchronized (session) {
                session.sendMessage(new TextMessage(json));
            }
            return true;
        } catch (IOException e) {
            log.debug("Frame to {} dropped: {}", userId, e.getMessage());
            return false;
        }
    }

    public void sendError(Long userId, String code, String message) {
        send(userId, "error", Map.of("code", code, "message", message));
    }
}
