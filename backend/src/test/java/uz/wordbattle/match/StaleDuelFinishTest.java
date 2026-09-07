package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.BDDMockito.given;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
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
import org.springframework.http.MediaType;
import org.springframework.lang.NonNull;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.dictionary.DictionaryService;

/**
 * The result of a duel that arrives after its player has started another one.
 *
 * <p>Nothing exotic gets you here: backing out of a battle forfeits it, the app
 * leaves the screen without waiting, and the result is written to the database
 * before anybody is told — all of which takes long enough for the player to have
 * searched again and been paired. The finish frame for the duel they walked out
 * of then went down the socket they are playing the new one on, and the app,
 * which had no way to tell one duel's frames from another's, threw the live
 * board away and showed a lose screen. Their new opponent was left playing
 * somebody who had gone quiet for good.
 *
 * <p>The settlement is held mid-transaction here rather than raced against, so
 * the frame really does come out behind the second duel every time.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class StaleDuelFinishTest {

    /** An everyday bot, whose pool is only ever borrowed here for a legal word. */
    private static final double EVERYDAY_BOT = 600;

    @MockitoBean
    private MatchResultService results;

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private DictionaryService dictionary;

    @Autowired
    private AppProperties props;

    /** Held closed until the second duel is under way. */
    private final CountDownLatch settlementReached = new CountDownLatch(1);
    private final CountDownLatch releaseSettlement = new CountDownLatch(1);

    private final TestRestTemplate rest = new TestRestTemplate();
    private Client quitter;
    private Client abandoned;
    private Client newRival;

    private class Client extends TextWebSocketHandler {
        private final BlockingQueue<JsonNode> frames = new LinkedBlockingQueue<>();
        private WebSocketSession session;

        Client(String token) throws Exception {
            session = new StandardWebSocketClient()
                    .execute(this, "ws://localhost:" + port + "/ws?token=" + token)
                    .get(5, TimeUnit.SECONDS);
        }

        @Override
        protected void handleTextMessage(@NonNull WebSocketSession session, @NonNull TextMessage message)
                throws Exception {
            frames.add(mapper.readTree(message.getPayload()));
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
        String response = rest.postForObject(
                "http://localhost:" + port + "/api/auth/dev",
                new HttpEntity<>("{\"displayName\":\"" + name + "\"}", headers),
                String.class);
        try {
            return mapper.readTree(response).get("token").asText();
        } catch (Exception e) {
            throw new IllegalStateException("Dev login failed: " + response, e);
        }
    }

    @AfterEach
    void tearDown() throws Exception {
        // Never leave the held settlement holding a pool thread, however the
        // test ended.
        releaseSettlement.countDown();
        if (quitter != null) quitter.close();
        if (abandoned != null) abandoned.close();
        if (newRival != null) newRival.close();
    }

    @Test
    void theResultOfAnAbandonedDuelDoesNotReachAPlayerAlreadyInTheNext() throws Exception {
        given(results.record(any(), anyLong(), any())).willAnswer(invocation -> {
            settlementReached.countDown();
            releaseSettlement.await(10, TimeUnit.SECONDS);
            return MatchResultService.Outcome.unrecorded();
        });

        quitter = new Client(login("Walked out"));
        abandoned = new Client(login("Left behind"));
        newRival = new Client(login("Next opponent"));
        quitter.await("hello", 5);
        abandoned.await("hello", 5);
        newRival.await("hello", 5);

        quitter.send("queue.join", Map.of());
        abandoned.send("queue.join", Map.of());
        String firstDuelId = quitter.await("match.found", 10).path("duelId").asText();
        abandoned.await("match.found", 10);

        // Out of the duel — which the app does without waiting for anything —
        // and the result starts on its way to the database.
        quitter.send("duel.forfeit", Map.of());
        assertThat(settlementReached.await(5, TimeUnit.SECONDS))
                .as("the forfeit never reached a settlement")
                .isTrue();

        // Straight back into the search, and into a second duel, while the
        // first one's result is still in flight.
        quitter.send("queue.join", Map.of());
        newRival.send("queue.join", Map.of());
        JsonNode secondDuel = quitter.await("match.found", 10);
        newRival.await("match.found", 10);
        assertThat(secondDuel.path("duelId").asText()).isNotEqualTo(firstDuelId);

        releaseSettlement.countDown();

        // The player who was left behind is owed their win and gets it: the
        // guard is about who has moved on, not about swallowing results.
        JsonNode won = abandoned.await("duel.finished", 5);
        assertThat(won.path("duelId").asText()).isEqualTo(firstDuelId);
        assertThat(won.path("result").asText()).isEqualTo("win");

        // The one who walked out hears nothing. Their screen is a live board,
        // and this frame is what used to take it away from them.
        quitter.expectNothing("duel.finished", 2);

        // Which it still is — the second duel plays on as if the first had
        // never happened.
        playFirstWordOf(secondDuel);
        assertThat(quitter.await("duel.update", 5).path("duelId").asText())
                .isEqualTo(secondDuel.path("duelId").asText());
        newRival.await("duel.update", 5);
    }

    /** Has whoever holds the opening turn answer the seed word. */
    private void playFirstWordOf(JsonNode match) throws Exception {
        Set<String> used = new HashSet<>(Set.of(match.path("seedWord").asText()));
        String word = dictionary.botMove(
                match.path("needLetter").asText().charAt(0), used, props.duel().minWordLength(), EVERYDAY_BOT);
        assertThat(word).as("no word to answer '%s' with", match.path("needLetter").asText()).isNotNull();
        (match.path("yourTurn").asBoolean() ? quitter : newRival).send("duel.submit", Map.of("word", word));
    }
}
