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

        Client(String token) throws Exception {
            this.token = token;
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

    private String login(long telegramId, String name) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        String body = "{\"telegramId\":" + telegramId + ",\"displayName\":\"" + name + "\"}";
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
        String hostToken = login(7101, "Otabek");
        String guestToken = login(7102, "Malika");
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
        String hostToken = login(7103, "Sardor");
        String guestToken = login(7104, "Nodira");
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

    @Test
    void strangersCannotBeChallenged() throws Exception {
        String hostToken = login(7105, "Bekzod");
        String strangerToken = login(7106, "Diyor");

        host = new Client(hostToken);
        guest = new Client(strangerToken);
        host.await("hello", 5);
        guest.await("hello", 5);

        host.send("invite.send", Map.of("userId", userId(strangerToken)));

        assertThat(host.await("error", 5).path("code").asText()).isEqualTo("not_friends");
    }
}
