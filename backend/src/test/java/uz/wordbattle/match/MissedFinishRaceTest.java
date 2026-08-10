package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.willAnswer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
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
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import uz.wordbattle.ws.SocketRegistry;

/**
 * The result of a duel that was shelved for a player one instant after that
 * player came back and looked for it.
 *
 * <p>A duel leaves the registries the moment it ends, so a player returning any
 * time after that is not offered a board — they are sent to the missed-finish
 * shelf, once, while their socket is coming up. The settlement puts the result
 * on that shelf, and it decides to do so by reading the socket registry one
 * statement earlier. Nothing holds the two together: the settlement runs on the
 * pool with no monitor held, deliberately, so that a database transaction never
 * has moves and turn timers queued behind it. A pool thread stopped between
 * those two statements for a few milliseconds — a GC pause, a container's CPU
 * quota running out, four other duels wanting the same cores — is enough for the
 * entire reconnect to pass through: the socket registers, the shelf is empty,
 * the player is put on the lobby, and the frame arrives on the shelf afterwards
 * for a return that has already been and gone.
 *
 * <p>What makes that permanent rather than merely late is the two-minute shelf
 * life. The result is only ever collected on a reconnect, and a reconnect later
 * than that throws it away unread — so a player who closes the app for the
 * evening is never told how the duel ended, while the rating it moved was
 * written before any of this ran.
 *
 * <p>Milliseconds are not something a test can schedule, so the stall is made
 * rather than waited for: the settlement is held inside the registry call it
 * would have been preempted after, with the same latch-and-override mechanism
 * {@link StaleDuelFinishTest} holds a settlement mid-transaction with. The
 * registry answers with what it really knew at that moment — the frame could
 * not go, the player was gone — and the reconnect completes before the answer
 * is acted upon, which is exactly the ordering a preempted thread produces.
 *
 * <p>That call is the send itself rather than a reachability check taken before
 * it, because the send is what decides now: it reports whether the frame landed,
 * so a socket that closes between the lookup and the write goes down the shelving
 * path instead of vanishing at DEBUG — see {@link DroppedFinishFrameTest}, which
 * is that gap on its own. The stall sits in the same place either way: the
 * settlement has learned the frame did not go and has not yet shelved it.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class MissedFinishRaceTest {

    /** Spied rather than mocked: every other socket in this test is a real one. */
    @MockitoSpyBean
    private SocketRegistry sockets;

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    /** Closed once the settlement has read the registry and not yet acted on it. */
    private final CountDownLatch settlementAtTheRegistry = new CountDownLatch(1);

    /** Held closed until the reconnect has looked for its result and found none. */
    private final CountDownLatch reconnectHasLooked = new CountDownLatch(1);

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
     * Blocks until the server has noticed a socket go, so that the duel really
     * does end on a player it believes to be away.
     */
    private void awaitDisconnect(long userId) throws Exception {
        for (int attempt = 0; attempt < 100 && sockets.isConnected(userId); attempt++) {
            Thread.sleep(50);
        }
        assertThat(sockets.isConnected(userId)).isFalse();
    }

    @AfterEach
    void tearDown() throws Exception {
        // Never leave the held settlement holding a pool thread, however the
        // test ended.
        reconnectHasLooked.countDown();
        for (Client client : clients) client.close();
        clients.clear();
    }

    @Test
    void aResultShelvedBehindAReconnectStillReachesThePlayer() throws Exception {
        String awayToken = login("Came back early");
        String stayingToken = login("Walked out");
        Client away = new Client(awayToken);
        Client staying = new Client(stayingToken);

        JsonNode match = pair(away, staying);
        String duelId = match.path("duelId").asText();
        long awayId = userId(awayToken);

        // The app dies mid-duel. Everything after this happens while the server
        // has no socket to reach that player on.
        away.close();
        awaitDisconnect(awayId);

        // The settlement is stopped where a busy machine would have stopped it:
        // after it has tried the registry and been told the frame could not go,
        // before it has done anything about that. One call only — the reconnect,
        // and the second look the fix takes, must both see the registry as it
        // really is.
        AtomicBoolean held = new AtomicBoolean();
        willAnswer(invocation -> {
            boolean sent = (boolean) invocation.callRealMethod();
            if (!sent && held.compareAndSet(false, true)) {
                settlementAtTheRegistry.countDown();
                reconnectHasLooked.await(10, TimeUnit.SECONDS);
            }
            return sent;
        })
                .given(sockets)
                .send(eq(awayId), eq("duel.finished"), any());

        // The opponent walks out, which hands the duel to the player who is not
        // there to see it.
        staying.send("duel.forfeit", Map.of());
        assertThat(settlementAtTheRegistry.await(10, TimeUnit.SECONDS))
                .as("the forfeit never reached the registry read")
                .isTrue();

        // And the app is reopened inside that window. It asks for a result the
        // settlement has not shelved yet, is told there is none, and shows the
        // lobby — the reconnect's one and only look.
        Client relaunched = new Client(awayToken);
        relaunched.await("hello", 5);
        relaunched.expectNothing("duel.finished", 1);
        reconnectHasLooked.countDown();

        // The settlement carries on and shelves the result for a return that
        // has already happened. Whether the player is ever told is the whole
        // question: without the second look this frame is written to a shelf
        // nobody will read again, thrown out unopened two minutes later, and a
        // rated duel ends with the rating moved and the player never told.
        JsonNode won = relaunched.await("duel.finished", 5);
        assertThat(won.path("duelId").asText()).isEqualTo(duelId);
        assertThat(won.path("result").asText()).isEqualTo("win");
        assertThat(won.path("reason").asText()).isEqualTo("forfeit");

        // Once, though. Both threads may reach for the same shelved frame, and
        // a result delivered twice would take the player off the lobby and back
        // onto a result screen they had already dismissed.
        relaunched.expectNothing("duel.finished", 1);
    }
}
