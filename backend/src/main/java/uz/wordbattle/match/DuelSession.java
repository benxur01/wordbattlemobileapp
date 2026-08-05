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

    private long turn;
    private Instant turnStartedAt;
    private ScheduledFuture<?> turnTimer;
    private boolean finished;

    public DuelSession(String id, long playerOne, long playerTwo, boolean botOpponent, String seedWord) {
        this.id = id;
        this.playerOne = playerOne;
        this.playerTwo = playerTwo;
        this.botOpponent = botOpponent;
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
    public boolean finished() { return finished; }

    public long opponentOf(long playerId) {
        return playerId == playerOne ? playerTwo : playerOne;
    }

    public boolean hasPlayer(long playerId) {
        return playerId == playerOne || playerId == playerTwo;
    }

    /** Letter the next word must start with. */
    public char requiredLetter() {
        String last = chain.get(chain.size() - 1).word();
        return last.charAt(last.length() - 1);
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
