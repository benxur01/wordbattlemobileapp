package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import uz.wordbattle.dictionary.DictionaryService;
import uz.wordbattle.user.UserService;

/**
 * The rare-letter trap played out against the real bot: a chain steered into
 * "x" as often as the player can manage.
 *
 * <p>This is the exploit the substitution rule exists for. Roughly a thousand
 * words end in "x" and the bot's pool holds exactly one that starts with it —
 * "xerox", which ends in "x" again — so under the plain last-letter rule the
 * player can reach this position whenever they like, the bot answers "xerox",
 * and the second time around it has nothing at all: a NO_MOVES win for free, on
 * repeat, and a human opponent is every bit as stuck.
 *
 * <p>Driven through the service rather than a socket because the bot's answers
 * are the subject; what a client would see of them is a consequence.
 */
@SpringBootTest
class RareLetterTrapTest {

    /** Times the trap has to be sprung. One is a fluke; the second one is fatal. */
    private static final int TRAPS = 3;

    /**
     * A player wins outright on their ninth word ({@code wordbattle.duel.
     * words-to-win}), so everything has to happen inside eight turns.
     */
    private static final int MAX_TURNS = 8;

    /** {@code wordbattle.duel.min-word-length}. */
    private static final int MIN_WORD_LENGTH = 3;

    /**
     * Words ending in "x", covering every letter the chain can hand over so the
     * trap is available on almost every turn. A few are obscure — "x" is a rare
     * ending precisely because English has so few of them — but each one is in
     * the dictionary the server accepts, which is all a player needs.
     */
    private static final List<String> ENDS_IN_X = List.of(
            "apex", "annex", "box", "borax", "coax", "crux", "dux", "essex",
            "flux", "flex", "grex", "hoax", "hex", "index", "ibex", "jinx",
            "knox", "latex", "lynx", "matrix", "minx", "nix", "onyx", "prefix",
            "prix", "quincunx", "relax", "remix", "syntax", "six", "telex",
            "tax", "unix", "unfix", "vertex", "vex", "wax", "xerox", "yex", "zax");

    /** A consistent look at the session — see {@link #snapshot}. */
    private record Snapshot(boolean finished, List<String> words, long turn) {}

    @Autowired
    private DuelService duels;

    @Autowired
    private DictionaryService dictionary;

    @Autowired
    private UserService users;

    private DuelSession session;

    @AfterEach
    void endTheDuel() {
        if (session != null && !session.finished()) duels.forfeit(session.playerOne());
    }

    @Test
    void aChainSteeredIntoTheTrapAgainAndAgainStillPlaysOn() {
        long player = users.createDevUser("Trap setter").getId();
        session = duels.startAgainstBot(player);
        assertThat(session).isNotNull();

        int sprung = 0;
        for (int turn = 1; turn <= MAX_TURNS && sprung < TRAPS; turn++) {
            // The trap runs dry only on the letters with a single "x" word to
            // their name; an ordinary word then carries the chain to the next
            // one rather than ending the duel early.
            String trap = trapFor(session);
            String word = trap != null ? trap : ordinaryWordFor(session);
            assertThat(word).as("turn %d has nothing legal left to play", turn).isNotNull();

            duels.submit(player, word);
            assertThat(snapshot(session).words()).as("turn %d: '%s' was refused", turn, word).contains(word);

            awaitBotReply(turn);
            Snapshot state = snapshot(session);
            assertThat(state.finished())
                    .as("turn %d: '%s' left the bot with nothing to play", turn, word)
                    .isFalse();

            if (trap == null) continue;
            sprung++;
            // The bot answered the letter before the "x" rather than the "x"
            // itself, which is the whole of the fix: its one move for "x" is
            // "xerox", and after that there is no second.
            assertThat(state.words().get(turn * 2))
                    .as("turn %d answer to '%s'", turn, trap)
                    .startsWith(String.valueOf(trap.charAt(trap.length() - 2)));
        }

        assertThat(sprung).as("the trap was sprung %d times, not %d", sprung, TRAPS).isEqualTo(TRAPS);
        assertThat(snapshot(session).turn()).isEqualTo(player);
    }

    /** The next word ending in "x" that fits the chain, or null if none is left. */
    private String trapFor(DuelSession session) {
        synchronized (session) {
            char needed = session.requiredLetter();
            for (String word : ENDS_IN_X) {
                if (word.charAt(0) == needed && !session.alreadyUsed(word)) return word;
            }
            return null;
        }
    }

    /** Any word that keeps the chain going. Every bot word is a legal player word. */
    private String ordinaryWordFor(DuelSession session) {
        synchronized (session) {
            return dictionary.botMove(session.requiredLetter(), session.used(), MIN_WORD_LENGTH);
        }
    }

    /** The bot replies on a 1.2–2.4s timer of its own, so polling beats a sleep. */
    private void awaitBotReply(int turn) {
        long deadline = System.currentTimeMillis() + 10_000;
        while (System.currentTimeMillis() < deadline) {
            Snapshot state = snapshot(session);
            if (state.finished() || state.words().size() > turn * 2) return;
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
     * Reads the session under its monitor, as every reader on another thread
     * has to: the bot appends to the chain from a timer thread, and a list read
     * mid-append sees a chain that never existed.
     */
    private Snapshot snapshot(DuelSession session) {
        synchronized (session) {
            return new Snapshot(
                    session.finished(),
                    session.chain().stream().map(DuelSession.ChainWord::word).toList(),
                    session.turn());
        }
    }
}
