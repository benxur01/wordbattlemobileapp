package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.BDDMockito.given;

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
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.lang.NonNull;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;

/**
 * What the players are told when the result cannot be written at all — the
 * database down, or a deadlock the retries never get past.
 *
 * <p>The duel is over either way, and the one thing that must not happen is
 * silence. The app has no timeout of its own: a finish frame that never arrives
 * leaves both of them on a duel screen that will never move again, and the
 * missed-finish backstop has nothing to hand them on their way back in either,
 * because it is filled in by the very step that was skipped.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DuelFinishWithoutAResultTest {

    @MockitoBean
    private MatchResultService results;

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    private final TestRestTemplate rest = new TestRestTemplate();
    private Client alpha;
    private Client beta;

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
        if (alpha != null) alpha.close();
        if (beta != null) beta.close();
    }

    @Test
    void aDuelWhoseResultCannotBeWrittenStillEndsOnBothScreens() throws Exception {
        given(results.record(any(), anyLong(), any()))
                .willThrow(new DataAccessResourceFailureException("the database is not there"));

        alpha = new Client(login("Outage A"));
        beta = new Client(login("Outage B"));
        alpha.await("hello", 5);
        beta.await("hello", 5);

        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());
        JsonNode match = alpha.await("match.found", 10);
        beta.await("match.found", 10);

        boolean alphaStarts = match.path("yourTurn").asBoolean();
        Client quitter = alphaStarts ? alpha : beta;
        Client stayer = alphaStarts ? beta : alpha;
        quitter.send("duel.forfeit", Map.of());

        JsonNode won = stayer.await("duel.finished", 5);
        JsonNode lost = quitter.await("duel.finished", 5);

        assertThat(won.path("result").asText()).isEqualTo("win");
        assertThat(lost.path("result").asText()).isEqualTo("lose");
        assertThat(won.path("reason").asText()).isEqualTo("forfeit");
        // Nothing was written, so nothing moved: a rating change the database
        // refused is one that did not happen, and the screen says so.
        assertThat(won.path("delta").asInt()).isZero();
        assertThat(lost.path("delta").asInt()).isZero();
    }
}
