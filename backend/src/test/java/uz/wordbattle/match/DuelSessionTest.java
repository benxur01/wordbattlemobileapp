package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class DuelSessionTest {

    private DuelSession session() {
        return new DuelSession("duel-1", 10L, 20L, false, "battle");
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

        assertThat(session.chainLength()).isEqualTo(2);
        assertThat(session.wordsBy(10L)).isEqualTo(1);
        assertThat(session.alreadyUsed("east")).isTrue();
        assertThat(session.alreadyUsed("river")).isFalse();
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
    void aDuelCanOnlyFinishOnce() {
        DuelSession session = session();

        assertThat(session.finish()).isTrue();
        assertThat(session.finish()).isFalse();
        assertThat(session.finished()).isTrue();
    }
}
