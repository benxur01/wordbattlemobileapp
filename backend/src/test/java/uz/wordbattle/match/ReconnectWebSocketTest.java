package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.CountDownLatch;
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
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.lang.NonNull;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;

/**
 * What happens to a live duel when the socket goes away — the thing phones do
 * constantly: a tunnel, a WiFi-to-cellular handoff, Android killing the app.
 *
 * <p>Three scenarios, all of them real: a drop the player recovers from inside
 * the grace period (the duel has to survive, board and all), a drop they never
 * recover from (the opponent has to be handed the win), and the reconnect race
 * — a second socket arriving before the first one's close callback has run,
 * which must not let the dying socket tear down the live session's duel.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ReconnectWebSocketTest {

    /** A word that certainly exists for every starting letter. */
    private static final Map<Character, String> WORD_FOR = Map.ofEntries(
            Map.entry('a', "anchor"), Map.entry('b', "basket"), Map.entry('c', "cinema"),
            Map.entry('d', "dinner"), Map.entry('e', "energy"), Map.entry('f', "famous"),
            Map.entry('g', "guitar"), Map.entry('h', "hunter"), Map.entry('i', "island"),
            Map.entry('j', "jacket"), Map.entry('k', "kitten"), Map.entry('l', "letter"),
            Map.entry('m', "mirror"), Map.entry('n', "nature"), Map.entry('o', "orange"),
            Map.entry('p', "pencil"), Map.entry('q', "quiet"), Map.entry('r', "rocket"),
            Map.entry('s', "summer"), Map.entry('t', "tunnel"), Map.entry('u', "united"),
            Map.entry('v', "velvet"), Map.entry('w', "winter"), Map.entry('x', "xylophone"),
            Map.entry('y', "yellow"), Map.entry('z', "zebra"));

    /** Long enough to be sure the grace period has come and gone. */
    private static final int PAST_THE_GRACE_PERIOD = (int) DuelService.DISCONNECT_GRACE_SECONDS + 2;

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    private final TestRestTemplate rest = new TestRestTemplate();
    private final List<Client> clients = new ArrayList<>();

    /** A connected player: sends frames, and queues everything the server pushes. */
    private class Client extends TextWebSocketHandler {
        private final BlockingQueue<JsonNode> frames = new LinkedBlockingQueue<>();
        private final CountDownLatch closed = new CountDownLatch(1);
        private WebSocketSession session;

        Client(String token) throws Exception {
            String url = "ws://localhost:" + port + "/ws?token=" + token;
            session = new StandardWebSocketClient().execute(this, url).get(5, TimeUnit.SECONDS);
            clients.add(this);
        }

        @Override
        protected void handleTextMessage(@NonNull WebSocketSession session, @NonNull TextMessage message)
                throws Exception {
            frames.add(mapper.readTree(message.getPayload()));
        }

        @Override
        public void afterConnectionClosed(@NonNull WebSocketSession session, @NonNull CloseStatus status) {
            closed.countDown();
        }

        void send(String type, Map<String, Object> payload) throws Exception {
            String json = mapper.writeValueAsString(Map.of("type", type, "payload", payload));
            session.sendMessage(new TextMessage(json));
        }

        /** Waits for the next frame of a given type, ignoring anything else. */
        JsonNode await(String type, int seconds) throws Exception {
            long deadline = System.currentTimeMillis() + seconds * 1000L;
            while (System.currentTimeMillis() < deadline) {
                JsonNode frame = frames.poll(deadline - System.currentTimeMillis(), TimeUnit.MILLISECONDS);
                if (frame == null) break;
                if (type.equals(frame.path("type").asText())) return frame.path("payload");
            }
            throw new AssertionError("No '" + type + "' frame arrived within " + seconds + "s");
        }

        /** The opposite: fails if such a frame turns up inside the window. */
        void expectNothing(String type, int seconds) throws Exception {
            long deadline = System.currentTimeMillis() + seconds * 1000L;
            while (System.currentTimeMillis() < deadline) {
                JsonNode frame = frames.poll(deadline - System.currentTimeMillis(), TimeUnit.MILLISECONDS);
                if (frame == null) return;
                if (type.equals(frame.path("type").asText())) {
                    throw new AssertionError("Unexpected '" + type + "' frame: " + frame);
                }
            }
        }

        /** True when the server (or we) hung up within the window. */
        boolean awaitClose(int seconds) throws Exception {
            return closed.await(seconds, TimeUnit.SECONDS);
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
                        HttpMethod.valueOf(method),
                        new HttpEntity<>(body, headers),
                        type)
                .getBody();
    }

    private long userId(String token) throws Exception {
        return mapper.readTree(call("GET", "/api/users/me", token, null, String.class)).get("id").asLong();
    }

    /** Makes the two accounts friends through the REST API. */
    private void befriend(String a, String b) throws Exception {
        String created = call("POST", "/api/friends/requests", a, "{\"userId\":" + userId(b) + "}", String.class);
        long requestId = mapper.readTree(created).get("id").asLong();
        call("POST", "/api/friends/requests/" + requestId + "/accept", b, null, String.class);
    }

    /** Two players, queued and paired: the starting point of every case here. */
    private JsonNode pair(Client one, Client two) throws Exception {
        one.await("hello", 5);
        two.await("hello", 5);
        one.send("queue.join", Map.of());
        two.send("queue.join", Map.of());
        JsonNode match = one.await("match.found", 10);
        two.await("match.found", 10);
        return match;
    }

    @AfterEach
    void tearDown() throws Exception {
        for (Client client : clients) client.close();
        clients.clear();
    }

    @Test
    void aReconnectInsideTheGracePeriodKeepsTheDuelAlive() throws Exception {
        String alphaToken = login("Tunnel A");
        String betaToken = login("Tunnel B");
        Client alpha = new Client(alphaToken);
        Client beta = new Client(betaToken);

        JsonNode match = pair(alpha, beta);
        String duelId = match.path("duelId").asText();
        boolean alphaStarts = match.path("yourTurn").asBoolean();
        Client mover = alphaStarts ? alpha : beta;
        Client waiter = alphaStarts ? beta : alpha;
        String waiterToken = alphaStarts ? betaToken : alphaToken;

        // One legal word, so the turn is sitting with the player who is about
        // to lose their connection.
        String opening = WORD_FOR.get(match.path("needLetter").asText().charAt(0));
        mover.send("duel.submit", Map.of("word", opening));
        mover.await("duel.update", 5);
        waiter.await("duel.update", 5);

        // The tunnel: the socket drops, and the app dials again a moment later
        // — the first of its 1s, 2s, 4s, 8s, 15s attempts would land here.
        waiter.close();
        Thread.sleep(2000);
        Client returning = new Client(waiterToken);

        // The duel is still theirs, and the server hands the board straight back.
        returning.await("hello", 5);
        JsonNode resumed = returning.await("duel.update", 5);
        assertThat(resumed.path("duelId").asText()).isEqualTo(duelId);
        assertThat(resumed.path("yourTurn").asBoolean()).isTrue();
        assertThat(resumed.path("timeLeftMs").asInt()).isPositive();
        assertThat(resumed.path("opponentWords").asInt()).isEqualTo(1);

        JsonNode lastEntry = resumed.path("chain").get(resumed.path("chain").size() - 1);
        assertThat(lastEntry.path("word").asText()).isEqualTo(opening);
        assertThat(lastEntry.path("mine").asBoolean()).isFalse();

        // The board is genuinely live: the returning player's move lands.
        String reply = WORD_FOR.get(opening.charAt(opening.length() - 1));
        // A table that sends us back to the word just played would be refused
        // as a repeat, and the duel would look dead for the wrong reason.
        assertThat(reply).isNotEqualTo(opening);
        returning.send("duel.submit", Map.of("word", reply));
        assertThat(returning.await("duel.update", 5).path("yourWords").asInt()).isEqualTo(1);
        assertThat(mover.await("duel.update", 5).path("opponentWords").asInt()).isEqualTo(1);

        // And no forfeit is lurking: the one the drop armed was called off, so
        // nothing ends the duel once the grace period is up either. A finish
        // reaches both sides, so watching one of them is enough.
        mover.expectNothing("duel.finished", PAST_THE_GRACE_PERIOD);
    }

    @Test
    void aDisconnectPastTheGracePeriodForfeitsAndTheReturningPlayerIsTold() throws Exception {
        String alphaToken = login("Gone A");
        String betaToken = login("Gone B");
        Client alpha = new Client(alphaToken);
        Client beta = new Client(betaToken);

        JsonNode match = pair(alpha, beta);
        String duelId = match.path("duelId").asText();

        // Beta really is gone — no reconnect follows.
        beta.close();

        // The opponent is not left staring at a board nobody will play: once
        // the grace period runs out the win is theirs.
        JsonNode won = alpha.await("duel.finished", PAST_THE_GRACE_PERIOD + 3);
        assertThat(won.path("duelId").asText()).isEqualTo(duelId);
        assertThat(won.path("result").asText()).isEqualTo("win");
        assertThat(won.path("reason").asText()).isEqualTo("forfeit");
        assertThat(won.path("delta").asInt()).isPositive();

        // Beta comes back long after the duel died. The finish frame went to a
        // socket that was already closed, so it is handed over now — otherwise
        // the app would sit on a duel screen that never moves again.
        Client returning = new Client(betaToken);
        returning.await("hello", 5);

        JsonNode lost = returning.await("duel.finished", 5);
        assertThat(lost.path("duelId").asText()).isEqualTo(duelId);
        assertThat(lost.path("result").asText()).isEqualTo("lose");
        assertThat(lost.path("reason").asText()).isEqualTo("forfeit");
        assertThat(lost.path("delta").asInt()).isNegative();
        assertThat(lost.path("stuckLetter").asText()).isNotEmpty();

        // Only once: a later reconnect must not drag them back to the result.
        Client again = new Client(betaToken);
        again.await("hello", 5);
        again.expectNothing("duel.finished", 2);
    }

    @Test
    void aSecondSocketForTheSameAccountDoesNotLoseTheDuelToTheOldOne() throws Exception {
        String alphaToken = login("Relaunch A");
        String betaToken = login("Relaunch B");
        // Friends, so alpha's list doubles as a window onto what the server
        // believes about beta's presence.
        befriend(alphaToken, betaToken);
        long betaId = userId(betaToken);

        Client alpha = new Client(alphaToken);
        Client stale = new Client(betaToken);

        JsonNode match = pair(alpha, stale);
        String duelId = match.path("duelId").asText();

        // Android killed the app and the player opened it again: the new socket
        // turns up while the old one is still connected. The server drops the
        // stale one, whose close callback then arrives for a player who is very
        // much online and mid-duel.
        Client relaunched = new Client(betaToken);
        relaunched.await("hello", 5);

        JsonNode resumed = relaunched.await("duel.update", 5);
        assertThat(resumed.path("duelId").asText()).isEqualTo(duelId);
        assertThat(stale.awaitClose(5)).isTrue();

        // Keep the turn timer honest so only a forfeit could end this duel
        // inside the window below.
        char needed = resumed.path("needLetter").asText().charAt(0);
        Client onTurn = resumed.path("yourTurn").asBoolean() ? relaunched : alpha;
        onTurn.send("duel.submit", Map.of("word", WORD_FOR.get(needed)));
        relaunched.await("duel.update", 5);
        alpha.await("duel.update", 5);

        // The close callback has long since run by now, and it must not have
        // marked a very much online player offline or pulled them out of the
        // battle they are in.
        JsonNode friends = mapper.readTree(call("GET", "/api/friends", alphaToken, null, String.class));
        assertThat(friends.get(0).path("user").path("id").asLong()).isEqualTo(betaId);
        assertThat(friends.get(0).path("online").asBoolean()).isTrue();
        assertThat(friends.get(0).path("inBattle").asBoolean()).isTrue();

        // Nor may it take the duel with it — neither there and then, nor when
        // the grace period it would have armed runs out.
        alpha.expectNothing("duel.finished", PAST_THE_GRACE_PERIOD);
    }

    @Test
    void aRelaunchDoesNotCancelTheInvitesTheNewSocketStillHas() throws Exception {
        String hostToken = login("Invite A");
        String guestToken = login("Invite B");
        befriend(hostToken, guestToken);

        Client host = new Client(hostToken);
        Client stale = new Client(guestToken);
        host.await("hello", 5);
        stale.await("hello", 5);

        host.send("invite.send", Map.of("userId", userId(guestToken)));
        String inviteId = stale.await("invite.incoming", 5).path("inviteId").asText();
        host.await("invite.sent", 5);

        // Same race as above, on the other thing the close callback tears down:
        // the guest's app is relaunched while the challenge is on their screen.
        Client relaunched = new Client(guestToken);
        relaunched.await("hello", 5);
        assertThat(stale.awaitClose(5)).isTrue();

        // The dying socket must not cancel a challenge its owner is still there
        // to answer — the challenger would watch it expire for no reason.
        host.expectNothing("invite.expired", 2);

        // And it really is still there to be taken up.
        relaunched.send("invite.accept", Map.of("inviteId", inviteId));
        assertThat(relaunched.await("match.found", 5).path("duelId").asText())
                .isEqualTo(host.await("match.found", 5).path("duelId").asText());
    }
}
