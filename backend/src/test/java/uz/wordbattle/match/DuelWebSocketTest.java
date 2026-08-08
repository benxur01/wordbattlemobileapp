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
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;

/**
 * Two real clients, one real server: queue up, get paired, have a word refused,
 * play a legal one, and see the duel settle. This is the path the Flutter app
 * takes, so it is worth exercising for real rather than mocking the socket.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DuelWebSocketTest {

    /** A word that certainly exists for every starting letter. */
    private static final Map<Character, String> WORD_FOR = Map.ofEntries(
            Map.entry('a', "anchor"), Map.entry('b', "basket"), Map.entry('c', "cinema"),
            Map.entry('d', "dinner"), Map.entry('e', "engine"), Map.entry('f', "famous"),
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

    private final TestRestTemplate rest = new TestRestTemplate();
    private Client alpha;
    private Client beta;

    /** A connected player: sends frames, and queues everything the server pushes. */
    private class Client extends TextWebSocketHandler {
        private final BlockingQueue<JsonNode> frames = new LinkedBlockingQueue<>();
        private WebSocketSession session;

        Client(String token) throws Exception {
            String url = "ws://localhost:" + port + "/ws?token=" + token;
            session = new StandardWebSocketClient().execute(this, url).get(5, TimeUnit.SECONDS);
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

    @AfterEach
    void tearDown() throws Exception {
        if (alpha != null) alpha.close();
        if (beta != null) beta.close();
    }

    @Test
    void twoPlayersAreMatchedAndTheServerJudgesEveryWord() throws Exception {
        alpha = new Client(login("Alpha"));
        beta = new Client(login("Beta"));

        assertThat(alpha.await("hello", 5).path("rules").path("turnSeconds").asInt()).isEqualTo(15);
        beta.await("hello", 5);

        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());

        JsonNode alphaMatch = alpha.await("match.found", 10);
        JsonNode betaMatch = beta.await("match.found", 10);

        // Same duel, opposite turns, and a real rated game (not the bot).
        assertThat(alphaMatch.path("duelId").asText()).isEqualTo(betaMatch.path("duelId").asText());
        assertThat(alphaMatch.path("yourTurn").asBoolean()).isNotEqualTo(betaMatch.path("yourTurn").asBoolean());
        assertThat(alphaMatch.path("rated").asBoolean()).isTrue();

        boolean alphaStarts = alphaMatch.path("yourTurn").asBoolean();
        Client mover = alphaStarts ? alpha : beta;
        Client waiter = alphaStarts ? beta : alpha;
        char needed = alphaMatch.path("needLetter").asText().charAt(0);

        // A word starting with the wrong letter is refused, and the turn stays put.
        char wrongLetter = needed == 'z' ? 'a' : (char) (needed + 1);
        mover.send("duel.submit", Map.of("word", WORD_FOR.get(wrongLetter)));
        JsonNode rejected = mover.await("duel.rejected", 5);
        assertThat(rejected.path("code").asText()).isEqualTo("wrong_letter");

        // So is a word that is not in the dictionary at all.
        mover.send("duel.submit", Map.of("word", needed + "zzqqx"));
        assertThat(mover.await("duel.rejected", 5).path("code").asText()).isEqualTo("not_a_word");

        // The opponent cannot play out of turn either.
        waiter.send("duel.submit", Map.of("word", WORD_FOR.get(needed)));
        assertThat(waiter.await("duel.rejected", 5).path("code").asText()).isEqualTo("not_your_turn");

        // A legal word is accepted and both sides see the same chain.
        String word = WORD_FOR.get(needed);
        mover.send("duel.submit", Map.of("word", word));

        JsonNode moverState = mover.await("duel.update", 5);
        JsonNode waiterState = waiter.await("duel.update", 5);

        assertThat(moverState.path("yourTurn").asBoolean()).isFalse();
        assertThat(waiterState.path("yourTurn").asBoolean()).isTrue();
        assertThat(moverState.path("yourWords").asInt()).isEqualTo(1);
        assertThat(waiterState.path("opponentWords").asInt()).isEqualTo(1);
        assertThat(waiterState.path("needLetter").asText())
                .isEqualTo(String.valueOf(word.charAt(word.length() - 1)));

        JsonNode lastEntry = moverState.path("chain").get(moverState.path("chain").size() - 1);
        assertThat(lastEntry.path("word").asText()).isEqualTo(word);
        assertThat(lastEntry.path("mine").asBoolean()).isTrue();

        // Quitting hands the win to the opponent and settles both ratings.
        waiter.send("duel.forfeit", Map.of());

        JsonNode winner = mover.await("duel.finished", 5);
        JsonNode loser = waiter.await("duel.finished", 5);

        assertThat(winner.path("result").asText()).isEqualTo("win");
        assertThat(loser.path("result").asText()).isEqualTo("lose");
        assertThat(winner.path("reason").asText()).isEqualTo("forfeit");
        assertThat(winner.path("delta").asInt()).isPositive();
        assertThat(loser.path("delta").asInt()).isNegative();
        assertThat(winner.path("ratingAfter").asInt())
                .isEqualTo(winner.path("ratingBefore").asInt() + winner.path("delta").asInt());
        // The loser is handed three words for the letter they were stuck on.
        assertThat(loser.path("stuckLetter").asText()).isNotEmpty();
        assertThat(loser.path("hints")).hasSize(3);
    }

    @Test
    void aLoneSearchFallsBackToTheBotAndThatDuelIsUnrated() throws Exception {
        alpha = new Client(login("Solo"));
        alpha.await("hello", 5);

        alpha.send("queue.join", Map.of());
        alpha.await("queue.joined", 5);

        // No human turns up, so the bot steps in (bot-fallback-seconds).
        JsonNode match = alpha.await("match.found", 25);
        assertThat(match.path("rated").asBoolean()).isFalse();
        assertThat(match.path("opponent").path("nickname").asText()).isEqualTo("wordbot");
        assertThat(match.path("yourTurn").asBoolean()).isTrue();

        // The bot answers on its own once a legal word is played.
        char needed = match.path("needLetter").asText().charAt(0);
        alpha.send("duel.submit", Map.of("word", WORD_FOR.get(needed)));

        JsonNode afterMine = alpha.await("duel.update", 5);
        assertThat(afterMine.path("yourTurn").asBoolean()).isFalse();

        JsonNode afterBot = alpha.await("duel.update", 8);
        assertThat(afterBot.path("yourTurn").asBoolean()).isTrue();
        assertThat(afterBot.path("opponentWords").asInt()).isEqualTo(1);
    }
}
