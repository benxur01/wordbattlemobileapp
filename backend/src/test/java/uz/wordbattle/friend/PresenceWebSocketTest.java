package uz.wordbattle.friend;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
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
 * Who the server believes is online, driven over real sockets: the figure the
 * lobby prints as "HOZIR ONLAYN", and the dot beside a friend's name.
 *
 * <p>Written after the count went wrong on a real phone. One device, one
 * account, nothing else connected — and the number climbed to two and stayed
 * there, with a player who had no socket at all still being counted. Presence
 * was a set of its own, kept in step with the socket registry by hand from the
 * two ends of {@link uz.wordbattle.ws.GameSocketHandler}, and any other route
 * out of the registry never reached it. Deleting an account is such a route:
 * the registry drops the entry itself, so the close callback that follows sees
 * no session under that id and reads it as "this socket was already replaced"
 * — the one branch that returns before presence is touched.
 *
 * <p>So the cases here are the three ways a socket can leave. An ordinary close
 * (the count comes back down), a relaunch where a second socket lands before
 * the first one's close callback (the count must not move at all, and the
 * player must stay online — that is the branch above doing its real job), and
 * the account deletion that started this.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class PresenceWebSocketTest {

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private PresenceService presence;

    private final TestRestTemplate rest = new TestRestTemplate();
    private final List<Client> clients = new ArrayList<>();

    /** A connected player: queues everything the server pushes, and hangs up on request. */
    private class Client extends TextWebSocketHandler {
        private final BlockingQueue<JsonNode> frames = new LinkedBlockingQueue<>();
        private final CountDownLatch closed = new CountDownLatch(1);
        private final WebSocketSession session;

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

        /** True when the server (or we) hung up within the window. */
        boolean awaitClose(int seconds) throws Exception {
            return closed.await(seconds, TimeUnit.SECONDS);
        }

        void close() throws Exception {
            if (session.isOpen()) session.close();
        }
    }

    @AfterEach
    void tearDown() throws Exception {
        for (Client client : clients) client.close();
        clients.clear();
    }

    /**
     * The plain case, and the one that always worked: a player connects, and
     * when their socket goes the server stops counting them. It is here because
     * it pins down the half of the mechanism the failure below is measured
     * against — the close callback really does reach presence when it is the
     * live socket closing, so nothing about session identity is at fault.
     */
    @Test
    void aSocketThatClosesTakesItsPlayerOutOfTheCount() throws Exception {
        int others = settledOnlineCount();
        String token = login("Presence Solo");
        long id = userId(token);

        Client client = new Client(token);
        assertThat(client.await("hello", 5).path("onlineCount").asInt()).isEqualTo(others + 1);
        assertThat(presence.isOnline(id)).isTrue();

        client.close();
        awaitOnlineCount(others);
        assertThat(presence.isOnline(id)).isFalse();

        // And the same account coming back is counted once, not twice.
        Client again = new Client(token);
        assertThat(again.await("hello", 5).path("onlineCount").asInt()).isEqualTo(others + 1);
        assertThat(presence.isOnline(id)).isTrue();
    }

    /**
     * The relaunch race, from presence's side. Android kills the app and the
     * player opens it again, so the new socket registers before the old one's
     * close callback runs. The dying socket must not carry its owner out of the
     * count with it — they are sitting in the lobby looking at that very number
     * — and the count must not double either.
     */
    @Test
    void aRelaunchLeavesThePlayerOnlineAndCountedExactlyOnce() throws Exception {
        int others = settledOnlineCount();
        String token = login("Presence Relaunch");
        long id = userId(token);

        Client stale = new Client(token);
        stale.await("hello", 5);

        Client relaunched = new Client(token);
        assertThat(relaunched.await("hello", 5).path("onlineCount").asInt()).isEqualTo(others + 1);
        assertThat(stale.awaitClose(5)).isTrue();

        // The close callback for the dropped socket runs on the server's own
        // thread, so the assertion is held open long enough for it to have run
        // and done its damage if it were going to.
        assertOnlineCountHolds(others + 1, 1000);
        assertThat(presence.isOnline(id)).isTrue();
    }

    /**
     * The failure from the phone. Deleting the account closes the socket
     * through the registry, which takes the entry out itself — and that is what
     * left the close callback with nothing to recognise. The player is gone,
     * their account is gone, and the count has to say so.
     */
    @Test
    void deletingAnAccountTakesThePlayerOutOfTheCount() throws Exception {
        int others = settledOnlineCount();
        String token = login("Presence Leaving");
        long id = userId(token);

        Client client = new Client(token);
        assertThat(client.await("hello", 5).path("onlineCount").asInt()).isEqualTo(others + 1);

        call("DELETE", "/api/users/me", token, null, String.class);
        assertThat(client.awaitClose(5)).isTrue();

        awaitOnlineCount(others);
        assertThat(presence.isOnline(id)).isFalse();
    }

    // --------------------------------------------------------------- helpers

    /**
     * What the count already stood at before this test connected anything.
     *
     * <p>The whole suite shares one server, and the sockets of the class that
     * ran before this one are closed without waiting for the server to notice,
     * so the figure is read once it has stopped moving rather than the instant
     * we ask. Everything here is then asserted relative to it.
     */
    private int settledOnlineCount() throws Exception {
        int last = presence.onlineCount();
        long deadline = System.currentTimeMillis() + 5000;
        while (System.currentTimeMillis() < deadline) {
            Thread.sleep(200);
            int now = presence.onlineCount();
            if (now == last) return now;
            last = now;
        }
        return last;
    }

    /** Polls: a socket closing is only news to the server a moment later. */
    private void awaitOnlineCount(int expected) throws Exception {
        long deadline = System.currentTimeMillis() + 5000;
        while (System.currentTimeMillis() < deadline) {
            if (presence.onlineCount() == expected) return;
            Thread.sleep(50);
        }
        assertThat(presence.onlineCount()).isEqualTo(expected);
    }

    /** The opposite: the count has to sit still at this value for the window. */
    private void assertOnlineCountHolds(int expected, int millis) throws Exception {
        long deadline = System.currentTimeMillis() + millis;
        while (System.currentTimeMillis() < deadline) {
            assertThat(presence.onlineCount()).isEqualTo(expected);
            Thread.sleep(50);
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
}
