package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
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
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.lang.NonNull;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import uz.wordbattle.ws.SocketRegistry;

/**
 * What a player gets when the app process itself dies mid-duel and is opened
 * again — the case a socket reconnect is not.
 *
 * <p>{@link ReconnectWebSocketTest} covers a socket that drops under an app
 * that keeps running: the duel is still in memory, so the state frame the
 * server sends has only to update it. A killed process has nothing. It never
 * saw {@code match.found} and never will, so that one frame is everything it
 * will ever know about the battle it is in — and until it carried the opponent
 * and whether the duel is rated, the app could not draw a board from it and
 * simply dropped it. The player sat on the lobby while their turn timer ran out
 * and charged them a rated loss they were never shown.
 *
 * <p>The other half is the duel that did <em>not</em> survive the relaunch. A
 * finished duel must come back as a result and never as a board: a board for a
 * battle that is over is one nothing will ever move again.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DuelResumeWebSocketTest {

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

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private DuelService duels;

    @Autowired
    private SocketRegistry sockets;

    private final TestRestTemplate rest = new TestRestTemplate();
    private final List<Client> clients = new ArrayList<>();

    /** A connected player: sends frames, and queues everything the server pushes. */
    private class Client extends TextWebSocketHandler {
        private final BlockingQueue<JsonNode> frames = new LinkedBlockingQueue<>();
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

    private long userId(String token) throws Exception {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        String body = rest.exchange(
                        "http://localhost:" + port + "/api/users/me",
                        HttpMethod.GET,
                        new HttpEntity<>(headers),
                        String.class)
                .getBody();
        return mapper.readTree(body).get("id").asLong();
    }

    /** Two players, queued and paired. Returns the first one's `match.found`. */
    private JsonNode pair(Client one, Client two) throws Exception {
        one.await("hello", 5);
        two.await("hello", 5);
        one.send("queue.join", Map.of());
        two.send("queue.join", Map.of());
        JsonNode match = one.await("match.found", 10);
        two.await("match.found", 10);
        return match;
    }

    /**
     * Blocks until the server has noticed a socket go. Anything that depends on
     * a player being offline — a result being kept for their return rather than
     * written to a socket that is already closing — races the close callback
     * otherwise, and the test would be deciding a real ordering by luck.
     */
    private void awaitDisconnect(long userId) throws Exception {
        for (int attempt = 0; attempt < 100 && sockets.isConnected(userId); attempt++) {
            Thread.sleep(50);
        }
        assertThat(sockets.isConnected(userId)).isFalse();
    }

    @AfterEach
    void tearDown() throws Exception {
        for (Client client : clients) client.close();
        clients.clear();
    }

    @Test
    void aRelaunchedAppIsHandedEverythingTheBoardIsDrawnFrom() throws Exception {
        String alphaToken = login("Killed A");
        String betaToken = login("Killed B");
        Client alpha = new Client(alphaToken);
        Client beta = new Client(betaToken);

        JsonNode match = pair(alpha, beta);
        String duelId = match.path("duelId").asText();
        boolean alphaStarts = match.path("yourTurn").asBoolean();

        Client mover = alphaStarts ? alpha : beta;
        String moverName = alphaStarts ? "Killed A" : "Killed B";
        long moverId = userId(alphaStarts ? alphaToken : betaToken);
        Client doomed = alphaStarts ? beta : alpha;
        String doomedToken = alphaStarts ? betaToken : alphaToken;

        // One word, so there is a chain to come back to and the turn is sitting
        // with the player whose app is about to die.
        String opening = WORD_FOR.get(match.path("needLetter").asText().charAt(0));
        mover.send("duel.submit", Map.of("word", opening));
        mover.await("duel.update", 5);
        doomed.await("duel.update", 5);

        // Android reclaimed the memory, or the player swiped the app away. The
        // process that opens next remembers nothing at all — not the duel, not
        // the opponent, not whose turn it is.
        doomed.close();
        Client relaunched = new Client(doomedToken);
        relaunched.await("hello", 5);

        JsonNode board = relaunched.await("duel.update", 5);

        // Every value the duel screen draws has to be in this one frame, since
        // it is the only one this process will ever get about the battle.
        assertThat(board.path("duelId").asText()).isEqualTo(duelId);
        assertThat(board.path("opponent").path("id").asLong()).isEqualTo(moverId);
        assertThat(board.path("opponent").path("displayName").asText()).isEqualTo(moverName);
        assertThat(board.path("rated").asBoolean()).isTrue();
        assertThat(board.path("yourTurn").asBoolean()).isTrue();
        assertThat(board.path("needLetter").asText()).isNotEmpty();
        assertThat(board.path("turnSeconds").asInt()).isPositive();
        assertThat(board.path("opponentWords").asInt()).isEqualTo(1);

        // The clock is what is left of the turn, not a fresh one: the server's
        // timer has been running the whole time the app was being reopened, and
        // it is the timer that ends the duel.
        int turnMillis = board.path("turnSeconds").asInt() * 1000;
        assertThat(board.path("timeLeftMs").asInt()).isPositive().isLessThanOrEqualTo(turnMillis);

        JsonNode lastEntry = board.path("chain").get(board.path("chain").size() - 1);
        assertThat(lastEntry.path("word").asText()).isEqualTo(opening);
        assertThat(lastEntry.path("mine").asBoolean()).isFalse();

        // And it is a live board rather than a picture of one: the word the
        // returning player types lands, and their opponent sees it.
        String reply = WORD_FOR.get(opening.charAt(opening.length() - 1));
        assertThat(reply).isNotEqualTo(opening);
        relaunched.send("duel.submit", Map.of("word", reply));
        assertThat(relaunched.await("duel.update", 5).path("yourWords").asInt()).isEqualTo(1);
        assertThat(mover.await("duel.update", 5).path("opponentWords").asInt()).isEqualTo(1);
    }

    @Test
    void aDuelThatEndedWhileTheAppWasGoneComesBackAsAResultAndNotABoard() throws Exception {
        String stayingToken = login("Ended A");
        String killedToken = login("Ended B");
        Client staying = new Client(stayingToken);
        Client killed = new Client(killedToken);

        JsonNode match = pair(staying, killed);
        String duelId = match.path("duelId").asText();
        long killedId = userId(killedToken);
        long stayingId = userId(stayingToken);

        // The app dies, and while it is gone the opponent walks out of the
        // battle — which hands it to the player who is not there to see it.
        // (The same thing happens on its own once the disconnect grace runs
        // out; ReconnectWebSocketTest times that path.)
        killed.close();
        awaitDisconnect(killedId);

        // Through the service rather than the socket, and waiting: a result is
        // settled on a pool thread behind a database transaction, so a forfeit
        // sent as a frame can still be in flight when the app is reopened —
        // and the reconnect would then look for a result that had not been put
        // aside yet. Waiting here is the test's business, not the app's; the
        // player who really relaunches inside that window is left on the lobby,
        // which is a smaller and separate problem than the one under test.
        duels.forfeitAndAwaitSettlement(stayingId);

        Client relaunched = new Client(killedToken);
        relaunched.await("hello", 5);

        JsonNode won = relaunched.await("duel.finished", 5);
        assertThat(won.path("duelId").asText()).isEqualTo(duelId);
        assertThat(won.path("result").asText()).isEqualTo("win");

        // No board with it. A relaunched app now raises a duel screen from any
        // state frame it is given, so a state frame for a battle that is over
        // would strand it on a board nothing will ever move again.
        relaunched.expectNothing("duel.update", 2);
    }

    @Test
    void aDuelThatEndsUnderTheReconnectSendsNoBoardBehindItsResult() throws Exception {
        String quitterToken = login("Race A");
        String returningToken = login("Race B");
        Client quitter = new Client(quitterToken);
        Client returning = new Client(returningToken);

        pair(quitter, returning);
        long returningId = userId(returningToken);

        // The interleaving the reconnect path cannot rule out on its own: a
        // socket thread finds the duel in the live registry and is on its way to
        // send its state when the duel ends underneath it. Holding the session
        // from before the finish is the same thing that thread is holding.
        DuelSession session = duels.duelOf(returningId).orElseThrow();
        quitter.send("duel.forfeit", Map.of());
        returning.await("duel.finished", 5);

        duels.sendState(session, returningId);

        // Nothing may come out of that. The result is the last word a duel has,
        // and a board arriving after it would put the app back on a battle it
        // has already been told the end of — with no timer left to move it and
        // no frame ever coming to take it off again.
        returning.expectNothing("duel.update", 2);
    }
}
