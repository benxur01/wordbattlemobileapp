package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willAnswer;
import static org.mockito.Mockito.mock;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import uz.wordbattle.dictionary.DictionaryService;
import uz.wordbattle.dictionary.WordTheme;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.SocketRegistry;

/**
 * A duel played inside one theme, against the real bot.
 *
 * <p>The theme is the only rule that changes: the words either side may say are
 * that theme's few hundred instead of the dictionary's 358k, and everything
 * else — the turn, the letter, the strength the bot was asked for — is the duel
 * this server already ran. So what is held here is that both halves of the
 * restriction bite. A player's word has to be in the theme however good an
 * English word it is, and the bot's own answers have to come from inside the
 * same list rather than from the pool it plays every other duel out of.
 *
 * <p>Driven through the services with a stand-in socket, like
 * {@code BotDuelRatingTest}: the frames are read where they are written.
 */
@SpringBootTest
class ThemedDuelTest {

    /** The theme played here — the deepest list, so no letter is a special case. */
    private static final WordTheme THEME = WordTheme.ANIMALS;

    /** {@code wordbattle.duel.min-word-length} plus one, as the bot is asked. */
    private static final int BOT_MIN_LENGTH = 4;

    /** Mid-range, so the bot draws on both halves of the theme's vocabulary. */
    private static final double BOT_RATING = 900;

    /**
     * Turns played out. A player wins on their ninth word, so this is a whole
     * duel bar the last move — long enough for the chain to be steered around
     * the alphabet and for a thin letter to show itself if there is one.
     */
    private static final int TURNS = 8;

    @Autowired
    private DuelService duels;

    @Autowired
    private MatchmakingService matchmaking;

    @Autowired
    private DictionaryService dictionary;

    @Autowired
    private UserService users;

    @Autowired
    private SocketRegistry sockets;

    @Autowired
    private ObjectMapper mapper;

    private long player;

    @AfterEach
    void endTheDuel() {
        if (player != 0) {
            duels.forfeit(player);
            sockets.disconnect(player);
        }
    }

    @Test
    void anOtherwisePerfectWordIsRefusedWhenItIsNotTheThemes() throws IOException {
        List<JsonNode> frames = start();
        DuelSession session = duels.duelOf(player).orElseThrow();

        String offTheme = offThemeWordFor(session);
        assertThat(dictionary.isValid(offTheme)).as("'%s' is a word the game accepts", offTheme).isTrue();

        duels.submit(player, offTheme);

        JsonNode rejected = payloadOf(frames, "duel.rejected");
        assertThat(rejected.path("code").asText()).isEqualTo("off_theme");
        // The message names the theme rather than calling it a non-word: the
        // player typed something real and has to be told what refused it.
        assertThat(rejected.path("message").asText()).contains(THEME.label());
        assertThat(snapshot(session)).as("the chain is untouched").hasSize(1);
    }

    @Test
    void aWordFromInsideTheThemeIsPlayedAsAnyOtherWouldBe() throws IOException {
        start();
        DuelSession session = duels.duelOf(player).orElseThrow();

        String word = inThemeWordFor(session);
        duels.submit(player, word);

        assertThat(snapshot(session)).contains(word);
    }

    /**
     * The other half of the restriction, and the half a word list can only be
     * trusted on by watching it: eight turns of the bot's own answers, every
     * one of them out of the theme.
     *
     * <p>The duel is also required to still be running at the end. A themed
     * chain that reaches a letter the theme has no answer for ends on the spot
     * — {@code EndReason.NO_MOVES} for the bot, a run-out clock for the human —
     * so a theme too thin to play would show up here as a duel that finished
     * early rather than as a word out of place.
     */
    @Test
    void theBotPlaysTheWholeDuelFromInsideTheThemeAndNeverRunsOut() throws IOException {
        start();
        DuelSession session = duels.duelOf(player).orElseThrow();

        for (int turn = 1; turn <= TURNS; turn++) {
            String word = inThemeWordFor(session);
            assertThat(word).as("turn %d has no themed word left to play", turn).isNotNull();

            duels.submit(player, word);
            assertThat(snapshot(session)).as("turn %d: '%s' was refused", turn, word).contains(word);

            awaitBotReply(session, turn);
            assertThat(session.finished()).as("the duel ended on turn %d", turn).isFalse();

            String answer = snapshot(session).get(turn * 2);
            assertThat(dictionary.isInTheme(THEME, answer))
                    .as("turn %d: the bot answered '%s', which is not a %s word", turn, answer, THEME.id())
                    .isTrue();
        }
    }

    @Test
    void theBoardIsToldWhichThemeItIsPlaying() throws IOException {
        List<JsonNode> frames = start();

        assertThat(payloadOf(frames, "match.found").path("theme").asText()).isEqualTo(THEME.label());

        // And on every state frame after it: a player whose app was relaunched
        // mid-duel is never sent match.found again.
        duels.submit(player, inThemeWordFor(duels.duelOf(player).orElseThrow()));
        assertThat(payloadOf(frames, "duel.update").path("theme").asText()).isEqualTo(THEME.label());
    }

    @Test
    void aDuelWithNoThemeIsTheOneItAlwaysWas() throws IOException {
        player = users.createDevUser("Untethered player").getId();
        List<JsonNode> frames = connect(player);
        matchmaking.joinAgainstBot(player, BOT_RATING, null);

        DuelSession session = duels.duelOf(player).orElseThrow();
        assertThat(session.theme()).isNull();
        // Null on the wire, and left out of the frame altogether by the shipped
        // jackson.default-property-inclusion — which the test profile replaces,
        // so what can be read here is the value rather than the omission.
        assertThat(payloadOf(frames, "match.found").path("theme").isNull()).isTrue();

        // A word no theme carries, which an untethered duel has no reason to
        // refuse.
        String word = dictionary.botMove(session.requiredLetter(), session.used(), BOT_MIN_LENGTH, BOT_RATING);
        duels.submit(player, word);
        assertThat(snapshot(session)).contains(word);
    }

    @Test
    void aThemeThisServerHasNeverHeardOfStartsNoDuelAtAll() throws IOException {
        player = users.createDevUser("Theme inventor").getId();
        List<JsonNode> frames = connect(player);

        matchmaking.joinAgainstBot(player, BOT_RATING, "dinosaurs-of-mars");

        assertThat(payloadOf(frames, "error").path("code").asText()).isEqualTo("unknown_theme");
        assertThat(duels.isPlaying(player)).isFalse();
    }

    // --------------------------------------------------------------- helpers

    /** A themed duel, started the way the app starts one. */
    private List<JsonNode> start() throws IOException {
        player = users.createDevUser("Themed player").getId();
        List<JsonNode> frames = connect(player);
        matchmaking.joinAgainstBot(player, BOT_RATING, THEME.id());
        assertThat(duels.isPlaying(player)).isTrue();
        return frames;
    }

    /**
     * A word this chain would accept. Taken from the bot's own themed pool:
     * everything the bot may answer with is something the player may say, and
     * asking for it here means the test never has to guess which letter the
     * chain has arrived at.
     */
    private String inThemeWordFor(DuelSession session) {
        synchronized (session) {
            return dictionary.botMove(THEME, session.requiredLetter(), session.used(), BOT_MIN_LENGTH, BOT_RATING);
        }
    }

    /** A word for the same letter that the dictionary knows and the theme does not. */
    private String offThemeWordFor(DuelSession session) {
        synchronized (session) {
            char letter = session.requiredLetter();
            return dictionary.hints(letter, session.used(), 40).stream()
                    .filter(word -> !dictionary.isInTheme(THEME, word))
                    .findFirst()
                    .orElseThrow(() -> new AssertionError("Every everyday '" + letter + "' word is in the theme"));
        }
    }

    /** The bot replies on a 1.2–2.4s timer of its own, so polling beats a sleep. */
    private void awaitBotReply(DuelSession session, int turn) {
        long deadline = System.currentTimeMillis() + 10_000;
        while (System.currentTimeMillis() < deadline) {
            if (session.finished() || snapshot(session).size() > turn * 2) return;
            try {
                Thread.sleep(25);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
        throw new AssertionError("The bot did not answer on turn " + turn);
    }

    /**
     * The chain under the session's monitor, as every reader on another thread
     * has to take it: the bot appends from a timer thread.
     */
    private List<String> snapshot(DuelSession session) {
        synchronized (session) {
            return session.chain().stream().map(DuelSession.ChainWord::word).toList();
        }
    }

    /** The stand-in socket {@code BotDuelRatingTest} uses, for the same reason. */
    private List<JsonNode> connect(long userId) throws IOException {
        List<JsonNode> frames = new ArrayList<>();
        WebSocketSession socket = mock(WebSocketSession.class);
        given(socket.isOpen()).willReturn(true);
        given(socket.getId()).willReturn("socket-" + userId);
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
        return frames;
    }

    /** The payload of the last frame of this type the socket was sent. */
    private JsonNode payloadOf(List<JsonNode> frames, String type) {
        synchronized (frames) {
            return frames.stream()
                    .filter(frame -> type.equals(frame.path("type").asText()))
                    .reduce((first, second) -> second)
                    .orElseThrow(() -> new AssertionError("No '" + type + "' frame was sent"))
                    .path("payload");
        }
    }
}
