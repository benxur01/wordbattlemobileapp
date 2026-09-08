package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
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

/**
 * A friend watching a live duel: read-only, pushed the same frame every
 * spectator gets from the moment they ask to watch until the duel is over.
 * See {@code DuelWebSocketTest} for the two-participant path this borrows its
 * client harness from — this one adds a third socket that never plays a word.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ExtendWith(CancelPendingForfeits.class)
class DuelSpectateTest {

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    private final TestRestTemplate rest = new TestRestTemplate();
    private Client host;
    private Client guest;
    private Client watcher;
    private Client watcherOpponent;

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
        long bId = userId(b);
        String created = call("POST", "/api/friends/requests", a, "{\"userId\":" + bId + "}", String.class);
        long requestId = mapper.readTree(created).get("id").asLong();
        call("POST", "/api/friends/requests/" + requestId + "/accept", b, null, String.class);
    }

    @AfterEach
    void tearDown() throws Exception {
        if (host != null) host.close();
        if (guest != null) guest.close();
        if (watcher != null) watcher.close();
        if (watcherOpponent != null) watcherOpponent.close();
    }

    @Test
    void aFriendWatchingReceivesTheInitialBoardAndThenLiveUpdates() throws Exception {
        String hostToken = login("Duel host");
        String guestToken = login("Duel guest");
        String watcherToken = login("Duel watcher");
        long hostId = userId(hostToken);
        long guestId = userId(guestToken);
        befriend(hostToken, watcherToken);

        host = new Client(hostToken);
        guest = new Client(guestToken);
        watcher = new Client(watcherToken);
        host.await("hello", 5);
        guest.await("hello", 5);
        watcher.await("hello", 5);

        host.send("queue.join", Map.of());
        guest.send("queue.join", Map.of());
        JsonNode hostMatch = host.await("match.found", 10);
        guest.await("match.found", 10);

        watcher.send("duel.spectate", Map.of("userId", hostId));
        JsonNode initial = watcher.await("duel.spectate_state", 5);

        assertThat(initial.path("duelId").asText()).isEqualTo(hostMatch.path("duelId").asText());
        Set<Long> players = Set.of(
                initial.path("playerOne").path("id").asLong(), initial.path("playerTwo").path("id").asLong());
        assertThat(players).containsExactlyInAnyOrder(hostId, guestId);
        int initialChainSize = initial.path("chain").size();

        boolean hostStarts = hostMatch.path("yourTurn").asBoolean();
        Client mover = hostStarts ? host : guest;
        char needed = hostMatch.path("needLetter").asText().charAt(0);
        mover.send("duel.submit", Map.of("word", wordFor(needed)));

        JsonNode update = watcher.await("duel.spectate_state", 5);
        assertThat(update.path("chain").size()).isEqualTo(initialChainSize + 1);
        assertThat(update.path("turnPlayerId").asLong()).isNotEqualTo(initial.path("turnPlayerId").asLong());
    }

    @Test
    void aNonFriendIsRejectedWithNotFriends() throws Exception {
        String hostToken = login("Stranger host");
        String guestToken = login("Stranger guest");
        String watcherToken = login("Stranger watcher");
        long hostId = userId(hostToken);

        host = new Client(hostToken);
        guest = new Client(guestToken);
        watcher = new Client(watcherToken);
        host.await("hello", 5);
        guest.await("hello", 5);
        watcher.await("hello", 5);

        host.send("queue.join", Map.of());
        guest.send("queue.join", Map.of());
        host.await("match.found", 10);
        guest.await("match.found", 10);

        watcher.send("duel.spectate", Map.of("userId", hostId));
        assertThat(watcher.await("error", 5).path("code").asText()).isEqualTo("not_friends");
    }

    @Test
    void watchingSomeoneNotInADuelIsRejectedWithNotInDuel() throws Exception {
        String hostToken = login("Idle host");
        String watcherToken = login("Idle watcher");
        long hostId = userId(hostToken);
        befriend(hostToken, watcherToken);

        host = new Client(hostToken);
        watcher = new Client(watcherToken);
        host.await("hello", 5);
        watcher.await("hello", 5);

        watcher.send("duel.spectate", Map.of("userId", hostId));
        assertThat(watcher.await("error", 5).path("code").asText()).isEqualTo("not_in_duel");
    }

    /**
     * A duel of one's own is not a seat in the stands. Both boards would arrive
     * on the one socket, and the watcher's own turn timer keeps running while
     * they look at somebody else's game.
     */
    @Test
    void aPlayerAlreadyInADuelIsRejectedWithAlreadyInDuel() throws Exception {
        String hostToken = login("Busy watched host");
        String guestToken = login("Busy watched guest");
        String watcherToken = login("Busy watcher");
        String watcherOpponentToken = login("Busy watcher opponent");
        long hostId = userId(hostToken);
        befriend(hostToken, watcherToken);

        host = new Client(hostToken);
        guest = new Client(guestToken);
        host.await("hello", 5);
        guest.await("hello", 5);
        host.send("queue.join", Map.of());
        guest.send("queue.join", Map.of());
        host.await("match.found", 10);
        guest.await("match.found", 10);

        // Queued only once the first pair is out of the queue, so these two are
        // certainly matched with each other.
        watcher = new Client(watcherToken);
        watcherOpponent = new Client(watcherOpponentToken);
        watcher.await("hello", 5);
        watcherOpponent.await("hello", 5);
        watcher.send("queue.join", Map.of());
        watcherOpponent.send("queue.join", Map.of());
        watcher.await("match.found", 10);
        watcherOpponent.await("match.found", 10);

        watcher.send("duel.spectate", Map.of("userId", hostId));
        assertThat(watcher.await("error", 5).path("code").asText()).isEqualTo("already_in_duel");
    }

    @Test
    void theWatcherIsToldWhenTheDuelFinishes() throws Exception {
        String hostToken = login("Finishing host");
        String guestToken = login("Finishing guest");
        String watcherToken = login("Finishing watcher");
        long hostId = userId(hostToken);

        befriend(hostToken, watcherToken);

        host = new Client(hostToken);
        guest = new Client(guestToken);
        watcher = new Client(watcherToken);
        host.await("hello", 5);
        guest.await("hello", 5);
        watcher.await("hello", 5);

        host.send("queue.join", Map.of());
        guest.send("queue.join", Map.of());
        host.await("match.found", 10);
        guest.await("match.found", 10);

        watcher.send("duel.spectate", Map.of("userId", hostId));
        watcher.await("duel.spectate_state", 5);

        guest.send("duel.forfeit", Map.of());

        JsonNode ended = watcher.await("duel.spectate_ended", 5);
        assertThat(ended.path("reason").asText()).isEqualTo("finished");
    }

    /** A word that certainly exists for every starting letter. */
    private static String wordFor(char letter) {
        return switch (letter) {
            case 'a' -> "anchor";
            case 'b' -> "basket";
            case 'c' -> "cinema";
            case 'd' -> "dinner";
            case 'e' -> "engine";
            case 'f' -> "famous";
            case 'g' -> "guitar";
            case 'h' -> "hunter";
            case 'i' -> "island";
            case 'j' -> "jacket";
            case 'k' -> "kitten";
            case 'l' -> "letter";
            case 'm' -> "mirror";
            case 'n' -> "nature";
            case 'o' -> "orange";
            case 'p' -> "pencil";
            case 'q' -> "quiet";
            case 'r' -> "rocket";
            case 's' -> "summer";
            case 't' -> "tunnel";
            case 'u' -> "united";
            case 'v' -> "velvet";
            case 'w' -> "winter";
            case 'x' -> "xylophone";
            case 'y' -> "yellow";
            default -> "zebra";
        };
    }
}
