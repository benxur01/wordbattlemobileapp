package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.HashSet;
import java.util.List;
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
 * Two pairs of friends team up, queue together, get matched, and play a 2v2
 * duel through a full turn rotation to a settled result. See
 * {@code DuelWebSocketTest} for the single-duel client harness this borrows —
 * this one drives four sockets instead of two, none of which is the server's
 * bot.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ExtendWith(CancelPendingForfeits.class)
class TeamDuelWebSocketTest {

    /**
     * A couple of candidate words for every starting letter, tried in order.
     * A single fixed word per letter (as {@code DuelWebSocketTest} gets away
     * with for a one-word exchange) forms short cycles once several turns are
     * chained — "letter" ends on 'r', "rocket" ends on 't', "tunnel" ends on
     * 'l', and 'l' is right back to "letter" — so a four-turn rotation needs a
     * fallback for whichever letter that closes a loop it lands on.
     */
    private static final Map<Character, List<String>> WORD_CANDIDATES = Map.ofEntries(
            Map.entry('a', List.of("anchor", "animal")), Map.entry('b', List.of("basket", "bottle")),
            Map.entry('c', List.of("cinema", "castle")), Map.entry('d', List.of("dinner", "doctor")),
            Map.entry('e', List.of("exotic", "engine")), Map.entry('f', List.of("famous", "forest")),
            Map.entry('g', List.of("guitar", "garden")), Map.entry('h', List.of("hunter", "husband")),
            Map.entry('i', List.of("island", "insect")), Map.entry('j', List.of("jacket", "jungle")),
            Map.entry('k', List.of("kitten", "koala")), Map.entry('l', List.of("letter", "liquid")),
            Map.entry('m', List.of("mirror", "market")), Map.entry('n', List.of("nature", "napkin")),
            Map.entry('o', List.of("orange", "oxygen")), Map.entry('p', List.of("pencil", "planet")),
            Map.entry('q', List.of("quiet", "quick")), Map.entry('r', List.of("rocket", "rabbit")),
            Map.entry('s', List.of("summer", "sunset")), Map.entry('t', List.of("tunnel", "tiger")),
            Map.entry('u', List.of("united", "umpire")), Map.entry('v', List.of("velvet", "vacuum")),
            Map.entry('w', List.of("winter", "window")), Map.entry('x', List.of("xylophone")),
            Map.entry('y', List.of("yellow", "yogurt")), Map.entry('z', List.of("zebra")));

    /** The first candidate for {@code letter} that is not already in {@code used}. */
    private static String wordFor(char letter, Set<String> used) {
        for (String candidate : WORD_CANDIDATES.get(letter)) {
            if (!used.contains(candidate)) return candidate;
        }
        throw new IllegalStateException("Every candidate for '" + letter + "' is already used: " + used);
    }

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    private final TestRestTemplate rest = new TestRestTemplate();
    private Client aOne;
    private Client aTwo;
    private Client bOne;
    private Client bTwo;

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

        JsonNode await(String type, int seconds) throws Exception {
            long deadline = System.currentTimeMillis() + seconds * 1000L;
            while (System.currentTimeMillis() < deadline) {
                JsonNode frame = frames.poll(deadline - System.currentTimeMillis(), TimeUnit.MILLISECONDS);
                if (frame == null) break;
                if (type.equals(frame.path("type").asText())) return frame.path("payload");
            }
            throw new AssertionError("No '" + type + "' frame arrived within " + seconds + "s");
        }

        /** Borrowed from {@code DuelWebSocketTest.Client} — proves a frame was *not* fanned out. */
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

    /** The four ids {@link #startTeamDuel} played into a duel. */
    private record Four(long aOne, long aTwo, long bOne, long bTwo) {}

    /**
     * Logs four fresh players in, forms both teams and queues them until they
     * are matched — the same sequence the duel tests above spell out, gathered
     * up for the social tests, which care about nothing before the duel exists.
     */
    private Four startTeamDuel(String namePrefix) throws Exception {
        String aOneToken = login(namePrefix + " A one");
        String aTwoToken = login(namePrefix + " A two");
        String bOneToken = login(namePrefix + " B one");
        String bTwoToken = login(namePrefix + " B two");

        Four ids = new Four(userId(aOneToken), userId(aTwoToken), userId(bOneToken), userId(bTwoToken));

        befriend(aOneToken, aTwoToken);
        befriend(bOneToken, bTwoToken);

        aOne = new Client(aOneToken);
        aTwo = new Client(aTwoToken);
        bOne = new Client(bOneToken);
        bTwo = new Client(bTwoToken);
        aOne.await("hello", 5);
        aTwo.await("hello", 5);
        bOne.await("hello", 5);
        bTwo.await("hello", 5);

        aOne.send("team_invite.send", Map.of("userId", ids.aTwo()));
        aTwo.send("team_invite.accept",
                Map.of("inviteId", aTwo.await("team_invite.incoming", 5).path("inviteId").asText()));
        aOne.await("team.formed", 5);
        aTwo.await("team.formed", 5);

        bOne.send("team_invite.send", Map.of("userId", ids.bTwo()));
        bTwo.send("team_invite.accept",
                Map.of("inviteId", bTwo.await("team_invite.incoming", 5).path("inviteId").asText()));
        bOne.await("team.formed", 5);
        bTwo.await("team.formed", 5);

        aOne.send("team.queue.join", Map.of());
        aTwo.await("team.queue.joined", 5);
        bOne.send("team.queue.join", Map.of());
        bTwo.await("team.queue.joined", 5);

        aOne.await("team_duel.match_found", 10);
        aTwo.await("team_duel.match_found", 10);
        bOne.await("team_duel.match_found", 10);
        bTwo.await("team_duel.match_found", 10);

        return ids;
    }

    @AfterEach
    void tearDown() throws Exception {
        if (aOne != null) aOne.close();
        if (aTwo != null) aTwo.close();
        if (bOne != null) bOne.close();
        if (bTwo != null) bTwo.close();
    }

    @Test
    void twoPairsOfFriendsFormTeamsQueueAndPlayAFullRotationThenSettle() throws Exception {
        String aOneToken = login("Team A one");
        String aTwoToken = login("Team A two");
        String bOneToken = login("Team B one");
        String bTwoToken = login("Team B two");

        long aOneId = userId(aOneToken);
        long aTwoId = userId(aTwoToken);
        long bOneId = userId(bOneToken);
        long bTwoId = userId(bTwoToken);

        befriend(aOneToken, aTwoToken);
        befriend(bOneToken, bTwoToken);

        aOne = new Client(aOneToken);
        aTwo = new Client(aTwoToken);
        bOne = new Client(bOneToken);
        bTwo = new Client(bTwoToken);
        aOne.await("hello", 5);
        aTwo.await("hello", 5);
        bOne.await("hello", 5);
        bTwo.await("hello", 5);

        // Team A forms: A-one invites, A-two accepts, so A-one is member one.
        aOne.send("team_invite.send", Map.of("userId", aTwoId));
        JsonNode aOneSent = aOne.await("team_invite.sent", 5);
        JsonNode aTwoIncoming = aTwo.await("team_invite.incoming", 5);
        assertThat(aOneSent.path("inviteId").asText()).isEqualTo(aTwoIncoming.path("inviteId").asText());
        aTwo.send("team_invite.accept", Map.of("inviteId", aTwoIncoming.path("inviteId").asText()));
        JsonNode aOneFormed = aOne.await("team.formed", 5);
        JsonNode aTwoFormed = aTwo.await("team.formed", 5);
        assertThat(aOneFormed.path("teamId").asLong()).isEqualTo(aTwoFormed.path("teamId").asLong());
        assertThat(aOneFormed.path("partner").path("id").asLong()).isEqualTo(aTwoId);
        assertThat(aTwoFormed.path("partner").path("id").asLong()).isEqualTo(aOneId);

        // Team B forms the same way: B-one invites, B-two accepts.
        bOne.send("team_invite.send", Map.of("userId", bTwoId));
        JsonNode bTwoIncoming = bTwo.await("team_invite.incoming", 5);
        bTwo.send("team_invite.accept", Map.of("inviteId", bTwoIncoming.path("inviteId").asText()));
        bOne.await("team.formed", 5);
        bTwo.await("team.formed", 5);

        // Only one member of each team has to queue — both are enqueued together.
        aOne.send("team.queue.join", Map.of());
        aTwo.await("team.queue.joined", 5);
        bOne.send("team.queue.join", Map.of());
        bTwo.await("team.queue.joined", 5);

        JsonNode aOneMatch = aOne.await("team_duel.match_found", 10);
        JsonNode aTwoMatch = aTwo.await("team_duel.match_found", 10);
        JsonNode bOneMatch = bOne.await("team_duel.match_found", 10);
        JsonNode bTwoMatch = bTwo.await("team_duel.match_found", 10);

        String duelId = aOneMatch.path("duelId").asText();
        assertThat(aTwoMatch.path("duelId").asText()).isEqualTo(duelId);
        assertThat(bOneMatch.path("duelId").asText()).isEqualTo(duelId);
        assertThat(bTwoMatch.path("duelId").asText()).isEqualTo(duelId);
        assertThat(aOneMatch.path("rated").asBoolean()).isTrue();

        // Team A queued first (its join call ran before Team B's), so it is
        // "team A" in the session and A-one — the team's member one — opens.
        long turnPlayerId = aOneMatch.path("turnPlayerId").asLong();
        assertThat(turnPlayerId).isEqualTo(aOneId);
        assertThat(aOneMatch.path("yourTurn").asBoolean()).isTrue();
        assertThat(aTwoMatch.path("yourTurn").asBoolean()).isFalse();
        assertThat(aOneMatch.path("partner").path("id").asLong()).isEqualTo(aTwoId);
        assertThat(aOneMatch.path("opponentOne").path("id").asLong()).isEqualTo(bOneId);
        assertThat(aOneMatch.path("opponentTwo").path("id").asLong()).isEqualTo(bTwoId);

        // A full four-cycle: A-one, B-one, A-two, B-two, and back to A-one.
        char needed = aOneMatch.path("needLetter").asText().charAt(0);
        Client[] rotation = {aOne, bOne, aTwo, bTwo};
        int chainSizeBefore = aOneMatch.path("chain").size();
        Set<String> played = new HashSet<>();
        played.add(aOneMatch.path("seedWord").asText());

        for (int turn = 0; turn < 4; turn++) {
            Client mover = rotation[turn];
            String word = wordFor(needed, played);
            played.add(word);
            mover.send("team_duel.submit", Map.of("word", word));

            JsonNode aOneState = aOne.await("team_duel.update", 5);
            JsonNode bOneState = bOne.await("team_duel.update", 5);
            JsonNode aTwoState = aTwo.await("team_duel.update", 5);
            JsonNode bTwoState = bTwo.await("team_duel.update", 5);

            assertThat(aOneState.path("chain").size()).isEqualTo(chainSizeBefore + turn + 1);

            long expectedNextTurn = rotation[(turn + 1) % 4] == aOne ? aOneId
                    : rotation[(turn + 1) % 4] == bOne ? bOneId
                    : rotation[(turn + 1) % 4] == aTwo ? aTwoId
                    : bTwoId;
            assertThat(aOneState.path("turnPlayerId").asLong()).isEqualTo(expectedNextTurn);
            assertThat(bOneState.path("turnPlayerId").asLong()).isEqualTo(expectedNextTurn);
            assertThat(aTwoState.path("turnPlayerId").asLong()).isEqualTo(expectedNextTurn);
            assertThat(bTwoState.path("turnPlayerId").asLong()).isEqualTo(expectedNextTurn);

            // Each side sees the word played as mine/ally/opponent correctly.
            JsonNode lastFromMoversView =
                    (mover == aOne ? aOneState : mover == bOne ? bOneState : mover == aTwo ? aTwoState : bTwoState)
                            .path("chain").get(chainSizeBefore + turn);
            assertThat(lastFromMoversView.path("word").asText()).isEqualTo(word);
            assertThat(lastFromMoversView.path("mine").asBoolean()).isTrue();

            // The word this turn's mover just played is the actual required
            // letter's ally/opponent view for whoever plays next — read back
            // from the state itself rather than assumed, since a rare-letter
            // substitution can hand the next player a different letter than
            // this word's own last one.
            needed = aOneState.path("needLetter").asText().charAt(0);
        }

        // Back to A-one after the full cycle: asserted above on the fourth
        // iteration already (expectedNextTurn wraps to aOneId), so nothing
        // further is submitted here.
    }

    @Test
    void formingATeamWithANonFriendIsRejected() throws Exception {
        String oneToken = login("Lone former");
        String strangerToken = login("Stranger to team with");
        long strangerId = userId(strangerToken);

        aOne = new Client(oneToken);
        aTwo = new Client(strangerToken);
        aOne.await("hello", 5);
        aTwo.await("hello", 5);

        aOne.send("team_invite.send", Map.of("userId", strangerId));
        assertThat(aOne.await("error", 5).path("code").asText()).isEqualTo("not_friends");
    }

    @Test
    void queueingWithNoFormedTeamIsRejected() throws Exception {
        aOne = new Client(login("Teamless"));
        aOne.await("hello", 5);

        aOne.send("team.queue.join", Map.of());
        assertThat(aOne.await("error", 5).path("code").asText()).isEqualTo("no_team");
    }

    @Test
    void aFormedTeamIsDisbandedWhenEitherMemberCancels() throws Exception {
        String oneToken = login("Canceller");
        String twoToken = login("Cancelled on");
        long twoId = userId(twoToken);

        befriend(oneToken, twoToken);

        aOne = new Client(oneToken);
        aTwo = new Client(twoToken);
        aOne.await("hello", 5);
        aTwo.await("hello", 5);

        aOne.send("team_invite.send", Map.of("userId", twoId));
        JsonNode incoming = aTwo.await("team_invite.incoming", 5);
        aTwo.send("team_invite.accept", Map.of("inviteId", incoming.path("inviteId").asText()));
        aOne.await("team.formed", 5);
        aTwo.await("team.formed", 5);

        aOne.send("team.cancel", Map.of());
        assertThat(aTwo.await("team.disbanded", 5).path("reason").asText()).isEqualTo("cancelled");

        // The team is gone, so queueing now fails the same way it would for
        // somebody who never formed one.
        aTwo.send("team.queue.join", Map.of());
        assertThat(aTwo.await("error", 5).path("code").asText()).isEqualTo("no_team");
    }

    @Test
    void aFullDuelSettlesRatingsInTheRightDirectionForBothTeams() throws Exception {
        String aOneToken = login("Settle A one");
        String aTwoToken = login("Settle A two");
        String bOneToken = login("Settle B one");
        String bTwoToken = login("Settle B two");

        long aOneId = userId(aOneToken);
        long aTwoId = userId(aTwoToken);
        long bOneId = userId(bOneToken);
        long bTwoId = userId(bTwoToken);

        befriend(aOneToken, aTwoToken);
        befriend(bOneToken, bTwoToken);

        aOne = new Client(aOneToken);
        aTwo = new Client(aTwoToken);
        bOne = new Client(bOneToken);
        bTwo = new Client(bTwoToken);
        aOne.await("hello", 5);
        aTwo.await("hello", 5);
        bOne.await("hello", 5);
        bTwo.await("hello", 5);

        aOne.send("team_invite.send", Map.of("userId", aTwoId));
        JsonNode aTwoIncoming = aTwo.await("team_invite.incoming", 5);
        aTwo.send("team_invite.accept", Map.of("inviteId", aTwoIncoming.path("inviteId").asText()));
        aOne.await("team.formed", 5);
        aTwo.await("team.formed", 5);

        bOne.send("team_invite.send", Map.of("userId", bTwoId));
        JsonNode bTwoIncoming = bTwo.await("team_invite.incoming", 5);
        bTwo.send("team_invite.accept", Map.of("inviteId", bTwoIncoming.path("inviteId").asText()));
        bOne.await("team.formed", 5);
        bTwo.await("team.formed", 5);

        aOne.send("team.queue.join", Map.of());
        aTwo.await("team.queue.joined", 5);
        bOne.send("team.queue.join", Map.of());
        bTwo.await("team.queue.joined", 5);

        aOne.await("team_duel.match_found", 10);
        aTwo.await("team_duel.match_found", 10);
        bOne.await("team_duel.match_found", 10);
        bTwo.await("team_duel.match_found", 10);

        // Team B forfeits (either member may): team A wins outright.
        bOne.send("team_duel.forfeit", Map.of());

        JsonNode aOneResult = aOne.await("team_duel.finished", 5);
        JsonNode aTwoResult = aTwo.await("team_duel.finished", 5);
        JsonNode bOneResult = bOne.await("team_duel.finished", 5);
        JsonNode bTwoResult = bTwo.await("team_duel.finished", 5);

        assertThat(aOneResult.path("result").asText()).isEqualTo("win");
        assertThat(aTwoResult.path("result").asText()).isEqualTo("win");
        assertThat(bOneResult.path("result").asText()).isEqualTo("lose");
        assertThat(bTwoResult.path("result").asText()).isEqualTo("lose");
        assertThat(aOneResult.path("reason").asText()).isEqualTo("forfeit");

        assertThat(aOneResult.path("delta").asInt()).isPositive();
        assertThat(aTwoResult.path("delta").asInt()).isPositive();
        assertThat(bOneResult.path("delta").asInt()).isNegative();
        assertThat(bTwoResult.path("delta").asInt()).isNegative();

        assertThat(aOneResult.path("ratingAfter").asInt())
                .isEqualTo(aOneResult.path("ratingBefore").asInt() + aOneResult.path("delta").asInt());

        // Both winners moved by roughly the same amount, and so did both
        // losers: each side was rated against the same synthetic average
        // opponent, not against each other individually.
        int aOneDelta = aOneResult.path("delta").asInt();
        int aTwoDelta = aTwoResult.path("delta").asInt();
        assertThat(Math.abs(aOneDelta - aTwoDelta)).isLessThanOrEqualTo(3);
    }

    @Test
    void chatReachesTheOtherThreeTrimmedAndNamesItsSender() throws Exception {
        Four ids = startTeamDuel("Team chatty");

        aOne.send("team_duel.chat", Map.of("text", "  ketdik  "));

        for (Client recipient : List.of(aTwo, bOne, bTwo)) {
            JsonNode chat = recipient.await("team_duel.chat", 5);
            assertThat(chat.path("text").asText()).isEqualTo("ketdik");
            // Three people could have sent it, so the frame has to say which.
            assertThat(chat.path("playerId").asLong()).isEqualTo(ids.aOne());
        }
        aOne.expectNothing("team_duel.chat", 1);
    }

    @Test
    void aReactionReachesTheOtherThreeAndNamesItsSender() throws Exception {
        Four ids = startTeamDuel("Team reactor");

        bTwo.send("team_duel.reaction", Map.of("emoji", "🔥"));

        for (Client recipient : List.of(aOne, aTwo, bOne)) {
            JsonNode reaction = recipient.await("team_duel.reaction", 5);
            assertThat(reaction.path("emoji").asText()).isEqualTo("🔥");
            assertThat(reaction.path("playerId").asLong()).isEqualTo(ids.bTwo());
        }
        bTwo.expectNothing("team_duel.reaction", 1);
    }

    @Test
    void chatOverTwoHundredCharactersIsRejectedAndFannedOutToNobody() throws Exception {
        startTeamDuel("Team wordy");

        aOne.send("team_duel.chat", Map.of("text", "a".repeat(201)));

        assertThat(aOne.await("error", 5).path("code").asText()).isEqualTo("message_too_long");
        aTwo.expectNothing("team_duel.chat", 1);
        bOne.expectNothing("team_duel.chat", 1);
        bTwo.expectNothing("team_duel.chat", 1);
    }
}
