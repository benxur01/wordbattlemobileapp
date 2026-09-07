package uz.wordbattle.match;

import java.time.Instant;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ScheduledFuture;
import uz.wordbattle.dictionary.WordTheme;

/**
 * The live state of one duel, held in memory for its (short) lifetime. Every
 * rule that decides the outcome is applied here, on the server — the client is
 * only ever told what happened.
 */
public class DuelSession {

    /** Stand-in id for the bot opponent, which has no user row. */
    public static final long BOT_ID = -1L;

    public record ChainWord(String word, long playerId, int spentMs) {}

    private final String id;
    private final long playerOne;
    private final long playerTwo;
    private final boolean botOpponent;

    /**
     * What the bot in this duel is rated, and 0 for a duel between two people.
     *
     * <p>It is one number doing two jobs, which is why it is kept here rather
     * than only on the profile the human is shown: it is what that profile says,
     * and it is what {@code DictionaryService.botMove} picks the bot's words
     * with. A duel started as a fallback computes it from the human's own
     * rating; one the player asked for carries the rating they chose. Fixed for
     * the duel either way — a bot that grew easier halfway through would be a
     * strange thing to explain.
     */
    private final double botRating;

    /**
     * The topic this duel is played inside, or null for one played against the
     * whole dictionary — which is every duel but a themed bot practice.
     *
     * <p>It decides what either side may say ({@code DuelService.validate}) and
     * where the bot's own words come from, and it is fixed for the duel: a
     * theme that changed halfway through would invalidate the chain already
     * played.
     */
    private final WordTheme theme;

    private final Instant startedAt = Instant.now();
    private final List<ChainWord> chain = new ArrayList<>();
    private final Set<String> used = new HashSet<>();
    private final Set<Character> rareLetters;

    /**
     * The four power-ups already spent in this duel — see {@link PowerUp}, and
     * {@code DuelService.usePowerUp} for the rules around them.
     *
     * <p>One set rather than one per player, which is the same thing here: only
     * a duel against the bot has them at all, and such a duel has exactly one
     * human in it. It is never written anywhere; a duel is the whole life of a
     * charge.
     */
    private final Set<PowerUp> spentPowerUps = EnumSet.noneOf(PowerUp.class);

    private long turn;
    private Instant turnStartedAt;

    /**
     * Seconds bought with {@link PowerUp#ADD_TIME}, on top of the turn's own
     * length — so the turn ends at {@link #turnStartedAt()} plus the configured
     * length plus this. Cleared by {@link #passTurnTo}: what was bought was one
     * turn, not the rest of the duel.
     */
    private int turnBonusMs;

    /**
     * The letter {@link PowerUp#SKIP_LETTER} turned down, refused by
     * {@link #requiredLetter()} exactly as a rare one is, and forgotten by
     * {@link #addWord} — the skip buys a way out of one letter, not a rule for
     * the duel. Null whenever no skip is standing.
     */
    private Character skippedLetter;

    /**
     * Whether {@link PowerUp#PRESSURE} is waiting to be spent on the bot's next
     * reply — read and cleared by {@code DuelService.scheduleBotMove}.
     */
    private boolean botPressured;

    /**
     * Which turn is being played, counting from one. It exists so that a turn
     * timer going off can prove the turn it was armed for is still the one on
     * the board: a task the scheduler has already begun cannot be cancelled, so
     * a player answering in the last instant leaves an expiry running for a turn
     * that is over — see {@code DuelService.onTurnExpired}.
     *
     * <p>{@link #extendTurn} moves it too, without the turn changing hands.
     * Lengthening a turn re-arms its timer, and the timer already running has to
     * be told it is no longer the live one; this is the mechanism that exists
     * for saying so, and a second one beside it would only be the same guard
     * spelled differently.
     *
     * <p>A counter rather than {@link #turnStartedAt}, which changes on every
     * pass and looks like it would do: two turns can carry the same instant when
     * the clock is coarser than the gap between them, and a timestamp that
     * happened to repeat would wave the stale timer through without a sound.
     * Counting cannot collide.
     */
    private long turnNumber = 1;

    private ScheduledFuture<?> turnTimer;
    private boolean finished;

    public DuelSession(
            String id,
            long playerOne,
            long playerTwo,
            boolean botOpponent,
            double botRating,
            WordTheme theme,
            String seedWord,
            Set<Character> rareLetters) {
        this.id = id;
        this.playerOne = playerOne;
        this.playerTwo = playerTwo;
        this.botOpponent = botOpponent;
        this.botRating = botRating;
        this.theme = theme;
        this.rareLetters = rareLetters;
        // The seed word belongs to nobody: it only fixes the starting letter.
        this.chain.add(new ChainWord(seedWord, 0L, 0));
        this.used.add(seedWord);
        this.turn = playerOne;
        this.turnStartedAt = Instant.now();
    }

    public String id() { return id; }
    public long playerOne() { return playerOne; }
    public long playerTwo() { return playerTwo; }
    public boolean botOpponent() { return botOpponent; }
    public double botRating() { return botRating; }
    public WordTheme theme() { return theme; }
    public Instant startedAt() { return startedAt; }
    public List<ChainWord> chain() { return List.copyOf(chain); }
    public Set<String> used() { return Set.copyOf(used); }
    public long turn() { return turn; }
    public Instant turnStartedAt() { return turnStartedAt; }
    public int turnBonusMs() { return turnBonusMs; }
    public long turnNumber() { return turnNumber; }
    public boolean finished() { return finished; }

    public long opponentOf(long playerId) {
        return playerId == playerOne ? playerTwo : playerOne;
    }

    public boolean hasPlayer(long playerId) {
        return playerId == playerOne || playerId == playerTwo;
    }

    /**
     * Letter the next word must start with: the last letter of the last word,
     * unless that letter is one nobody can answer.
     *
     * <p>English leaves a couple of dead ends. About a thousand words end in
     * "x" while the bot knows exactly one that starts with it — "xerox", which
     * ends in "x" again — so "wax" opens a two-move loop that either side can
     * force and neither can leave; "z" is the same trap over about six turns. A
     * bigger dictionary does not help, because the words it adds are
     * "xanthidium" and its like, which no player would ever type. So a chain
     * that lands on such a letter walks back to the last ordinary letter of the
     * word and hands that over instead. Word-chain games settle this the same
     * way — shiritori passes on the preceding kana — which is why players read
     * it as a rule rather than as the judge losing its nerve.
     *
     * <p>Which letters count is {@code wordbattle.duel.rare-letters}, plus —
     * in a themed duel — the letters that theme has no answers for, which are
     * dead ends for exactly the same reason inside a few hundred words as "x"
     * is inside 358k. See {@code DictionaryService.thinLetters}.
     *
     * <p>A letter a player has spent {@link PowerUp#SKIP_LETTER} on is walked
     * past by the same rule while their skip stands, which is what makes the
     * power-up a rule the game already had rather than a second one beside it.
     */
    public char requiredLetter() {
        String last = lastWord();
        for (int i = last.length() - 1; i >= 0; i--) {
            char letter = last.charAt(i);
            if (!rareLetters.contains(letter) && !wasSkipped(letter)) return letter;
        }
        // "jazz" ends on two rare letters and the walk steps past both, but a
        // word made of nothing else has no easier letter to offer: better the
        // plain rule than no rule at all.
        return last.charAt(last.length() - 1);
    }

    /**
     * The letter {@link #requiredLetter()} stepped over, or null when the chain
     * ends on an ordinary one and nothing was skipped. The client mentions the
     * substitution only on the turn it happens: a rule a player meets once in a
     * few duels reads as a bug unless it explains itself in the moment it fires.
     *
     * <p>A skip names the letter the player turned down rather than the word's
     * ending, which are the same letter unless the rare-letter rule had already
     * moved the chain off it — and then it is the one they were looking at when
     * they spent the charge that they have to be told about.
     */
    public Character substitutedFrom() {
        char required = requiredLetter();
        if (skippedLetter != null) return required == skippedLetter ? null : skippedLetter;
        char ending = lastWord().charAt(lastWord().length() - 1);
        return required == ending ? null : ending;
    }

    /**
     * Whether {@link #substitutedFrom()} is naming a skipped letter rather than
     * a rare one. The two read as completely different things to a player — one
     * is the game's own rule, the other is what they just asked for — so the
     * client is told which of them it is looking at.
     */
    public boolean letterWasSkipped() {
        return skippedLetter != null && requiredLetter() != skippedLetter;
    }

    private boolean wasSkipped(char letter) {
        return skippedLetter != null && letter == skippedLetter;
    }

    private String lastWord() {
        return chain.get(chain.size() - 1).word();
    }

    public boolean alreadyUsed(String word) {
        return used.contains(word);
    }

    public int wordsBy(long playerId) {
        return (int) chain.stream().filter(w -> w.playerId() == playerId).count();
    }

    public int chainLength() {
        // The seed word is not anyone's move.
        return chain.size() - 1;
    }

    public void addWord(String word, long playerId, int spentMs) {
        chain.add(new ChainWord(word, playerId, spentMs));
        used.add(word);
        // The chain has moved on, so the letter that was skipped is behind it.
        this.skippedLetter = null;
    }

    public void passTurnTo(long playerId) {
        this.turn = playerId;
        this.turnStartedAt = Instant.now();
        this.turnBonusMs = 0;
        this.turnNumber++;
    }

    // ------------------------------------------------------------ power-ups

    /**
     * Takes the charge for {@code powerUp}, or refuses when it has already been
     * spent. Every use goes through here, so the one-per-duel rule is a single
     * line rather than a check each caller has to remember.
     *
     * @return false when this duel's charge for it is gone
     */
    public boolean spendPowerUp(PowerUp powerUp) {
        return spentPowerUps.add(powerUp);
    }

    /** Adds to the turn now being played. The caller re-arms the timer. */
    public void extendTurn(int bonusMs) {
        this.turnBonusMs += bonusMs;
        // Not a new turn to either player, but a new one to whichever timer is
        // running for it — see turnNumber's own note.
        this.turnNumber++;
    }

    /** Turns down the letter the chain is asking for, in favour of the next one. */
    public void skipLetter() {
        this.skippedLetter = requiredLetter();
    }

    /** Arms {@link PowerUp#PRESSURE} for the bot's next reply. */
    public void pressureBot() {
        this.botPressured = true;
    }

    /** @return true once per {@link #pressureBot()}, for the reply it was aimed at. */
    public boolean takePressure() {
        boolean pressured = botPressured;
        this.botPressured = false;
        return pressured;
    }

    public void setTurnTimer(ScheduledFuture<?> future) {
        cancelTimer();
        this.turnTimer = future;
    }

    /**
     * The expiry now armed for this turn. Package-private, for the one question
     * only it can answer: {@code PowerUpTest} holds that adding time moves the
     * moment the server itself will end the turn, and a frame saying so proves
     * nothing — the bug being guarded against is exactly a bigger number sent to
     * a client whose turn still expires on the old schedule.
     */
    ScheduledFuture<?> turnTimer() {
        return turnTimer;
    }

    public void cancelTimer() {
        if (turnTimer != null) {
            turnTimer.cancel(false);
            turnTimer = null;
        }
    }

    /** Marks the duel finished; returns false when it already was. */
    public synchronized boolean finish() {
        if (finished) return false;
        finished = true;
        cancelTimer();
        return true;
    }

    public int averageMsOf(long playerId) {
        List<ChainWord> mine = chain.stream().filter(w -> w.playerId() == playerId).toList();
        if (mine.isEmpty()) return 0;
        return (int) mine.stream().mapToInt(ChainWord::spentMs).average().orElse(0);
    }
}
