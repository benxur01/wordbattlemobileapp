package uz.wordbattle.ws;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.lang.NonNull;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.friend.FriendService;
import uz.wordbattle.friend.PresenceService;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.match.InviteService;
import uz.wordbattle.match.MatchmakingService;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserService;

/**
 * The single realtime endpoint. Frames are {@code {"type": ..., "payload": ...}}
 * — see the protocol table in the README.
 */
@Component
public class GameSocketHandler extends TextWebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(GameSocketHandler.class);

    private final ObjectMapper mapper;
    private final SocketRegistry sockets;
    private final MatchmakingService matchmaking;
    private final DuelService duels;
    private final InviteService invites;
    private final PresenceService presence;
    private final UserService users;
    private final FriendService friends;
    private final AppProperties props;

    public GameSocketHandler(
            ObjectMapper mapper,
            SocketRegistry sockets,
            MatchmakingService matchmaking,
            DuelService duels,
            InviteService invites,
            PresenceService presence,
            UserService users,
            FriendService friends,
            AppProperties props) {
        this.mapper = mapper;
        this.sockets = sockets;
        this.matchmaking = matchmaking;
        this.duels = duels;
        this.invites = invites;
        this.presence = presence;
        this.users = users;
        this.friends = friends;
        this.props = props;
    }

    private Long userIdOf(WebSocketSession session) {
        Object value = session.getAttributes().get(HandshakeAuthInterceptor.USER_ID);
        return value instanceof Long id ? id : null;
    }

    @Override
    public void afterConnectionEstablished(@NonNull WebSocketSession session) {
        Long userId = userIdOf(session);
        if (userId == null) return;

        sockets.register(userId, session);
        presence.connected(userId);
        users.markSeen(userId);
        log.info("Socket connected: user={} online={}", userId, presence.onlineCount());

        Map<String, Object> hello = new LinkedHashMap<>();
        hello.put("user", UserDto.of(users.require(userId)));
        hello.put("rules", Map.of(
                "turnSeconds", props.duel().turnSeconds(),
                "minWordLength", props.duel().minWordLength(),
                "wordsToWin", props.duel().wordsToWin(),
                "inviteTimeoutSeconds", props.duel().inviteTimeoutSeconds()));
        hello.put("onlineCount", presence.onlineCount());
        hello.put("pendingFriendRequests", friends.pendingRequestCount(userId));
        sockets.send(userId, "hello", hello);

        // Reconnecting mid-duel: hand the player back their live state.
        duels.duelOf(userId).ifPresent(duel -> duels.sendState(duel, userId));
    }

    @Override
    protected void handleTextMessage(@NonNull WebSocketSession session, @NonNull TextMessage message) {
        Long userId = userIdOf(session);
        if (userId == null) return;

        Envelope envelope;
        try {
            envelope = mapper.readValue(message.getPayload(), Envelope.class);
        } catch (Exception e) {
            sockets.sendError(userId, "bad_frame", "Xabarni o'qib bo'lmadi");
            return;
        }

        String type = envelope.type() == null ? "" : envelope.type();
        if (!"ping".equals(type)) log.info("Frame from {}: {}", userId, type);
        try {
            switch (type) {
                case "ping" -> sockets.send(userId, "pong", Map.of());
                case "queue.join" -> matchmaking.join(userId);
                case "queue.leave" -> matchmaking.leave(userId);
                case "duel.submit" -> duels.submit(userId, text(envelope, "word"));
                case "duel.forfeit" -> duels.forfeit(userId);
                case "invite.send" -> invites.send(userId, longValue(envelope, "userId"));
                case "invite.accept" -> invites.accept(userId, text(envelope, "inviteId"));
                case "invite.decline" -> invites.decline(userId, text(envelope, "inviteId"));
                default -> sockets.sendError(userId, "unknown_type", "Noma'lum xabar turi: " + type);
            }
        } catch (Exception e) {
            log.warn("Socket frame '{}' from {} failed", type, userId, e);
            sockets.sendError(userId, "frame_failed", "Amalni bajarib bo'lmadi");
        }
    }

    @Override
    public void afterConnectionClosed(@NonNull WebSocketSession session, @NonNull CloseStatus status) {
        Long userId = userIdOf(session);
        if (userId == null) return;

        sockets.unregister(userId, session);
        matchmaking.leave(userId);
        invites.cancelAllFor(userId);
        // Dropping out of a live duel hands the win to the opponent, exactly as
        // quitting does — otherwise pulling the plug would be a free escape.
        duels.forfeit(userId);
        presence.disconnected(userId);
        users.markSeen(userId);
        log.info("Socket closed: user={} status={}", userId, status);
    }

    private String text(Envelope envelope, String field) {
        return envelope.payload() == null ? null : envelope.payload().path(field).asText(null);
    }

    private long longValue(Envelope envelope, String field) {
        return envelope.payload() == null ? 0L : envelope.payload().path(field).asLong();
    }
}
