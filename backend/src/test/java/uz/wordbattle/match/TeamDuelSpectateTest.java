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
 * A friend watching a live 2v2 duel — {@code DuelSpectateTest} with four
 * players on the board instead of two, and a fifth socket that never plays a
 * word.
 *
 * <p>The last test here is about a 1v1 duel on purpose. Which engine a
 * {@code duel.spectate} reaches is decided in {@code GameSocketHandler}, from
 * the target's occupancy, so a mistake in that routing would hand a friend in
 * an ordinary duel to the team service and answer {@code not_in_duel} — the
 * very failure this feature exists to fix, turned around.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ExtendWith(CancelPendingForfeits.class)
class TeamDuelSpectateTest {

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    private final TestRestTemplate rest = new TestRestTemplate();
    private Client aOne;
    private Client aTwo;
    private Client bOne;
    private Client bTwo;
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

    /** One account, as the tests need it: a token to act with and the id others name them by. */
    private record Player(String token, long id) {}

    private Player register(String name) throws Exception {
        String token = login(name);
        return new Player(token, userId(token));
    }

    /** The four players {@link #startTeamDuel} put into a duel, and its opening frame. */
    private record Duel(Player aOne, Player aTwo, Player bOne, Player bTwo, JsonNode matchFound) {}

    /**
     * Logs four fresh players in, forms both teams and queues them until they
     * are matched — the same sequence {@code TeamDuelWebSocketTest} spells out.
     * Team A queues first, so it is the session's team A and its member one
     * opens; {@code matchFound} is that player's own announcement.
     */
    private Duel startTeamDuel(String namePrefix) throws Exception {
        Player playerAOne = register(namePrefix + " A one");
        Player playerATwo = register(namePrefix + " A two");
        Player playerBOne = register(namePrefix + " B one");
        Player playerBTwo = register(namePrefix + " B two");

        befriend(playerAOne.token(), playerATwo.token());
        befriend(playerBOne.token(), playerBTwo.token());

        aOne = new Client(playerAOne.token());
        aTwo = new Client(playerATwo.token());
        bOne = new Client(playerBOne.token());
        bTwo = new Client(playerBTwo.token());
        aOne.await("hello", 5);
        aTwo.await("hello", 5);
        bOne.await("hello", 5);
        bTwo.await("hello", 5);

        aOne.send("team_invite.send", Map.of("userId", playerATwo.id()));
        aTwo.send("team_invite.accept",
                Map.of("inviteId", aTwo.await("team_invite.incoming", 5).path("inviteId").asText()));
        aOne.await("team.formed", 5);
        aTwo.await("team.formed", 5);

        bOne.send("team_invite.send", Map.of("userId", playerBTwo.id()));
        bTwo.send("team_invite.accept",
                Map.of("inviteId", bTwo.await("team_invite.incoming", 5).path("inviteId").asText()));
        bOne.await("team.formed", 5);
        bTwo.await("team.formed", 5);

        aOne.send("team.queue.join", Map.of());
        aTwo.await("team.queue.joined", 5);
        bOne.send("team.queue.join", Map.of());
        bTwo.await("team.queue.joined", 5);

        JsonNode matchFound = aOne.await("team_duel.match_found", 10);
        aTwo.await("team_duel.match_found", 10);
        bOne.await("team_duel.match_found", 10);
        bTwo.await("team_duel.match_found", 10);

        return new Duel(playerAOne, playerATwo, playerBOne, playerBTwo, matchFound);
    }

    @AfterEach
    void tearDown() throws Exception {
        if (aOne != null) aOne.close();
        if (aTwo != null) aTwo.close();
        if (bOne != null) bOne.close();
        if (bTwo != null) bTwo.close();
        if (watcher != null) watcher.close();
        if (watcherOpponent != null) watcherOpponent.close();
    }

    @Test
    void aFriendWatchingReceivesTheFourPlayerBoardAndThenLiveUpdates() throws Exception {
        Duel duel = startTeamDuel("Team watched");
        Player fan = register("Team watcher");
        befriend(fan.token(), duel.aOne().token());

        watcher = new Client(fan.token());
        watcher.await("hello", 5);

        watcher.send("duel.spectate", Map.of("userId", duel.aOne().id()));
        JsonNode initial = watcher.await("team_duel.spectate_state", 5);

        assertThat(initial.path("duelId").asText()).isEqualTo(duel.matchFound().path("duelId").asText());
        assertThat(initial.path("teamAOne").path("id").asLong()).isEqualTo(duel.aOne().id());
        assertThat(initial.path("teamATwo").path("id").asLong()).isEqualTo(duel.aTwo().id());
        assertThat(initial.path("teamBOne").path("id").asLong()).isEqualTo(duel.bOne().id());
        assertThat(initial.path("teamBTwo").path("id").asLong()).isEqualTo(duel.bTwo().id());
        assertThat(initial.path("turnPlayerId").asLong()).isEqualTo(duel.aOne().id());
        int initialChainSize = initial.path("chain").size();

        String word = wordFor(initial.path("needLetter").asText().charAt(0));
        aOne.send("team_duel.submit", Map.of("word", word));

        JsonNode update = watcher.await("team_duel.spectate_state", 5);
        assertThat(update.path("chain").size()).isEqualTo(initialChainSize + 1);
        JsonNode played = update.path("chain").get(initialChainSize);
        assertThat(played.path("word").asText()).isEqualTo(word);
        // Named outright rather than reduced to mine/ally: a spectator plays
        // for neither of the two teams.
        assertThat(played.path("playerId").asLong()).isEqualTo(duel.aOne().id());
        assertThat(update.path("teamAOneWords").asInt()).isEqualTo(1);
        // The rotation is A-one, B-one, A-two, B-two.
        assertThat(update.path("turnPlayerId").asLong()).isEqualTo(duel.bOne().id());
    }

    @Test
    void beingAFriendOfAnyOneOfTheFourIsEnoughToWatch() throws Exception {
        Duel duel = startTeamDuel("Team roster");
        Player fan = register("Watcher of the other side");
        // Friends with nobody on the team being asked about — only with an
        // opponent of theirs, on the far side of the same board.
        befriend(fan.token(), duel.bTwo().token());

        watcher = new Client(fan.token());
        watcher.await("hello", 5);

        watcher.send("duel.spectate", Map.of("userId", duel.aOne().id()));
        assertThat(watcher.await("team_duel.spectate_state", 5).path("duelId").asText())
                .isEqualTo(duel.matchFound().path("duelId").asText());
    }

    @Test
    void aStrangerToAllFourIsRejectedWithNotFriends() throws Exception {
        Duel duel = startTeamDuel("Team stranger");

        watcher = new Client(login("Stranger to all four"));
        watcher.await("hello", 5);

        watcher.send("duel.spectate", Map.of("userId", duel.aOne().id()));
        assertThat(watcher.await("error", 5).path("code").asText()).isEqualTo("not_friends");
    }

    /**
     * The 1v1 half of the refusal, which is the half that matters here: a
     * service knowing only about 2v2 would wave this caller through, and their
     * own duel's frames and this board's would then share the one socket.
     */
    @Test
    void aWatcherAlreadyFightingElsewhereIsRejectedWithAlreadyInDuel() throws Exception {
        Duel duel = startTeamDuel("Team busy watcher");
        Player fan = register("Busy team watcher");
        Player fanOpponent = register("Busy team watcher opponent");
        befriend(fan.token(), duel.aOne().token());

        watcher = new Client(fan.token());
        watcherOpponent = new Client(fanOpponent.token());
        watcher.await("hello", 5);
        watcherOpponent.await("hello", 5);
        watcher.send("queue.join", Map.of());
        watcherOpponent.send("queue.join", Map.of());
        watcher.await("match.found", 10);
        watcherOpponent.await("match.found", 10);

        watcher.send("duel.spectate", Map.of("userId", duel.aOne().id()));
        assertThat(watcher.await("error", 5).path("code").asText()).isEqualTo("already_in_duel");
    }

    @Test
    void watchingSomebodyInNeitherKindOfDuelIsRejectedWithNotInDuel() throws Exception {
        Player idle = register("Idle team player");
        Player fan = register("Idle team watcher");
        befriend(idle.token(), fan.token());

        aOne = new Client(idle.token());
        watcher = new Client(fan.token());
        aOne.await("hello", 5);
        watcher.await("hello", 5);

        watcher.send("duel.spectate", Map.of("userId", idle.id()));
        assertThat(watcher.await("error", 5).path("code").asText()).isEqualTo("not_in_duel");
    }

    @Test
    void aFriendInAnOrdinaryDuelIsStillWatchedTheOneOnOneWay() throws Exception {
        Player host = register("Routing host");
        Player guest = register("Routing guest");
        Player fan = register("Routing watcher");
        befriend(host.token(), fan.token());

        // The two socket fields are the 1v1 pair here; tearDown closes whatever
        // was opened either way.
        aOne = new Client(host.token());
        aTwo = new Client(guest.token());
        watcher = new Client(fan.token());
        aOne.await("hello", 5);
        aTwo.await("hello", 5);
        watcher.await("hello", 5);

        aOne.send("queue.join", Map.of());
        aTwo.send("queue.join", Map.of());
        JsonNode hostMatch = aOne.await("match.found", 10);
        aTwo.await("match.found", 10);

        watcher.send("duel.spectate", Map.of("userId", host.id()));
        JsonNode initial = watcher.await("duel.spectate_state", 5);

        assertThat(initial.path("duelId").asText()).isEqualTo(hostMatch.path("duelId").asText());
        assertThat(Set.of(initial.path("playerOne").path("id").asLong(), initial.path("playerTwo").path("id").asLong()))
                .containsExactlyInAnyOrder(host.id(), guest.id());

        Client mover = hostMatch.path("yourTurn").asBoolean() ? aOne : aTwo;
        mover.send("duel.submit", Map.of("word", wordFor(hostMatch.path("needLetter").asText().charAt(0))));

        JsonNode update = watcher.await("duel.spectate_state", 5);
        assertThat(update.path("chain").size()).isEqualTo(initial.path("chain").size() + 1);
    }

    /** A word that certainly exists for every starting letter — none of them a seed word. */
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
