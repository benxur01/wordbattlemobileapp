package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Set;
import org.junit.jupiter.api.Test;

class DuelSessionTest {

    /** The shipped {@code wordbattle.duel.rare-letters}. */
    private static final Set<Character> RARE = Set.of('x', 'z');

    /** No bot in any of these, so the bot's rating is the 0 a human duel carries. */
    private DuelSession session() {
        return new DuelSession("duel-1", 10L, 20L, false, 0, null, "battle", RARE);
    }

    @Test
    void theSeedWordFixesTheStartingLetterButBelongsToNobody() {
        DuelSession session = session();

        assertThat(session.requiredLetter()).isEqualTo('e');
        assertThat(session.chainLength()).isZero();
        assertThat(session.wordsBy(10L)).isZero();
        assertThat(session.wordsBy(20L)).isZero();
    }

    @Test
    void eachWordMovesTheRequiredLetterAlong() {
        DuelSession session = session();

        session.addWord("east", 10L, 1200);
        assertThat(session.requiredLetter()).isEqualTo('t');
        session.addWord("tiger", 20L, 900);
        assertThat(session.requiredLetter()).isEqualTo('r');

        // Ordinary endings are handed over untouched, and say so.
        assertThat(session.substitutedFrom()).isNull();

        assertThat(session.chainLength()).isEqualTo(2);
        assertThat(session.wordsBy(10L)).isEqualTo(1);
        assertThat(session.alreadyUsed("east")).isTrue();
        assertThat(session.alreadyUsed("river")).isFalse();
    }

    @Test
    void aChainEndingOnARareLetterMovesOnToTheOneBeforeIt() {
        DuelSession session = session();

        // Without the substitution "earwax" is a win on the spot: one common
        // word starts with "x" and it ends in "x" as well.
        session.addWord("earwax", 10L, 1200);

        assertThat(session.requiredLetter()).isEqualTo('a');
        assertThat(session.substitutedFrom()).isEqualTo('x');
    }

    @Test
    void aRunOfRareLettersIsSteppedOverInOneGo() {
        DuelSession session = session();
        session.addWord("east", 10L, 1200);

        session.addWord("topaz", 20L, 900);
        assertThat(session.requiredLetter()).isEqualTo('a');
        assertThat(session.substitutedFrom()).isEqualTo('z');

        // Two rare letters back to back: handing over the second "z" would be
        // the same dead end one letter along.
        session.addWord("abuzz", 10L, 900);
        assertThat(session.requiredLetter()).isEqualTo('u');
        assertThat(session.substitutedFrom()).isEqualTo('z');
    }

    @Test
    void theWalkBackwardsCannotRunOffTheFrontOfAWord() {
        // Neither shape can reach the chain — words are validated against the
        // dictionary and must be three letters long — but the walk must not
        // depend on that to stay inside the string.
        DuelSession allRare = new DuelSession("duel-2", 10L, 20L, false, 0, null, "zzz", RARE);
        assertThat(allRare.requiredLetter()).isEqualTo('z');
        assertThat(allRare.substitutedFrom()).isNull();

        DuelSession twoLetters = new DuelSession("duel-3", 10L, 20L, false, 0, null, "ox", RARE);
        assertThat(twoLetters.requiredLetter()).isEqualTo('o');
        assertThat(twoLetters.substitutedFrom()).isEqualTo('x');
    }

    @Test
    void opponentLookupWorksBothWays() {
        DuelSession session = session();

        assertThat(session.opponentOf(10L)).isEqualTo(20L);
        assertThat(session.opponentOf(20L)).isEqualTo(10L);
        assertThat(session.hasPlayer(30L)).isFalse();
    }

    @Test
    void averageTimeCountsOnlyThatPlayersWords() {
        DuelSession session = session();
        session.addWord("east", 10L, 1000);
        session.addWord("tiger", 20L, 5000);
        session.addWord("rock", 10L, 3000);

        assertThat(session.averageMsOf(10L)).isEqualTo(2000);
        assertThat(session.averageMsOf(20L)).isEqualTo(5000);
    }

    @Test
    void everyPassOfTheTurnIsANewTurnNumber() {
        DuelSession session = session();
        long opening = session.turnNumber();

        session.passTurnTo(20L);
        long second = session.turnNumber();
        session.passTurnTo(10L);

        // What a turn timer is armed with, and the only reason the number
        // exists: it has to move every single time the turn does, or an expiry
        // left behind by a turn already played still looks current and times
        // out whoever has just taken over. Two instants could repeat; a count
        // cannot.
        assertThat(second).isGreaterThan(opening);
        assertThat(session.turnNumber()).isGreaterThan(second);
    }

    @Test
    void aDuelCanOnlyFinishOnce() {
        DuelSession session = session();

        assertThat(session.finish()).isTrue();
        assertThat(session.finish()).isFalse();
        assertThat(session.finished()).isTrue();
    }
}
