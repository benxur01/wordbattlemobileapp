package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.time.Instant;
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
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.lang.NonNull;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * Two real clients, one real server: queue up, get paired, have a word refused,
 * play a legal one, and see the duel settle. This is the path the Flutter app
 * takes, so it is worth exercising for real rather than mocking the socket.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DuelWebSocketTest {

    /** A word that certainly exists for every starting letter. */
    private static final Map<Character, String> WORD_FOR = Map.ofEntries(
            Map.entry('a', "anchor"), Map.entry('b', "basket"), Map.entry('c', "cinema"),
            Map.entry('d', "dinner"), Map.entry('e', "engine"), Map.entry('f', "famous"),
            Map.entry('g', "guitar"), Map.entry('h', "hunter"), Map.entry('i', "island"),
            Map.entry('j', "jacket"), Map.entry('k', "kitten"), Map.entry('l', "letter"),
            Map.entry('m', "mirror"), Map.entry('n', "nature"), Map.entry('o', "orange"),
            Map.entry('p', "pencil"), Map.entry('q', "quiet"), Map.entry('r', "rocket"),
            Map.entry('s', "summer"), Map.entry('t', "tunnel"), Map.entry('u', "united"),
            Map.entry('v', "velvet"), Map.entry('w', "winter"), Map.entry('x', "xylophone"),
            Map.entry('y', "yellow"), Map.entry('z', "zebra"));

    @LocalServerPort
    private int port;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private UserRepository users;

    private final TestRestTemplate rest = new TestRestTemplate();
    private Client alpha;
    private Client beta;

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

    /** The account behind a token, asked for the way any client would. */
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

    /** Moves an account off the 1200 every fresh one starts on. */
    private long rate(String token, double rating) throws Exception {
        long id = userId(token);
        User user = users.findById(id).orElseThrow();
        user.setRating(rating);
        users.save(user);
        return id;
    }

    /**
     * An account the ladder already knows — a deviation of 60 rather than a new
     * player's 350 — whose last rated duel was {@code idlePeriods} rating
     * periods ago. A fresh account is capped at 350 and could not be inflated
     * at all, so a settled one is the only way to see the growth happen.
     */
    private long settled(String token, double deviation, int idlePeriods) throws Exception {
        long id = userId(token);
        User user = users.findById(id).orElseThrow();
        user.setRatingDeviation(deviation);
        user.setRatingPeriodAt(Instant.now().minus(Duration.ofHours(24 * idlePeriods)));
        users.save(user);
        return id;
    }

    @AfterEach
    void tearDown() throws Exception {
        if (alpha != null) alpha.close();
        if (beta != null) beta.close();
    }

    @Test
    void twoPlayersAreMatchedAndTheServerJudgesEveryWord() throws Exception {
        alpha = new Client(login("Alpha"));
        beta = new Client(login("Beta"));

        assertThat(alpha.await("hello", 5).path("rules").path("turnSeconds").asInt()).isEqualTo(15);
        beta.await("hello", 5);

        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());

        JsonNode alphaMatch = alpha.await("match.found", 10);
        JsonNode betaMatch = beta.await("match.found", 10);

        // Same duel, opposite turns, and a real rated game (not the bot).
        assertThat(alphaMatch.path("duelId").asText()).isEqualTo(betaMatch.path("duelId").asText());
        assertThat(alphaMatch.path("yourTurn").asBoolean()).isNotEqualTo(betaMatch.path("yourTurn").asBoolean());
        assertThat(alphaMatch.path("rated").asBoolean()).isTrue();

        boolean alphaStarts = alphaMatch.path("yourTurn").asBoolean();
        Client mover = alphaStarts ? alpha : beta;
        Client waiter = alphaStarts ? beta : alpha;
        char needed = alphaMatch.path("needLetter").asText().charAt(0);

        // A word starting with the wrong letter is refused, and the turn stays put.
        char wrongLetter = needed == 'z' ? 'a' : (char) (needed + 1);
        mover.send("duel.submit", Map.of("word", WORD_FOR.get(wrongLetter)));
        JsonNode rejected = mover.await("duel.rejected", 5);
        assertThat(rejected.path("code").asText()).isEqualTo("wrong_letter");

        // So is a word that is not in the dictionary at all.
        mover.send("duel.submit", Map.of("word", needed + "zzqqx"));
        assertThat(mover.await("duel.rejected", 5).path("code").asText()).isEqualTo("not_a_word");

        // The opponent cannot play out of turn either.
        waiter.send("duel.submit", Map.of("word", WORD_FOR.get(needed)));
        assertThat(waiter.await("duel.rejected", 5).path("code").asText()).isEqualTo("not_your_turn");

        // A legal word is accepted and both sides see the same chain.
        String word = WORD_FOR.get(needed);
        mover.send("duel.submit", Map.of("word", word));

        JsonNode moverState = mover.await("duel.update", 5);
        JsonNode waiterState = waiter.await("duel.update", 5);

        assertThat(moverState.path("yourTurn").asBoolean()).isFalse();
        assertThat(waiterState.path("yourTurn").asBoolean()).isTrue();
        assertThat(moverState.path("yourWords").asInt()).isEqualTo(1);
        assertThat(waiterState.path("opponentWords").asInt()).isEqualTo(1);
        assertThat(waiterState.path("needLetter").asText())
                .isEqualTo(String.valueOf(word.charAt(word.length() - 1)));

        JsonNode lastEntry = moverState.path("chain").get(moverState.path("chain").size() - 1);
        assertThat(lastEntry.path("word").asText()).isEqualTo(word);
        assertThat(lastEntry.path("mine").asBoolean()).isTrue();

        // Quitting hands the win to the opponent and settles both ratings.
        waiter.send("duel.forfeit", Map.of());

        JsonNode winner = mover.await("duel.finished", 5);
        JsonNode loser = waiter.await("duel.finished", 5);

        assertThat(winner.path("result").asText()).isEqualTo("win");
        assertThat(loser.path("result").asText()).isEqualTo("lose");
        assertThat(winner.path("reason").asText()).isEqualTo("forfeit");
        assertThat(winner.path("delta").asInt()).isPositive();
        assertThat(loser.path("delta").asInt()).isNegative();
        assertThat(winner.path("ratingAfter").asInt())
                .isEqualTo(winner.path("ratingBefore").asInt() + winner.path("delta").asInt());
        // The loser is handed three words for the letter they were stuck on.
        assertThat(loser.path("stuckLetter").asText()).isNotEmpty();
        assertThat(loser.path("hints")).hasSize(3);
    }

    /**
     * Two humans further apart than the opening window have to find each other
     * rather than a bot each. Live, they did not: 1362 and 1037 queued together
     * and were both handed a bot in the same second, because the fallback fired
     * at twelve seconds and the window had reached only 175 by then. Bot duels
     * are unrated, so the pair had no way to close the gap that was keeping
     * them apart, and a run of one-sided results separated them for good.
     *
     * <p>180 points is the gap that tells the two schedules apart: wider than
     * anything the old one opened to before its bot, inside the new one at nine
     * seconds. The property is what matters — a pair the opening window cannot
     * hold still meets — so the numbers here are deliberately not the ceiling.
     */
    @Test
    void twoPlayersTooFarApartForTheOpeningWindowMeetEachOtherRatherThanABot() throws Exception {
        String leaderToken = login("Zafar");
        String chaserToken = login("Laylo");
        long leaderId = rate(leaderToken, 1380);
        long chaserId = rate(chaserToken, 1200);

        alpha = new Client(leaderToken);
        beta = new Client(chaserToken);
        alpha.await("hello", 5);
        beta.await("hello", 5);

        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());

        JsonNode leaderMatch = alpha.await("match.found", 30);
        JsonNode chaserMatch = beta.await("match.found", 30);

        // One duel between the two of them, and a rated one. Two bots would be
        // two duel ids and rated: false — which is exactly what the old
        // schedule handed them.
        assertThat(leaderMatch.path("duelId").asText()).isEqualTo(chaserMatch.path("duelId").asText());
        assertThat(leaderMatch.path("rated").asBoolean()).isTrue();
        assertThat(leaderMatch.path("opponent").path("id").asLong()).isEqualTo(chaserId);
        assertThat(chaserMatch.path("opponent").path("id").asLong()).isEqualTo(leaderId);
    }

    /**
     * Glicko-2's step 6 down the real settlement path — the column, the clock
     * and the duel that reads them — rather than the arithmetic on its own,
     * which {@code Glicko2Test} already pins.
     *
     * <p>Two players on 1200 that the ladder knows equally well, except that
     * one of them has not settled a rated duel in two hundred rating periods.
     * That used to make no difference whatsoever: they met on a deviation of 60
     * each and moved ten points in opposite directions, however long one had
     * been gone. The absent one's deviation is now aged to 159 before the game
     * is rated, and the same result moves them several times as far as it moves
     * the opponent who never left. That asymmetry is the whole point — a rating
     * nobody has tested in half a year is a guess, and the first game back
     * should say far more about the player who has been away than about the one
     * who has been here all along.
     */
    @Test
    void aPlayerBackFromALongAbsenceMovesFurtherThanTheOpponentWhoNeverLeft() throws Exception {
        String idleToken = login("Qaytgan");
        String regularToken = login("Doimiy");
        long idleId = settled(idleToken, 60, 200);
        long regularId = settled(regularToken, 60, 0);

        alpha = new Client(idleToken);
        beta = new Client(regularToken);
        alpha.await("hello", 5);
        beta.await("hello", 5);

        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());

        JsonNode idleMatch = alpha.await("match.found", 30);
        beta.await("match.found", 30);
        // Each other and nobody else: a bot duel settles no rating at all and
        // would leave both deltas at zero, which passes nothing here honestly.
        assertThat(idleMatch.path("opponent").path("id").asLong()).isEqualTo(regularId);
        assertThat(idleMatch.path("rated").asBoolean()).isTrue();

        // Who wins does not matter, only how far each is moved by it.
        alpha.send("duel.forfeit", Map.of());

        int idleDelta = alpha.await("duel.finished", 5).path("delta").asInt();
        int regularDelta = beta.await("duel.finished", 5).path("delta").asInt();

        assertThat(Math.abs(idleDelta)).isGreaterThan(Math.abs(regularDelta));

        // And the clock is restarted for both, so the absence just paid for is
        // not charged again to the next duel either of them plays.
        Instant justNow = Instant.now().minus(Duration.ofMinutes(1));
        assertThat(users.findById(idleId).orElseThrow().getRatingPeriodAt()).isAfter(justNow);
        assertThat(users.findById(regularId).orElseThrow().getRatingPeriodAt()).isAfter(justNow);
    }

    @Test
    void aLoneSearchFallsBackToTheBotAndThatDuelIsUnrated() throws Exception {
        alpha = new Client(login("Solo"));
        alpha.await("hello", 5);

        alpha.send("queue.join", Map.of());
        alpha.await("queue.joined", 5);

        // No human turns up, so the bot steps in (bot-fallback-seconds). The
        // wait is the real one: shortening it here for the suite's sake would
        // leave the shipped number the only part of this never exercised.
        JsonNode match = alpha.await("match.found", 50);
        assertThat(match.path("rated").asBoolean()).isFalse();
        assertThat(match.path("opponent").path("nickname").asText()).isEqualTo("wordbot");
        assertThat(match.path("yourTurn").asBoolean()).isTrue();

        // The bot answers on its own once a legal word is played.
        char needed = match.path("needLetter").asText().charAt(0);
        alpha.send("duel.submit", Map.of("word", WORD_FOR.get(needed)));

        JsonNode afterMine = alpha.await("duel.update", 5);
        assertThat(afterMine.path("yourTurn").asBoolean()).isFalse();

        JsonNode afterBot = alpha.await("duel.update", 8);
        assertThat(afterBot.path("yourTurn").asBoolean()).isTrue();
        assertThat(afterBot.path("opponentWords").asInt()).isEqualTo(1);
    }

    @Test
    void chatReachesTheOpponentOnlyAndTrimmed() throws Exception {
        alpha = new Client(login("Chatty alpha"));
        beta = new Client(login("Chatty beta"));
        alpha.await("hello", 5);
        beta.await("hello", 5);
        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());
        alpha.await("match.found", 10);
        beta.await("match.found", 10);

        alpha.send("duel.chat", Map.of("text", "  gl hf  "));

        assertThat(beta.await("duel.chat", 5).path("text").asText()).isEqualTo("gl hf");
        alpha.expectNothing("duel.chat", 1);
    }

    @Test
    void chatWithNoActiveDuelIsRejected() throws Exception {
        alpha = new Client(login("No duel chatter"));
        alpha.await("hello", 5);

        alpha.send("duel.chat", Map.of("text", "hello?"));

        assertThat(alpha.await("error", 5).path("code").asText()).isEqualTo("no_duel");
    }

    @Test
    void emptyOrBlankChatIsRejected() throws Exception {
        alpha = new Client(login("Blank chatter"));
        beta = new Client(login("Blank chatter rival"));
        alpha.await("hello", 5);
        beta.await("hello", 5);
        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());
        alpha.await("match.found", 10);
        beta.await("match.found", 10);

        alpha.send("duel.chat", Map.of("text", "   "));

        assertThat(alpha.await("error", 5).path("code").asText()).isEqualTo("empty_message");
        beta.expectNothing("duel.chat", 1);
    }

    @Test
    void chatOverTwoHundredCharactersIsRejected() throws Exception {
        alpha = new Client(login("Wordy chatter"));
        beta = new Client(login("Wordy chatter rival"));
        alpha.await("hello", 5);
        beta.await("hello", 5);
        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());
        alpha.await("match.found", 10);
        beta.await("match.found", 10);

        alpha.send("duel.chat", Map.of("text", "a".repeat(201)));

        assertThat(alpha.await("error", 5).path("code").asText()).isEqualTo("message_too_long");
        beta.expectNothing("duel.chat", 1);
    }

    @Test
    void aReactionOutsideTheFixedSetIsRejected() throws Exception {
        alpha = new Client(login("Reactor"));
        beta = new Client(login("Reactor rival"));
        alpha.await("hello", 5);
        beta.await("hello", 5);
        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());
        alpha.await("match.found", 10);
        beta.await("match.found", 10);

        alpha.send("duel.reaction", Map.of("emoji", "🍕"));

        assertThat(alpha.await("error", 5).path("code").asText()).isEqualTo("invalid_reaction");
        beta.expectNothing("duel.reaction", 1);
    }

    @Test
    void aValidReactionReachesTheOpponent() throws Exception {
        alpha = new Client(login("Valid reactor"));
        beta = new Client(login("Valid reactor rival"));
        alpha.await("hello", 5);
        beta.await("hello", 5);
        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());
        alpha.await("match.found", 10);
        beta.await("match.found", 10);

        alpha.send("duel.reaction", Map.of("emoji", "🔥"));

        assertThat(beta.await("duel.reaction", 5).path("emoji").asText()).isEqualTo("🔥");
    }

    @Test
    void chatAndReactionsShareOneThrottleAndTheSecondTooSoonIsRejected() throws Exception {
        alpha = new Client(login("Fast chatter"));
        beta = new Client(login("Fast chatter rival"));
        alpha.await("hello", 5);
        beta.await("hello", 5);
        alpha.send("queue.join", Map.of());
        beta.send("queue.join", Map.of());
        alpha.await("match.found", 10);
        beta.await("match.found", 10);

        alpha.send("duel.chat", Map.of("text", "first"));
        beta.await("duel.chat", 5);

        // Sent immediately after, well inside the 400ms window.
        alpha.send("duel.reaction", Map.of("emoji", "😂"));
        assertThat(alpha.await("error", 5).path("code").asText()).isEqualTo("too_fast");
        beta.expectNothing("duel.reaction", 1);
    }
}
