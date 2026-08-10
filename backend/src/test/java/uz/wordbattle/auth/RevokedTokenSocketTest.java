package uz.wordbattle.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ExecutionException;
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
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.lang.NonNull;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * The other door the same token opens. Everything that matters while the app is
 * running — the duel, the queue, the invites, presence — arrives over the
 * socket and never touches the REST API again, so a sign-out that closed only
 * the REST door would have left the account wide open to whoever held a copy of
 * the token.
 *
 * <p>A real socket against a real port, like the tests in {@code match}: the
 * handshake is the only place a socket's token is ever checked, and MockMvc
 * cannot reach it.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class RevokedTokenSocketTest {

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private UserRepository users;

    @Autowired
    private JwtService jwt;

    private final TestRestTemplate rest = new TestRestTemplate();
    private final List<Client> clients = new ArrayList<>();

    /** A connected player, cut down to what these tests ask of one. */
    private class Client extends TextWebSocketHandler {
        private final BlockingQueue<JsonNode> frames = new LinkedBlockingQueue<>();
        private final WebSocketSession session;

        Client(String token) throws Exception {
            session = new StandardWebSocketClient()
                    .execute(this, "ws://localhost:" + port + "/ws?token=" + token)
                    .get(5, TimeUnit.SECONDS);
            clients.add(this);
        }

        @Override
        protected void handleTextMessage(@NonNull WebSocketSession session, @NonNull TextMessage message)
                throws Exception {
            frames.add(mapper.readTree(message.getPayload()));
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

    @AfterEach
    void tearDown() throws Exception {
        for (Client client : clients) client.close();
        clients.clear();
    }

    @Test
    void aSignedOutTokenCannotOpenASocket() throws Exception {
        String token = login("Socket Sign-out");
        long id = userId(token);

        // It opens one now — otherwise the refusal below would prove nothing.
        new Client(token).await("hello", 5);

        assertThat(call(HttpMethod.POST, "/api/auth/logout", token).getStatusCode())
                .isEqualTo(HttpStatus.NO_CONTENT);

        // The interceptor turns the handshake down, so the upgrade never
        // completes and the client is left holding a failed connection instead
        // of a live socket.
        assertThatThrownBy(() -> new Client(token)).isInstanceOf(ExecutionException.class);

        // And the player is not shut out of their own game: the token their
        // next sign-in hands them opens a socket exactly as before.
        new Client(issueFor(id)).await("hello", 5);
    }

    /**
     * Deletion goes the same way, and this is the hole it closes. The account
     * was already erased everywhere else and its live socket cut, but nothing
     * checked the token at the handshake — so the token left on the phone could
     * open a fresh socket, register itself and be counted online for an account
     * that no longer exists.
     */
    @Test
    void aDeletedAccountsTokenCannotOpenASocketEither() throws Exception {
        String token = login("Socket Deleted");
        new Client(token).await("hello", 5);

        assertThat(call(HttpMethod.DELETE, "/api/users/me", token).getStatusCode())
                .isEqualTo(HttpStatus.NO_CONTENT);

        assertThatThrownBy(() -> new Client(token)).isInstanceOf(ExecutionException.class);
    }

    /** Nothing about that refusal is new: a token that was never valid gets it too. */
    @Test
    void aGarbledTokenCannotOpenASocket() {
        assertThatThrownBy(() -> new Client("not-a-token")).isInstanceOf(ExecutionException.class);
    }

    // --------------------------------------------------------------- helpers

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

    private long userId(String token) throws Exception {
        return mapper.readTree(call(HttpMethod.GET, "/api/users/me", token).getBody())
                .get("id")
                .asLong();
    }

    /** A later sign-in of the same account, as {@code AuthController} does it. */
    private String issueFor(long id) {
        User user = users.findById(id).orElseThrow();
        return jwt.issue(user.getId(), user.getTokenGeneration());
    }

    private ResponseEntity<String> call(HttpMethod method, String path, String token) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setBearerAuth(token);
        return rest.exchange("http://localhost:" + port + path, method, new HttpEntity<>(headers), String.class);
    }
}
