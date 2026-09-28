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
import org.junit.jupiter.api.extension.ExtendWith;
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

/**
 * What a block does once two players are live: the duel they are already in
 * goes quiet between them, and nothing new can bring them together — not a
 * challenge, not a team invite, not the queue.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ExtendWith(CancelPendingForfeits.class)
class BlockedPlayersSocketTest {

    /** Longer than the 400ms both engines hold chat and reactions apart by. */
    private static final long PAST_SOCIAL_THROTTLE_MS = 450;

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private DuelService duels;

    @Autowired
    private TeamDuelService teamDuels;

    private final TestRestTemplate rest = new TestRestTemplate();
    private final List<Client> clients = new ArrayList<>();

    private class Client extends TextWebSocketHandler {
        private final BlockingQueue<JsonNode> frames = new LinkedBlockingQueue<>();
        private final WebSocketSession session;
        final String token;
        final long id;

        Client(String name) throws Exception {
            token = login(name);
            id = mapper.readTree(call(HttpMethod.GET, "/api/users/me", token, null).getBody()).get("id").asLong();
            session = new StandardWebSocketClient()
                    .execute(this, "ws://localhost:" + port + "/ws?token=" + token)
                    .get(5, TimeUnit.SECONDS);
            clients.add(this);
            await("hello", 5);
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

        void block(Client other) {
            assertThat(call(HttpMethod.POST, "/api/users/" + other.id + "/block", token, null).getStatusCode())
                    .isEqualTo(HttpStatus.NO_CONTENT);
        }

        void befriend(Client other) throws Exception {
            String created = call(HttpMethod.POST, "/api/friends/requests", token, "{\"userId\":" + other.id + "}")
                    .getBody();
            long requestId = mapper.readTree(created).get("id").asLong();
            call(HttpMethod.POST, "/api/friends/requests/" + requestId + "/accept", other.token, null);
        }
    }

    @AfterEach
    void tearDown() throws Exception {
        for (Client client : clients) {
            if (client.session.isOpen()) client.session.close();
        }
    }

    @Test
    void aBlockPlacedMidDuelSilencesChatAndReactionsBothWays() throws Exception {
        Client alpha = new Client("Loud alpha");
        Client beta = new Client("Quiet beta");
        assertThat(duels.start(alpha.id, beta.id)).isNotNull();
        alpha.await("match.found", 5);
        beta.await("match.found", 5);

        // Delivered while nothing stands between them.
        alpha.send("duel.chat", Map.of("text", "salom"));
        assertThat(beta.await("duel.chat", 5).path("text").asText()).isEqualTo("salom");

        beta.block(alpha);

        Thread.sleep(PAST_SOCIAL_THROTTLE_MS);
        alpha.send("duel.chat", Map.of("text", "hali shu yerdaman"));
        beta.expectNothing("duel.chat", 1);

        Thread.sleep(PAST_SOCIAL_THROTTLE_MS);
        alpha.send("duel.reaction", Map.of("emoji", "😂"));
        beta.expectNothing("duel.reaction", 1);

        // And the blocker is not heard either.
        beta.send("duel.chat", Map.of("text", "xayr"));
        alpha.expectNothing("duel.chat", 1);
    }

    @Test
    void inATeamDuelOnlyThePairABlockStandsBetweenStopsHearingEachOther() throws Exception {
        Client aOne = new Client("Blocking A one");
        Client aTwo = new Client("Blocking A two");
        Client bOne = new Client("Blocking B one");
        Client bTwo = new Client("Blocking B two");
        assertThat(teamDuels.start(aOne.id, aTwo.id, bOne.id, bTwo.id)).isNotNull();
        for (Client client : List.of(aOne, aTwo, bOne, bTwo)) {
            client.await("team_duel.match_found", 5);
        }

        aOne.block(bOne);

        bOne.send("team_duel.chat", Map.of("text", "gl"));
        assertThat(aTwo.await("team_duel.chat", 5).path("playerId").asLong()).isEqualTo(bOne.id);
        assertThat(bTwo.await("team_duel.chat", 5).path("playerId").asLong()).isEqualTo(bOne.id);
        aOne.expectNothing("team_duel.chat", 1);

        aOne.send("team_duel.reaction", Map.of("emoji", "🔥"));
        aTwo.await("team_duel.reaction", 5);
        bTwo.await("team_duel.reaction", 5);
        bOne.expectNothing("team_duel.reaction", 1);
    }

    @Test
    void neitherSideCanChallengeOrTeamUpWithTheOther() throws Exception {
        Client host = new Client("Blocked host");
        Client guest = new Client("Blocking guest");
        host.befriend(guest);
        guest.block(host);

        host.send("invite.send", Map.of("userId", guest.id));
        assertThat(host.await("error", 5).path("code").asText()).isEqualTo("blocked");
        guest.expectNothing("invite.incoming", 1);

        guest.send("invite.send", Map.of("userId", host.id));
        assertThat(guest.await("error", 5).path("code").asText()).isEqualTo("blocked");

        host.send("team_invite.send", Map.of("userId", guest.id));
        assertThat(host.await("error", 5).path("code").asText()).isEqualTo("blocked");
        guest.expectNothing("team_invite.incoming", 1);
    }

    @Test
    void theQueueDoesNotPairTwoPlayersABlockStandsBetween() throws Exception {
        Client first = new Client("Queued first");
        Client second = new Client("Queued second");
        first.block(second);

        // Level ratings, so nothing but the block keeps these two apart.
        first.send("queue.join", Map.of());
        first.await("queue.joined", 5);
        second.send("queue.join", Map.of());
        second.await("queue.joined", 5);
        first.expectNothing("match.found", 3);
        second.expectNothing("match.found", 1);

        // Somebody else is still a fair opponent for either of them.
        Client third = new Client("Queued third");
        third.send("queue.join", Map.of());
        long opponent = third.await("match.found", 5).path("opponent").path("id").asLong();
        assertThat(opponent).isIn(first.id, second.id);
    }

    // --------------------------------------------------------------- helpers

    private String login(String name) throws Exception {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        String response = rest.postForObject(
                "http://localhost:" + port + "/api/auth/dev",
                new HttpEntity<>("{\"displayName\":\"" + name + "\"}", headers),
                String.class);
        return mapper.readTree(response).get("token").asText();
    }

    private ResponseEntity<String> call(HttpMethod method, String path, String token, String body) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setBearerAuth(token);
        return rest.exchange("http://localhost:" + port + path, method, new HttpEntity<>(body, headers), String.class);
    }
}
