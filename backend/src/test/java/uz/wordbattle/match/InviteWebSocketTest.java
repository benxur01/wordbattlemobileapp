package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.lang.NonNull;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketHttpHeaders;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;

/**
 * The friend-challenge path: "Jang" on the friends screen, the incoming
 * challenge sheet, and what happens when it is declined or the challenger is
 * not a friend at all.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class InviteWebSocketTest {

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    private final TestRestTemplate rest = new TestRestTemplate();
    private Client host;
    private Client guest;

    private class Client extends TextWebSocketHandler {
        private final BlockingQueue<JsonNode> frames = new LinkedBlockingQueue<>();
        private final String token;
        private WebSocketSession session;

        /**
         * Refuses every challenge from inside the frame callback, before the
         * queue above is even read. Nothing a player does is this quick, but a
         * scripted client is, and that is what caught the ordering below.
         */
        private volatile boolean declineOnSight;

        Client(String token) throws Exception {
            this.token = token;
            session = new StandardWebSocketClient()
                    .execute(this, "ws://localhost:" + port + "/ws?token=" + token)
                    .get(5, TimeUnit.SECONDS);
        }

        @Override
        protected void handleTextMessage(@NonNull WebSocketSession session, @NonNull TextMessage message)
                throws Exception {
            JsonNode frame = mapper.readTree(message.getPayload());
            frames.add(frame);
            if (declineOnSight && "invite.incoming".equals(frame.path("type").asText())) {
                send("invite.decline", Map.of("inviteId", frame.path("payload").path("inviteId").asText()));
            }
        }

        void send(String type, Map<String, Object> payload) throws Exception {
            session.sendMessage(new TextMessage(mapper.writeValueAsString(Map.of("type", type, "payload", payload))));
        }

        JsonNode await(String type, int seconds) throws Exception {
            long deadline = System.currentTimeMillis() + seconds * 1000L;
            while (System.currentTimeMillis() < deadline) {
                JsonNode frame = frames.poll(deadline - System.currentTimeMillis(), TimeUnit.MILLISECONDS);
                if (frame == null) break;
                if (type.equals(frame.path("type").asText())) return frame.path("payload");
            }
            throw new AssertionError("No '" + type + "' frame arrived within " + seconds + "s");
        }

        /**
         * The next whole frame of a family, type included and in the order it
         * came off the wire. {@link #await} throws its way past everything it
         * was not asked for, which is the wrong instrument when the order of
         * two frames is the thing under test.
         */
        JsonNode awaitFrameOfFamily(String prefix, int seconds) throws Exception {
            long deadline = System.currentTimeMillis() + seconds * 1000L;
            while (System.currentTimeMillis() < deadline) {
                JsonNode frame = frames.poll(deadline - System.currentTimeMillis(), TimeUnit.MILLISECONDS);
                if (frame == null) break;
                if (frame.path("type").asText().startsWith(prefix)) return frame;
            }
            throw new AssertionError("No '" + prefix + "' frame arrived within " + seconds + "s");
        }

        void close() throws Exception {
            if (session != null && session.isOpen()) session.close();
        }
    }

    private String login(String name) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        String body = "{\"displayName\":\"" + name + "\"}";
        String response = rest.postForObject(
                "http://localhost:" + port + "/api/auth/dev", new HttpEntity<>(body, headers), String.class);
        try {
            return mapper.readTree(response).get("token").asText();
        } catch (Exception e) {
            throw new IllegalStateException("Dev login failed: " + response, e);
        }
    }

    private <T> T call(String method, String path, String token, String body, Class<T> type) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setBearerAuth(token);
        return rest.exchange(
                        "http://localhost:" + port + path,
                        org.springframework.http.HttpMethod.valueOf(method),
                        new HttpEntity<>(body, headers),
                        type)
                .getBody();
    }

    private long userId(String token) throws Exception {
        return mapper.readTree(call("GET", "/api/users/me", token, null, String.class)).get("id").asLong();
    }

    /** Makes the two accounts friends through the REST API. */
    private void befriend(String a, String b) throws Exception {
        long bId = userId(b);
        String created = call("POST", "/api/friends/requests", a, "{\"userId\":" + bId + "}", String.class);
        long requestId = mapper.readTree(created).get("id").asLong();
        call("POST", "/api/friends/requests/" + requestId + "/accept", b, null, String.class);
    }

    @AfterEach
    void tearDown() throws Exception {
        if (host != null) host.close();
        if (guest != null) guest.close();
    }

    @Test
    void aFriendChallengeStartsADuelWhenAccepted() throws Exception {
        String hostToken = login("Otabek");
        String guestToken = login("Malika");
        call("PUT", "/api/users/me/nickname", hostToken, "{\"nickname\":\"otabek_z1\"}", String.class);
        call("PUT", "/api/users/me/nickname", guestToken, "{\"nickname\":\"malika_x1\"}", String.class);
        befriend(hostToken, guestToken);

        host = new Client(hostToken);
        guest = new Client(guestToken);
        host.await("hello", 5);
        guest.await("hello", 5);

        host.send("invite.send", Map.of("userId", userId(guestToken)));

        JsonNode sent = host.await("invite.sent", 5);
        JsonNode incoming = guest.await("invite.incoming", 5);

        assertThat(incoming.path("inviteId").asText()).isEqualTo(sent.path("inviteId").asText());
        assertThat(incoming.path("from").path("nickname").asText()).isEqualTo("otabek_z1");
        assertThat(incoming.path("expiresInSeconds").asInt()).isEqualTo(12);

        guest.send("invite.accept", Map.of("inviteId", incoming.path("inviteId").asText()));

        JsonNode hostMatch = host.await("match.found", 5);
        JsonNode guestMatch = guest.await("match.found", 5);

        assertThat(hostMatch.path("duelId").asText()).isEqualTo(guestMatch.path("duelId").asText());
        assertThat(hostMatch.path("rated").asBoolean()).isTrue();
        // The challenger moves first.
        assertThat(hostMatch.path("yourTurn").asBoolean()).isTrue();
        assertThat(guestMatch.path("opponent").path("nickname").asText()).isEqualTo("otabek_z1");
    }

    @Test
    void decliningTellsTheChallengerAndStartsNothing() throws Exception {
        String hostToken = login("Sardor");
        String guestToken = login("Nodira");
        call("PUT", "/api/users/me/nickname", hostToken, "{\"nickname\":\"sardor_e1\"}", String.class);
        call("PUT", "/api/users/me/nickname", guestToken, "{\"nickname\":\"nodira_w1\"}", String.class);
        befriend(hostToken, guestToken);

        host = new Client(hostToken);
        guest = new Client(guestToken);
        host.await("hello", 5);
        guest.await("hello", 5);

        host.send("invite.send", Map.of("userId", userId(guestToken)));
        String inviteId = guest.await("invite.incoming", 5).path("inviteId").asText();

        guest.send("invite.decline", Map.of("inviteId", inviteId));

        assertThat(host.await("invite.declined", 5).path("inviteId").asText()).isEqualTo(inviteId);
    }

    /**
     * The challenger has to hear that the invite went out before it hears the
     * answer to it. Live, it did not: a scripted client that refused the moment
     * the challenge landed got its {@code invite.declined} home first, and the
     * challenger was told about a refusal to an invite it had never been told
     * it had sent. The server was notifying the receiver first and then loading
     * the receiver's profile for the sender's frame, and the refusal came back
     * through that gap — two different sockets, so nothing ordered them.
     *
     * <p>It matters because the app opens its "waiting for X" screen on
     * {@code invite.sent}: arriving second, that frame either never opened the
     * screen at all or opened it after the one thing that would have closed it
     * had already been handled, leaving it up with nothing left to dismiss it.
     *
     * <p>Twenty rounds because it is a race and one round proves nothing —
     * written the wrong way round the loser turns up within a few. Written the
     * right way round it cannot happen at all: the receiver cannot answer a
     * frame that has not been written yet, and the two frames share the
     * challenger's socket, which keeps the order they were written in.
     */
    @Test
    void theChallengerHearsTheInviteWentOutBeforeItHearsTheRefusal() throws Exception {
        String hostToken = login("Rustam");
        String guestToken = login("Gulnora");
        call("PUT", "/api/users/me/nickname", hostToken, "{\"nickname\":\"rustam_t1\"}", String.class);
        call("PUT", "/api/users/me/nickname", guestToken, "{\"nickname\":\"gulnor_t1\"}", String.class);
        befriend(hostToken, guestToken);
        long guestId = userId(guestToken);

        host = new Client(hostToken);
        guest = new Client(guestToken);
        host.await("hello", 5);
        guest.await("hello", 5);
        guest.declineOnSight = true;

        for (int round = 1; round <= 20; round++) {
            host.send("invite.send", Map.of("userId", guestId));

            JsonNode first = host.awaitFrameOfFamily("invite.", 5);
            JsonNode second = host.awaitFrameOfFamily("invite.", 5);

            assertThat(first.path("type").asText()).as("round %d, first frame", round).isEqualTo("invite.sent");
            assertThat(second.path("type").asText()).as("round %d, second frame", round).isEqualTo("invite.declined");
            // The same invite throughout: a refusal for a different one would
            // satisfy the order above and mean nothing.
            assertThat(second.path("payload").path("inviteId").asText())
                    .as("round %d", round)
                    .isEqualTo(first.path("payload").path("inviteId").asText());
        }
    }

    /**
     * An invite outlives the moment it was sent, so the challenger can be
     * pulled into a duel by matchmaking while it waits. Accepting used to start
     * a second duel for them regardless — and because a player maps to exactly
     * one duel, whichever finished first deregistered the other, leaving that
     * player on a duel screen where every word came back "no active duel".
     */
    @Test
    void anInviteCannotStartASecondDuelForAChallengerWhoIsAlreadyPlaying() throws Exception {
        String hostToken = login("Jahongir");
        String guestToken = login("Zilola");
        String thirdToken = login("Kamola");
        call("PUT", "/api/users/me/nickname", hostToken, "{\"nickname\":\"jahon_q1\"}", String.class);
        call("PUT", "/api/users/me/nickname", guestToken, "{\"nickname\":\"zilola_q1\"}", String.class);
        call("PUT", "/api/users/me/nickname", thirdToken, "{\"nickname\":\"kamola_q1\"}", String.class);
        befriend(hostToken, guestToken);

        host = new Client(hostToken);
        guest = new Client(guestToken);
        Client third = new Client(thirdToken);
        try {
            host.await("hello", 5);
            guest.await("hello", 5);
            third.await("hello", 5);

            host.send("invite.send", Map.of("userId", userId(guestToken)));
            String inviteId = guest.await("invite.incoming", 5).path("inviteId").asText();

            // Both are fresh accounts on 1200, so the queue pairs them at once.
            third.send("queue.join", Map.of());
            host.send("queue.join", Map.of());
            host.await("match.found", 10);

            guest.send("invite.accept", Map.of("inviteId", inviteId));

            assertThat(guest.await("error", 5).path("code").asText()).isEqualTo("opponent_busy");
        } finally {
            third.close();
        }
    }

    /** A player mid-duel should not be able to open a second one either. */
    @Test
    void aPlayerAlreadyInADuelCannotSendAnInvite() throws Exception {
        String hostToken = login("Ulugbek");
        String guestToken = login("Sevara");
        String thirdToken = login("Dilnoza");
        call("PUT", "/api/users/me/nickname", hostToken, "{\"nickname\":\"ulugb_r1\"}", String.class);
        call("PUT", "/api/users/me/nickname", guestToken, "{\"nickname\":\"sevara_r1\"}", String.class);
        call("PUT", "/api/users/me/nickname", thirdToken, "{\"nickname\":\"dilnoz_r1\"}", String.class);
        befriend(hostToken, guestToken);

        host = new Client(hostToken);
        guest = new Client(guestToken);
        Client third = new Client(thirdToken);
        try {
            host.await("hello", 5);
            guest.await("hello", 5);
            third.await("hello", 5);

            third.send("queue.join", Map.of());
            host.send("queue.join", Map.of());
            host.await("match.found", 10);

            host.send("invite.send", Map.of("userId", userId(guestToken)));

            assertThat(host.await("error", 5).path("code").asText()).isEqualTo("already_in_duel");
        } finally {
            third.close();
        }
    }

    /**
     * The app authenticates the socket with a header so the token stays out of
     * proxy access logs; the query-string form remains for browsers.
     */
    @Test
    void theHandshakeAcceptsTheTokenInAnAuthorizationHeader() throws Exception {
        String token = login("Aziza");
        BlockingQueue<JsonNode> frames = new LinkedBlockingQueue<>();
        WebSocketHttpHeaders headers = new WebSocketHttpHeaders();
        headers.add("Authorization", "Bearer " + token);

        WebSocketSession session = new StandardWebSocketClient()
                .execute(
                        new TextWebSocketHandler() {
                            @Override
                            protected void handleTextMessage(
                                    @NonNull WebSocketSession session, @NonNull TextMessage message) throws Exception {
                                frames.add(mapper.readTree(message.getPayload()));
                            }
                        },
                        headers,
                        java.net.URI.create("ws://localhost:" + port + "/ws"))
                .get(5, TimeUnit.SECONDS);
        try {
            JsonNode frame = frames.poll(5, TimeUnit.SECONDS);
            assertThat(frame).isNotNull();
            assertThat(frame.path("type").asText()).isEqualTo("hello");
        } finally {
            session.close();
        }
    }

    @Test
    void strangersCannotBeChallenged() throws Exception {
        String hostToken = login("Bekzod");
        String strangerToken = login("Diyor");

        host = new Client(hostToken);
        guest = new Client(strangerToken);
        host.await("hello", 5);
        guest.await("hello", 5);

        host.send("invite.send", Map.of("userId", userId(strangerToken)));

        assertThat(host.await("error", 5).path("code").asText()).isEqualTo("not_friends");
    }
}
