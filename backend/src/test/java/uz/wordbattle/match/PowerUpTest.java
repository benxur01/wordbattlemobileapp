package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willAnswer;
import static org.mockito.Mockito.mock;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.dictionary.DictionaryService;
import uz.wordbattle.dictionary.WordTheme;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.GameSocketHandler;
import uz.wordbattle.ws.HandshakeAuthInterceptor;
import uz.wordbattle.ws.SocketRegistry;

/**
 * The four power-ups: what each of them does, that each is good for one use,
 * and — the point of most of this file — that none of them exists at all in a
 * duel between two people.
 *
 * <p>Driven through {@code GameSocketHandler} with a stand-in socket, so every
 * test goes the whole way a client's frame goes: the frame name, the payload's
 * field, the service's checks, and the frames written back. What a power-up did
 * is then read off the session itself, because a state frame is the one thing
 * that can look right while the server disagrees with it.
 */
@SpringBootTest
class PowerUpTest {

    /** {@code wordbattle.duel.turn-seconds}. */
    private static final int TURN_MS = 15_000;

    /** {@code DuelService.ADD_TIME_MS}. */
    private static final int BONUS_MS = 10_000;

    /**
     * {@code DuelService.BOT_DELAY_MIN_MS}: the fastest an ordinary bot reply
     * can arrive, and so the bar a pressured one has to come in under.
     */
    private static final long UNPRESSURED_MIN_MS = 1200;

    /** Mid-range, so the bot's words come from both halves of its vocabulary. */
    private static final double BOT_RATING = 900;

    /** The deepest themed list, so no letter of it is a special case. */
    private static final WordTheme THEME = WordTheme.ANIMALS;

    @Autowired
    private DuelService duels;

    @Autowired
    private DictionaryService dictionary;

    @Autowired
    private UserService users;

    @Autowired
    private SocketRegistry sockets;

    @Autowired
    private GameSocketHandler handler;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private AppProperties props;

    private final Map<Long, WebSocketSession> socketOf = new LinkedHashMap<>();
    private final Map<Long, List<JsonNode>> framesOf = new LinkedHashMap<>();

    @AfterEach
    void endEverything() {
        for (long playerId : socketOf.keySet()) {
            duels.forfeit(playerId);
            sockets.disconnect(playerId);
        }
    }

    @Test
    void everyChargeIsGoodForExactlyOneUse() throws Exception {
        long player = botDuel(null);

        for (PowerUp powerUp : PowerUp.values()) {
            use(player, powerUp.id());
            assertThat(payload(player, "duel.power_up").path("type").asText())
                    .as("%s was refused the first time", powerUp.id())
                    .isEqualTo(powerUp.id());

            use(player, powerUp.id());
            assertThat(payload(player, "error").path("code").asText())
                    .as("%s could be used twice", powerUp.id())
                    .isEqualTo("power_up_spent");
        }
    }

    /**
     * The one that could most easily be a lie. A bonus the client is told about
     * and the server does not act on leaves a player watching eighteen seconds
     * on the ring and losing on time at fifteen, so what is held here is the
     * expiry actually armed — and that the one it replaced no longer bites.
     */
    @Test
    void addTimeMovesTheExpiryItselfNotOnlyTheNumberOnScreen() throws Exception {
        long player = botDuel(null);
        DuelSession session = duels.duelOf(player).orElseThrow();
        long armedForTurn = session.turnNumber();
        long before = session.turnTimer().getDelay(TimeUnit.MILLISECONDS);

        use(player, PowerUp.ADD_TIME.id());

        long after = session.turnTimer().getDelay(TimeUnit.MILLISECONDS);
        assertThat(after - before).isBetween(BONUS_MS - 1000L, (long) BONUS_MS);
        assertThat(after).as("the turn still ends within its own length").isGreaterThan(TURN_MS);
        assertThat(payload(player, "duel.update").path("timeLeftMs").asInt())
                .isGreaterThan(TURN_MS)
                .isLessThanOrEqualTo(TURN_MS + BONUS_MS);

        // The expiry armed before the extension is now a stale one, and a stale
        // expiry that had already started running must not end the turn it was
        // armed for — the whole point of rescheduling rather than pretending.
        duels.onTurnExpired(session, armedForTurn);
        assertThat(session.finished()).as("the old deadline still ended the duel").isFalse();
    }

    @Test
    void skippingHandsOverAnotherLetterAndSaysThatIsWhy() throws Exception {
        long player = botDuel(null);
        DuelSession session = duels.duelOf(player).orElseThrow();
        char refused = session.requiredLetter();

        use(player, PowerUp.SKIP_LETTER.id());

        assertThat(session.requiredLetter()).isNotEqualTo(refused);
        JsonNode update = payload(player, "duel.update");
        assertThat(update.path("needLetter").asText()).isEqualTo(String.valueOf(session.requiredLetter()));
        assertThat(update.path("substitutedFrom").asText()).isEqualTo(String.valueOf(refused));
        // The board draws the same note the rare-letter rule raises, and would
        // otherwise tell the player their own skip was a rare letter.
        assertThat(update.path("substitutionReason").asText()).isEqualTo("power_up");

        // And the rule moved with the letter: the word that was wanted a moment
        // ago is now the wrong one.
        duels.submit(player, wordFor(refused, session));
        assertThat(payload(player, "duel.rejected").path("code").asText()).isEqualTo("wrong_letter");
    }

    @Test
    void theHintOffersWordsFromInsideTheThemeWhenThereIsOne() throws Exception {
        long player = botDuel(THEME);
        DuelSession session = duels.duelOf(player).orElseThrow();
        char letter = session.requiredLetter();

        use(player, PowerUp.HINT.id());

        List<String> words = new ArrayList<>();
        payload(player, "duel.power_up").path("words").forEach(word -> words.add(word.asText()));
        assertThat(words).isNotEmpty();
        for (String word : words) {
            assertThat(word.charAt(0)).isEqualTo(letter);
            assertThat(dictionary.isInTheme(THEME, word))
                    .as("'%s' is not a %s word, and this duel would refuse it", word, THEME.id())
                    .isTrue();
        }

        // A hint is a read: the letter, the clock and the chain are where they
        // were, and only the charge is gone.
        assertThat(session.requiredLetter()).isEqualTo(letter);
        assertThat(session.turnBonusMs()).isZero();
        assertThat(session.chainLength()).isZero();
    }

    /**
     * The bot has no clock to shorten — it holds its answer back for a moment
     * so as not to reply the instant a word lands. Pressure spends that moment:
     * the next reply comes back at once, which is a faster opponent to keep up
     * with rather than a weaker one.
     */
    @Test
    void pressureBringsTheBotsNextReplyForward() throws Exception {
        long player = botDuel(null);
        DuelSession session = duels.duelOf(player).orElseThrow();

        assertThat(timeBotTakesToAnswer(player, session, 1))
                .as("the bot answered before it had waited at all")
                .isGreaterThanOrEqualTo(UNPRESSURED_MIN_MS);

        use(player, PowerUp.PRESSURE.id());
        assertThat(timeBotTakesToAnswer(player, session, 2)).isLessThan(UNPRESSURED_MIN_MS);

        // Spent on the one reply it was aimed at: the move after it is the
        // unhurried bot again.
        assertThat(timeBotTakesToAnswer(player, session, 3)).isGreaterThanOrEqualTo(UNPRESSURED_MIN_MS);
    }

    /**
     * The rule the rest of this file exists to protect. A rated duel has a
     * person on the other side of it, and a letter or a clock that answers to
     * one of them is not a game they are both playing.
     */
    @Test
    void aDuelBetweenTwoPeopleHasNoPowerUpsAtAll() throws Exception {
        long one = player("Rated one");
        long two = player("Rated two");
        DuelSession session = duels.start(one, two);
        assertThat(session).isNotNull();

        char letter = session.requiredLetter();
        long armed = session.turnTimer().getDelay(TimeUnit.MILLISECONDS);

        for (PowerUp powerUp : PowerUp.values()) {
            use(one, powerUp.id());
            assertThat(payload(one, "error").path("code").asText())
                    .as("%s was allowed in a rated duel", powerUp.id())
                    .isEqualTo("not_a_bot_duel");
        }

        // From the player who is not even on turn, the same refusal: it is the
        // duel that has no power-ups, not the moment.
        use(two, PowerUp.ADD_TIME.id());
        assertThat(payload(two, "error").path("code").asText()).isEqualTo("not_a_bot_duel");

        assertThat(session.requiredLetter()).isEqualTo(letter);
        assertThat(session.turnBonusMs()).isZero();
        assertThat(session.turnTimer().getDelay(TimeUnit.MILLISECONDS)).isLessThanOrEqualTo(armed);
        assertThat(framesOf(one)).noneMatch(frame -> "duel.power_up".equals(frame.path("type").asText()));
        assertThat(framesOf(two)).noneMatch(frame -> "duel.power_up".equals(frame.path("type").asText()));
    }

    /** All four bend the turn the player is standing on, so all four wait for it. */
    @Test
    void aPowerUpOnTheBotsTurnIsRefusedAndCostsNothing() throws Exception {
        long player = botDuel(null);
        DuelSession session = duels.duelOf(player).orElseThrow();

        duels.submit(player, wordFor(session.requiredLetter(), session));
        assertThat(session.turn()).isEqualTo(DuelSession.BOT_ID);

        use(player, PowerUp.ADD_TIME.id());
        assertThat(payload(player, "error").path("code").asText()).isEqualTo("not_your_turn");
        assertThat(session.turnBonusMs()).isZero();

        // The charge survived the refusal: it is spent by using it, not by
        // asking at the wrong moment.
        awaitBotReply(session, 1);
        use(player, PowerUp.ADD_TIME.id());
        assertThat(payload(player, "duel.power_up").path("type").asText()).isEqualTo(PowerUp.ADD_TIME.id());
    }

    @Test
    void aPowerUpThisServerHasNeverHeardOfIsRefusedByName() throws Exception {
        long player = botDuel(null);

        use(player, "double_score");

        assertThat(payload(player, "error").path("code").asText()).isEqualTo("unknown_power_up");
    }

    // --------------------------------------------------------------- helpers

    /** A player, a stand-in socket, and a duel against the bot they can play. */
    private long botDuel(WordTheme theme) throws Exception {
        long player = player(theme == null ? "Power-up player" : "Themed power-up player");
        assertThat(duels.startAgainstChosenBot(player, BOT_RATING, theme)).isNotNull();
        return player;
    }

    private long player(String displayName) throws Exception {
        long playerId = users.createDevUser(displayName).getId();
        connect(playerId);
        return playerId;
    }

    /** One power-up frame, sent exactly as the app sends it. */
    private void use(long playerId, String type) throws Exception {
        String json = mapper.writeValueAsString(
                Map.of("type", "duel.power_up", "payload", Map.of("type", type)));
        handler.handleMessage(socketOf.get(playerId), new TextMessage(json));
    }

    /**
     * How long the bot took over its {@code move}-th answer, measured from the
     * word it is replying to. The player's own word is played here so that the
     * clock starts where the bot's wait does.
     */
    private long timeBotTakesToAnswer(long playerId, DuelSession session, int move) {
        String word;
        synchronized (session) {
            word = wordFor(session.requiredLetter(), session);
        }
        long start = System.currentTimeMillis();
        duels.submit(playerId, word);
        awaitBotReply(session, move);
        return System.currentTimeMillis() - start;
    }

    /** A word this chain will accept for {@code letter}. Every bot word is a legal one. */
    private String wordFor(char letter, DuelSession session) {
        synchronized (session) {
            String word = session.theme() == null
                    ? dictionary.botMove(letter, session.used(), props.duel().minWordLength(), BOT_RATING)
                    : dictionary.botMove(session.theme(), letter, session.used(), props.duel().minWordLength(), BOT_RATING);
            assertThat(word).as("no word starts with '%s'", letter).isNotNull();
            return word;
        }
    }

    /** The bot answers on a timer of its own, so polling beats a sleep. */
    private void awaitBotReply(DuelSession session, int move) {
        long deadline = System.currentTimeMillis() + 10_000;
        while (System.currentTimeMillis() < deadline) {
            synchronized (session) {
                if (session.finished() || session.chain().size() > move * 2) return;
            }
            try {
                Thread.sleep(5);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
        throw new AssertionError("The bot did not answer move " + move);
    }

    /**
     * The stand-in socket {@code BotDuelRatingTest} uses, carrying the player's
     * id in its attributes as the handshake leaves it — {@link GameSocketHandler}
     * reads every frame's sender from there.
     */
    private void connect(long userId) throws Exception {
        List<JsonNode> frames = new ArrayList<>();
        WebSocketSession socket = mock(WebSocketSession.class);
        given(socket.isOpen()).willReturn(true);
        given(socket.getId()).willReturn("socket-" + userId);
        given(socket.getAttributes()).willReturn(new HashMap<>(Map.of(HandshakeAuthInterceptor.USER_ID, userId)));
        willAnswer(invocation -> {
            TextMessage message = invocation.getArgument(0);
            synchronized (frames) {
                frames.add(mapper.readTree(message.getPayload()));
            }
            return null;
        })
                .given(socket)
                .sendMessage(any());
        sockets.register(userId, socket);
        socketOf.put(userId, socket);
        framesOf.put(userId, frames);
    }

    private List<JsonNode> framesOf(long userId) {
        List<JsonNode> frames = framesOf.get(userId);
        synchronized (frames) {
            return List.copyOf(frames);
        }
    }

    /** The payload of the last frame of this type this player was sent. */
    private JsonNode payload(long userId, String type) {
        return framesOf(userId).stream()
                .filter(frame -> type.equals(frame.path("type").asText()))
                .reduce((first, second) -> second)
                .orElseThrow(() -> new AssertionError("No '" + type + "' frame was sent to " + userId))
                .path("payload");
    }
}
