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
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.friend.FriendService;
import uz.wordbattle.friend.PresenceService;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.match.InviteService;
import uz.wordbattle.match.MatchmakingService;
import uz.wordbattle.match.TeamDuelService;
import uz.wordbattle.match.TeamInviteService;
import uz.wordbattle.match.TeamMatchmakingService;
import uz.wordbattle.match.TeamService;
import uz.wordbattle.tournament.TournamentService;
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
    private final FrameRateLimiter rateLimiter;
    private final MatchmakingService matchmaking;
    private final DuelService duels;
    private final InviteService invites;
    private final PresenceService presence;
    private final UserService users;
    private final FriendService friends;
    private final AppProperties props;
    private final TournamentService tournaments;
    private final TeamInviteService teamInvites;
    private final TeamMatchmakingService teamMatchmaking;
    private final TeamDuelService teamDuels;
    private final TeamService teams;

    public GameSocketHandler(
            ObjectMapper mapper,
            SocketRegistry sockets,
            FrameRateLimiter rateLimiter,
            MatchmakingService matchmaking,
            DuelService duels,
            InviteService invites,
            PresenceService presence,
            UserService users,
            FriendService friends,
            AppProperties props,
            TournamentService tournaments,
            TeamInviteService teamInvites,
            TeamMatchmakingService teamMatchmaking,
            TeamDuelService teamDuels,
            TeamService teams) {
        this.mapper = mapper;
        this.sockets = sockets;
        this.rateLimiter = rateLimiter;
        this.matchmaking = matchmaking;
        this.duels = duels;
        this.invites = invites;
        this.presence = presence;
        this.users = users;
        this.friends = friends;
        this.props = props;
        this.tournaments = tournaments;
        this.teamInvites = teamInvites;
        this.teamMatchmaking = teamMatchmaking;
        this.teamDuels = teamDuels;
        this.teams = teams;
    }

    private Long userIdOf(WebSocketSession session) {
        Object value = session.getAttributes().get(HandshakeAuthInterceptor.USER_ID);
        return value instanceof Long id ? id : null;
    }

    @Override
    public void afterConnectionEstablished(@NonNull WebSocketSession session) {
        Long userId = userIdOf(session);
        if (userId == null) return;

        // Registering is also what puts them online — presence reads the live
        // sockets rather than being told about them separately.
        sockets.register(userId, session);
        // Back inside the grace window: the drop must not cost them the duel.
        duels.connectionRestored(userId);
        teamDuels.connectionRestored(userId);
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

        // A tournament invite or a ready match is a real row, not a 12-second
        // in-memory challenge, so it survives however long this player was
        // disconnected — but nothing pushes it to them until they have a socket
        // to push it down again. This is that push, standing in for the FCM this
        // server does not have (see the README's "Hali yo'q").
        tournaments.sendPendingNoticesTo(userId);

        // Reconnecting mid-duel: hand the player back their live state. If the
        // duel ended while they were away, hand them the result instead — the
        // finish frame went to a socket that was already gone, and without it
        // the app sits on a duel screen that will never move again.
        duels.duelOf(userId).ifPresentOrElse(
                duel -> {
                    presence.battleStarted(userId);
                    duels.sendState(duel, userId);
                },
                () -> duels.sendMissedFinish(userId));
        // Same reconnect handling for a 2v2 duel — a player is never in both
        // at once, so at most one of these two branches ever does anything.
        teamDuels.teamDuelOf(userId).ifPresentOrElse(
                duel -> {
                    presence.battleStarted(userId);
                    teamDuels.sendState(duel, userId);
                },
                () -> teamDuels.sendMissedFinish(userId));
    }

    @Override
    protected void handleTextMessage(@NonNull WebSocketSession session, @NonNull TextMessage message) {
        Long userId = userIdOf(session);
        if (userId == null) return;

        if (!rateLimiter.allow(userId)) {
            sockets.sendError(userId, "too_many_frames", "Juda ko'p so'rov — biroz kuting");
            return;
        }

        Envelope envelope;
        try {
            envelope = mapper.readValue(message.getPayload(), Envelope.class);
        } catch (Exception e) {
            sockets.sendError(userId, "bad_frame", "Xabarni o'qib bo'lmadi");
            return;
        }

        String type = envelope.type() == null ? "" : envelope.type();
        // Per-frame traffic at INFO buried everything else in the log.
        if (!"ping".equals(type)) log.debug("Frame from {}: {}", userId, type);
        try {
            switch (type) {
                case "ping" -> sockets.send(userId, "pong", Map.of());
                case "queue.join" -> matchmaking.join(userId);
                case "queue.leave" -> matchmaking.leave(userId);
                case "queue.bot" -> matchmaking.joinAgainstBot(
                        userId, doubleValue(envelope, "rating"), text(envelope, "theme"));
                case "duel.submit" -> duels.submit(userId, text(envelope, "word"));
                case "duel.forfeit" -> duels.forfeit(userId);
                case "duel.power_up" -> duels.usePowerUp(userId, text(envelope, "type"));
                case "duel.chat" -> duels.sendChat(userId, text(envelope, "text"));
                case "duel.reaction" -> duels.sendReaction(userId, text(envelope, "emoji"));
                case "duel.spectate" -> spectate(userId, longValue(envelope, "userId"));
                case "duel.unspectate" -> {
                    // One frame stops either kind of watch: the client is not
                    // told which engine took its `duel.spectate`, so it cannot
                    // be asked to name one on the way out. Whichever service
                    // this caller was not watching through does nothing.
                    duels.stopSpectating(userId);
                    teamDuels.stopSpectating(userId);
                }
                case "invite.send" -> invites.send(userId, longValue(envelope, "userId"));
                case "invite.accept" -> invites.accept(userId, text(envelope, "inviteId"));
                case "invite.decline" -> invites.decline(userId, text(envelope, "inviteId"));
                case "tournament.accept" -> tournaments.accept(userId, longValue(envelope, "tournamentId"));
                case "tournament.decline" -> tournaments.decline(userId, longValue(envelope, "tournamentId"));
                case "tournament.match_start" -> tournaments.startMatch(userId, longValue(envelope, "tournamentMatchId"));
                case "team_invite.send" -> teamInvites.send(userId, longValue(envelope, "userId"));
                case "team_invite.accept" -> teamInvites.accept(userId, text(envelope, "inviteId"));
                case "team_invite.decline" -> teamInvites.decline(userId, text(envelope, "inviteId"));
                case "team.cancel" -> teams.disbandFor(userId, "cancelled");
                case "team.queue.join" -> teamMatchmaking.join(userId);
                case "team.queue.leave" -> teamMatchmaking.leave(userId);
                case "team_duel.submit" -> teamDuels.submit(userId, text(envelope, "word"));
                case "team_duel.forfeit" -> teamDuels.forfeit(userId);
                case "team_duel.chat" -> teamDuels.sendChat(userId, text(envelope, "text"));
                case "team_duel.reaction" -> teamDuels.sendReaction(userId, text(envelope, "emoji"));
                default -> sockets.sendError(userId, "unknown_type", "Noma'lum xabar turi: " + type);
            }
        } catch (ApiException e) {
            // The tournament actions above are the only frames that fail this way
            // — everything else on this switch answers a bad request with its own
            // sockets.sendError rather than throwing. Their code and message are
            // worth keeping, the same way GlobalExceptionHandler keeps them for
            // the REST routes that share this service.
            sockets.sendError(userId, e.code(), e.getMessage());
        } catch (Exception e) {
            log.warn("Socket frame '{}' from {} failed", type, userId, e);
            sockets.sendError(userId, "frame_failed", "Amalni bajarib bo'lmadi");
        }
    }

    @Override
    public void afterConnectionClosed(@NonNull WebSocketSession session, @NonNull CloseStatus status) {
        Long userId = userIdOf(session);
        if (userId == null) return;

        // A reconnect registers the new socket before the old one's close
        // callback arrives, and every step below keys off the user id alone —
        // running them for a socket that has already been replaced would tear
        // down the state of the session that is right now live and playing.
        // Only unregister can tell the two apart, so it decides.
        //
        // It cannot always tell, and that is worth knowing before adding
        // anything here: taking the entry out of the registry directly, as
        // SocketRegistry.disconnect does for account deletion, makes an
        // ordinary close look like a replaced socket when there is no new one
        // at all. Whoever does that owns this teardown. Presence used to be
        // part of it and was the one thing nobody thought to hand over — a
        // deleted player stayed in the online count until the server was
        // restarted — so it is now read from the registry instead of tracked.
        if (!sockets.unregister(userId, session)) {
            log.info("Stale socket closed: user={} status={} (already reconnected)", userId, status);
            return;
        }

        rateLimiter.forget(userId);
        matchmaking.leave(userId);
        invites.cancelAllFor(userId);
        // Dropping out of a live duel hands the win to the opponent, exactly as
        // quitting does — otherwise pulling the plug would be a free escape.
        // The app reconnects by itself though, so the forfeit is held back for
        // a grace period rather than landing on every flaky-network blip.
        duels.connectionLost(userId);
        duels.stopSpectating(userId);
        // Same teardown for everything 2v2: the team queue, any pending team
        // invite, a formed-but-not-yet-queued team, and a live team duel.
        teamMatchmaking.leave(userId);
        teamInvites.cancelAllFor(userId);
        teams.cancelAllFor(userId);
        teamDuels.connectionLost(userId);
        teamDuels.stopSpectating(userId);
        presence.disconnected(userId);
        users.markSeen(userId);
        log.info("Socket closed: user={} status={}", userId, status);
    }

    /**
     * Hands a request to watch {@code targetUserId} to whichever engine has
     * them, and is the only place that knows both exist.
     *
     * <p>The app asks to watch a person, not a duel, and cannot tell which mode
     * that person is playing: {@code PresenceService} flags them as fighting
     * either way. The choice therefore has to be made here, because neither
     * service can make it — {@link DuelService} is kept ignorant of 2v2
     * entirely, and asking it about a player it has never heard of came back
     * {@code not_in_duel} for a friend who was very much mid-battle.
     *
     * <p>Whichever service is chosen answers the whole request, refusals
     * included, so exactly one error frame is ever sent. The other is only told
     * to drop a watch this caller may still hold with it, which is what keeps a
     * spectator from being registered with both at once and fed two boards.
     */
    private void spectate(long callerId, long targetUserId) {
        if (teamDuels.isPlaying(targetUserId)) {
            duels.stopSpectating(callerId);
            teamDuels.spectate(callerId, targetUserId);
        } else {
            teamDuels.stopSpectating(callerId);
            duels.spectate(callerId, targetUserId);
        }
    }

    private String text(Envelope envelope, String field) {
        return envelope.payload() == null ? null : envelope.payload().path(field).asText(null);
    }

    private long longValue(Envelope envelope, String field) {
        return envelope.payload() == null ? 0L : envelope.payload().path(field).asLong();
    }

    /** A missing or unreadable number reads as 0, which the receiver clamps. */
    private double doubleValue(Envelope envelope, String field) {
        return envelope.payload() == null ? 0 : envelope.payload().path(field).asDouble();
    }
}
