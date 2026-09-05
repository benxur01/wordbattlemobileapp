package uz.wordbattle.match;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ScheduledFuture;

/**
 * The live state of one 2v2 duel, held in memory for its (short) lifetime —
 * the four-participant counterpart to {@link DuelSession}, which this class
 * does not touch or extend: the two engines are kept fully separate so that
 * nothing built here can change how a 1v1 duel behaves.
 *
 * <p>The word-chain rules themselves are identical to {@link DuelSession}'s —
 * same seed word, same required-letter and rare-letter substitution logic,
 * same used-word set — only the participant model differs: four ids in a
 * fixed rotation instead of two in a binary toggle. Reuses
 * {@link DuelSession.ChainWord} rather than declaring a duplicate record,
 * since the shape of one played word is exactly the same either way.
 */
public class TeamDuelSession {

    private final String id;

    /** The two members of each side, in formation order (member one, member two). */
    private final List<Long> teamA;
    private final List<Long> teamB;

    /**
     * The fixed four-player cycle this duel rotates through:
     * team-A-member-one, team-B-member-one, team-A-member-two, team-B-member-two,
     * then back to the start. Decided at formation time and never reordered —
     * see {@link #next(long)}, which is this class's replacement for
     * {@link DuelSession#opponentOf(long)}.
     */
    private final List<Long> order;

    private final Instant startedAt = Instant.now();
    private final List<DuelSession.ChainWord> chain = new ArrayList<>();
    private final Set<String> used = new HashSet<>();
    private final Set<Character> rareLetters;

    private long turn;
    private Instant turnStartedAt;

    /** Counts turns the same way {@link DuelSession#turnNumber()} does, and for the same reason. */
    private long turnNumber = 1;

    private ScheduledFuture<?> turnTimer;
    private boolean finished;

    public TeamDuelSession(
            String id,
            long teamAMemberOne,
            long teamAMemberTwo,
            long teamBMemberOne,
            long teamBMemberTwo,
            String seedWord,
            Set<Character> rareLetters) {
        this.id = id;
        this.teamA = List.of(teamAMemberOne, teamAMemberTwo);
        this.teamB = List.of(teamBMemberOne, teamBMemberTwo);
        this.order = List.of(teamAMemberOne, teamBMemberOne, teamAMemberTwo, teamBMemberTwo);
        this.rareLetters = rareLetters;
        this.chain.add(new DuelSession.ChainWord(seedWord, 0L, 0));
        this.used.add(seedWord);
        this.turn = order.get(0);
        this.turnStartedAt = Instant.now();
    }

    public String id() { return id; }
    public List<Long> teamA() { return teamA; }
    public List<Long> teamB() { return teamB; }
    public List<Long> order() { return order; }
    public Instant startedAt() { return startedAt; }
    public List<DuelSession.ChainWord> chain() { return List.copyOf(chain); }
    public Set<String> used() { return Set.copyOf(used); }
    public long turn() { return turn; }
    public Instant turnStartedAt() { return turnStartedAt; }
    public long turnNumber() { return turnNumber; }
    public boolean finished() { return finished; }

    public boolean isTeamA(long playerId) {
        return teamA.contains(playerId);
    }

    /** Which of the two teams {@code playerId} plays for. */
    public List<Long> teamOf(long playerId) {
        return isTeamA(playerId) ? teamA : teamB;
    }

    /** The team {@code playerId} is <em>not</em> on. */
    public List<Long> opposingTeamOf(long playerId) {
        return isTeamA(playerId) ? teamB : teamA;
    }

    /** {@code playerId}'s own teammate. */
    public long partnerOf(long playerId) {
        List<Long> team = teamOf(playerId);
        return playerId == team.get(0) ? team.get(1) : team.get(0);
    }

    public boolean hasPlayer(long playerId) {
        return order.contains(playerId);
    }

    /**
     * Who plays next after {@code playerId}, walking the fixed rotation —
     * team-A-member-one, team-B-member-one, team-A-member-two,
     * team-B-member-two, and back round. This is the four-player replacement
     * for {@link DuelSession#opponentOf(long)}'s binary toggle.
     */
    public long next(long playerId) {
        int index = order.indexOf(playerId);
        return order.get((index + 1) % order.size());
    }

    // --------------------------------------------------------- chain rules
    // Identical to DuelSession's — see there for why the rare-letter
    // substitution exists at all. Copied rather than shared because the two
    // classes must stay independently editable: see this class's own javadoc.

    /** Letter the next word must start with — see {@link DuelSession#requiredLetter()}. */
    public char requiredLetter() {
        String last = lastWord();
        for (int i = last.length() - 1; i >= 0; i--) {
            char letter = last.charAt(i);
            if (!rareLetters.contains(letter)) return letter;
        }
        return last.charAt(last.length() - 1);
    }

    /** The letter {@link #requiredLetter()} stepped over, or null when nothing was substituted. */
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
        return chain.size() - 1;
    }

    public void addWord(String word, long playerId, int spentMs) {
        chain.add(new DuelSession.ChainWord(word, playerId, spentMs));
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
        List<DuelSession.ChainWord> mine = chain.stream().filter(w -> w.playerId() == playerId).toList();
        if (mine.isEmpty()) return 0;
        return (int) mine.stream().mapToInt(DuelSession.ChainWord::spentMs).average().orElse(0);
    }
}
