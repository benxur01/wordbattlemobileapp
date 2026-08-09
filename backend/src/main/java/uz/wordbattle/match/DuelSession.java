package uz.wordbattle.match;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ScheduledFuture;

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
    private final Instant startedAt = Instant.now();
    private final List<ChainWord> chain = new ArrayList<>();
    private final Set<String> used = new HashSet<>();
    private final Set<Character> rareLetters;

    private long turn;
    private Instant turnStartedAt;

    /**
     * Which turn is being played, counting from one. It exists so that a turn
     * timer going off can prove the turn it was armed for is still the one on
     * the board: a task the scheduler has already begun cannot be cancelled, so
     * a player answering in the last instant leaves an expiry running for a turn
     * that is over — see {@code DuelService.onTurnExpired}.
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
            String seedWord,
            Set<Character> rareLetters) {
        this.id = id;
        this.playerOne = playerOne;
        this.playerTwo = playerTwo;
        this.botOpponent = botOpponent;
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
    public Instant startedAt() { return startedAt; }
    public List<ChainWord> chain() { return List.copyOf(chain); }
    public Set<String> used() { return Set.copyOf(used); }
    public long turn() { return turn; }
    public Instant turnStartedAt() { return turnStartedAt; }
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
     * <p>Which letters count is {@code wordbattle.duel.rare-letters}.
     */
    public char requiredLetter() {
        String last = lastWord();
        for (int i = last.length() - 1; i >= 0; i--) {
            char letter = last.charAt(i);
            if (!rareLetters.contains(letter)) return letter;
        }
        // "jazz" ends on two rare letters and the walk steps past both, but a
        // word made of nothing else has no easier letter to offer: better the
        // plain rule than no rule at all.
        return last.charAt(last.length() - 1);
    }

    /**
     * The letter {@link #requiredLetter()} stepped over, or null when the chain
     * ends on an ordinary one. The client mentions the substitution only on the
     * turn it happens: a rule a player meets once in a few duels reads as a bug
     * unless it explains itself in the moment it fires.
     */
    public Character substitutedFrom() {
        String last = lastWord();
        char ending = last.charAt(last.length() - 1);
        return requiredLetter() == ending ? null : ending;
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
    }

    public void passTurnTo(long playerId) {
        this.turn = playerId;
        this.turnStartedAt = Instant.now();
        this.turnNumber++;
    }

    public void setTurnTimer(ScheduledFuture<?> future) {
        cancelTimer();
        this.turnTimer = future;
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
