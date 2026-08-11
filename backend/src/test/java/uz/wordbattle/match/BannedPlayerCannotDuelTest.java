package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willAnswer;
import static org.mockito.Mockito.mock;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import uz.wordbattle.friend.FriendService;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.SocketRegistry;

/**
 * A banned account plays nobody.
 *
 * <p>A ban is felt at the door — {@code UserRepository.currentFor} refuses the
 * token, so the socket closes and no frame of theirs is read again — and the ban
 * commits before the session is torn down precisely so that the reconnect
 * arriving a second later finds the door already shut. What is left is the frame
 * that was already in flight when the transaction landed: a queue entry being
 * paired on the scheduler's thread, or an invite of theirs somebody else accepts
 * a moment too early. Either would have started a rated duel on an account its
 * owner has just lost — two ratings moved and a match row that should never have
 * existed.
 *
 * <p>So the refusal lives in {@code DuelService.start} as well, where every
 * route into a duel has to pass. Driven through the services here rather than
 * over a socket, because the whole question is what happens when a frame gets
 * through anyway; a banned player has no socket to send one on.
 */
@SpringBootTest
class BannedPlayerCannotDuelTest {

    @Autowired
    private DuelService duels;

    @Autowired
    private MatchmakingService matchmaking;

    @Autowired
    private InviteService invites;

    @Autowired
    private UserService users;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private FriendService friends;

    @Autowired
    private SocketRegistry sockets;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private PlatformTransactionManager transactionManager;

    /** Both slots, and the bot, because a start is refused or it is not. */
    @Test
    void neitherSideOfADuelWillTakeABannedAccount() {
        long banned = users.createDevUser("Banned duellist").getId();
        long rival = users.createDevUser("Banned duellist rival").getId();
        ban(banned);

        assertThat(duels.start(banned, rival)).as("banned player in the first slot").isNull();
        assertThat(duels.start(rival, banned)).as("banned player in the second slot").isNull();
        assertThat(duels.startAgainstBot(banned)).as("banned player against the bot").isNull();

        // A refusal leaves nothing half-registered behind it, on either side —
        // an entry in duelByPlayer with no duel to reach is a player who can
        // never start another one.
        assertThat(duels.duelOf(banned)).isEmpty();
        assertThat(duels.duelOf(rival)).isEmpty();

        // And it really is the ban doing it: lifted, the same call starts the
        // same duel. Without this the three assertions above would still pass
        // for a start that had stopped working altogether.
        unban(banned);
        DuelSession started = duels.start(banned, rival);
        assertThat(started).as("the duel refused for a ban that is no longer there").isNotNull();
        duels.forfeit(rival);
    }

    /**
     * The queue, which is the one path that reaches {@code start} without a
     * frame from either player: the pairing runs on the scheduler, so a ban
     * landing between the last tick and this one is caught nowhere else.
     *
     * <p>What matters is the player who did nothing wrong. Both are dropped from
     * the queue before the start is attempted, so a refusal that was not handled
     * would leave them watching a search screen with nothing looking for them
     * ever again.
     */
    @Test
    void matchmakingPutsTheFreePlayerBackWhenTheStartIsRefused() throws IOException {
        long banned = users.createDevUser("Queued and banned").getId();
        long waiting = users.createDevUser("Queued and waiting").getId();
        connect(banned);
        connect(waiting);
        ban(banned);

        try {
            matchmaking.join(waiting);
            // join() pairs at once rather than waiting for a tick, so this is
            // the pairing itself.
            matchmaking.join(banned);

            assertThat(duels.isPlaying(waiting)).as("a duel against a banned account").isFalse();
            assertThat(duels.isPlaying(banned)).isFalse();
            assertThat(matchmaking.isQueued(waiting))
                    .as("the free player was dropped from the queue and given no duel")
                    .isTrue();
        } finally {
            matchmaking.leave(waiting);
            matchmaking.leave(banned);
            sockets.disconnect(waiting);
            sockets.disconnect(banned);
        }
    }

    /**
     * The invite, which is the other one: it sits around for its whole timeout,
     * and a ban can land anywhere in that window. Accepting it is a frame the
     * banned player's own socket would have to carry, which is why the ban is
     * dropped on them here after the challenge has already gone out — the
     * microsecond in which their frame is in flight and the ban is committing.
     */
    @Test
    void anInviteAcceptedByABannedAccountStartsNothingAndTellsBothSides() throws IOException {
        long host = users.createDevUser("Invite host").getId();
        long banned = users.createDevUser("Invite banned").getId();
        List<JsonNode> hostFrames = connect(host);
        List<JsonNode> bannedFrames = connect(banned);
        befriend(host, banned);

        try {
            invites.send(host, banned);
            String inviteId = payloadOf(hostFrames, "invite.sent").path("inviteId").asText();
            assertThat(inviteId).isNotEmpty();

            ban(banned);
            invites.accept(banned, inviteId);

            assertThat(duels.isPlaying(host)).as("a duel against a banned account").isFalse();
            assertThat(duels.isPlaying(banned)).isFalse();
            // Somebody has to be told, or the challenger waits out a duel that
            // is not coming and the accepter sits on a challenge sheet that
            // will never close.
            assertThat(payloadOf(bannedFrames, "error").path("code").asText()).isEqualTo("duel_unavailable");
            assertThat(payloadOf(hostFrames, "invite.expired").path("inviteId").asText())
                    .isEqualTo(inviteId);
        } finally {
            sockets.disconnect(host);
            sockets.disconnect(banned);
        }
    }

    // --------------------------------------------------------------- helpers

    /** Straight at the column, as the panel's own ban does it. */
    private void ban(long userId) {
        new TransactionTemplate(transactionManager)
                .executeWithoutResult(status -> assertThat(userRepository.ban(userId, Instant.now()))
                        .isEqualTo(1));
    }

    private void unban(long userId) {
        new TransactionTemplate(transactionManager)
                .executeWithoutResult(status -> assertThat(userRepository.unban(userId)).isEqualTo(1));
    }

    private void befriend(long one, long two) {
        friends.accept(two, friends.sendRequest(one, two).getId());
        assertThat(friends.areFriends(one, two)).isTrue();
    }

    /**
     * A stand-in socket that keeps what was written to it. Real ones cannot be
     * used: the two players this test needs are one banned account, whose
     * handshake is refused, and one challenger, who has to be reachable for the
     * invite to be sent at all.
     */
    private List<JsonNode> connect(long userId) throws IOException {
        List<JsonNode> frames = new ArrayList<>();
        WebSocketSession socket = mock(WebSocketSession.class);
        given(socket.isOpen()).willReturn(true);
        given(socket.getId()).willReturn("socket-" + userId);
        willAnswer(invocation -> {
            TextMessage message = invocation.getArgument(0);
            synchronized (frames) {
                frames.add(mapper.readTree(message.getPayload()));
            }
            return null;
        })
                .given(socket)
                .sendMessage(any());
        sockets.register(userId, socket);
        return frames;
    }

    /** The payload of the last frame of this type the socket was sent. */
    private JsonNode payloadOf(List<JsonNode> frames, String type) {
        synchronized (frames) {
            return frames.stream()
                    .filter(frame -> type.equals(frame.path("type").asText()))
                    .reduce((first, second) -> second)
                    .orElseThrow(() -> new AssertionError("No '" + type + "' frame was sent"))
                    .path("payload");
        }
    }
}
