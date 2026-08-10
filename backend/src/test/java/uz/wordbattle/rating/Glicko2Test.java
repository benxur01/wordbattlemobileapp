package uz.wordbattle.rating;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import org.junit.jupiter.api.Test;
import uz.wordbattle.rating.Glicko2.Outcome;
import uz.wordbattle.rating.Glicko2.Rating;

class Glicko2Test {

    private static final Rating SETTLED = new Rating(1500, 60, 0.06);

    @Test
    void winningRaisesTheRatingAndLosingLowersIt() {
        Rating won = Glicko2.update(SETTLED, SETTLED, Outcome.WIN);
        Rating lost = Glicko2.update(SETTLED, SETTLED, Outcome.LOSS);

        assertThat(won.rating()).isGreaterThan(1500);
        assertThat(lost.rating()).isLessThan(1500);
    }

    @Test
    void beatingAStrongerOpponentIsWorthMore() {
        Rating stronger = new Rating(1800, 60, 0.06);
        Rating weaker = new Rating(1200, 60, 0.06);

        double vsStronger = Glicko2.update(SETTLED, stronger, Outcome.WIN).rating() - 1500;
        double vsWeaker = Glicko2.update(SETTLED, weaker, Outcome.WIN).rating() - 1500;

        assertThat(vsStronger).isGreaterThan(vsWeaker);
    }

    @Test
    void anUnprovenPlayerMovesFurtherThanASettledOne() {
        Rating unproven = new Rating(1500, 350, 0.06);

        double unprovenGain = Glicko2.update(unproven, SETTLED, Outcome.WIN).rating() - 1500;
        double settledGain = Glicko2.update(SETTLED, SETTLED, Outcome.WIN).rating() - 1500;

        assertThat(unprovenGain).isGreaterThan(settledGain);
    }

    @Test
    void deviationShrinksAsGamesArePlayed() {
        Rating rating = new Rating(1500, 350, 0.06);
        for (int i = 0; i < 15; i++) {
            rating = Glicko2.update(rating, SETTLED, i % 2 == 0 ? Outcome.WIN : Outcome.LOSS);
        }
        assertThat(rating.deviation()).isLessThan(350).isGreaterThanOrEqualTo(30);
    }

    @Test
    void deviationNeverLeavesItsBounds() {
        Rating rating = new Rating(1500, 30, 0.06);
        for (int i = 0; i < 200; i++) {
            rating = Glicko2.update(rating, SETTLED, Outcome.WIN);
            assertThat(rating.deviation()).isBetween(30.0, 350.0);
            assertThat(rating.volatility()).isPositive();
        }
    }

    /**
     * Everything above this point asks only for a direction — bigger, smaller,
     * shrinking, inside its bounds — and all of it stays green through a
     * rewrite that quietly changes the arithmetic. Using φ* where the paper
     * calls for φ' in the µ' update, or dropping a term from v, still moves the
     * winner up and the loser down. These two pin the numbers themselves.
     *
     * <p>Both figures come from outside this implementation, which is the whole
     * point of having them. They were worked out by hand from Glickman's
     * published Glicko-2 algorithm, and that hand calculation was checked
     * against the paper's own example first: a 1500/200/0.06 player meeting
     * 1400/30, 1550/100 and 1700/300 in one rating period, which the paper
     * gives as 1464.06 / 151.52 / 0.05999 and which it reproduces, down to the
     * tabulated g = 0.9955 and E = 0.639 for the 1400/30 opponent used here.
     *
     * <p>A hundredth of a rating point is far tighter than any change of
     * formula could slip through, and loose enough that nothing here depends on
     * the last bits of a double.
     */
    @Test
    void oneWinOverASettledOpponentLandsOnTheHandCalculatedValues() {
        Rating after = Glicko2.update(new Rating(1500, 200, 0.06), new Rating(1400, 30, 0.06), Outcome.WIN);

        assertThat(after.rating()).isCloseTo(1563.5642, within(0.01));
        assertThat(after.deviation()).isCloseTo(175.4027, within(0.01));
        // Volatility barely stirs after a single unsurprising result; the
        // tolerance is still a hundred times finer than the solver's own.
        assertThat(after.volatility()).isCloseTo(0.0599987, within(0.000001));
    }

    /**
     * The same pinning, but against a duel two fresh accounts actually played
     * on the live server rather than against a hand calculation: both started
     * at 1200 with a deviation of 350, and one game took them to 1362.31 and
     * 1037.69 with both deviations at 290.32.
     *
     * <p>Worth keeping alongside the case above because it is the shape almost
     * every real first duel has — two unproven players, evenly matched — and
     * because the symmetry is its own check: with the two sides identical going
     * in, whatever the winner gains the loser has to lose, and any asymmetry
     * slipped into the update shows up here as free or vanishing rating.
     */
    @Test
    void twoFreshPlayersMoveExactlyAsTheLiveServerMovedThem() {
        Rating fresh = new Rating(1200, 350, 0.06);
        Rating winner = Glicko2.update(fresh, fresh, Outcome.WIN);
        Rating loser = Glicko2.update(fresh, fresh, Outcome.LOSS);

        assertThat(winner.rating()).isCloseTo(1362.3109, within(0.01));
        assertThat(loser.rating()).isCloseTo(1037.6891, within(0.01));
        assertThat(winner.deviation()).isCloseTo(290.3190, within(0.01));
        assertThat(loser.deviation()).isCloseTo(290.3190, within(0.01));

        assertThat(winner.rating() - 1200).isCloseTo(1200 - loser.rating(), within(0.000001));
    }

    /**
     * Step 6, pinned the same way as the two above: φ* = √(φ² + σ²t) on the
     * internal scale, worked from the published formula rather than read back
     * out of this implementation. At σ = 0.06 the growth is deliberately slow —
     * ten periods away add barely three points to a deviation of 200 — because
     * the volatility is what says how erratic a player is, and a steady one
     * does not become a stranger over a fortnight.
     */
    @Test
    void sittingOutGrowsTheDeviationByTheHandCalculatedAmount() {
        assertThat(Glicko2.inflateForInactivity(200, 0.06, 10)).isCloseTo(202.6978131735176, within(0.0001));
        assertThat(Glicko2.inflateForInactivity(60, 0.06, 30)).isCloseTo(82.82035013194958, within(0.0001));
    }

    /** A player who never left is exactly as well known as their last game left them. */
    @Test
    void noTimeAwayLeavesTheDeviationAlone() {
        assertThat(Glicko2.inflateForInactivity(200, 0.06, 0)).isEqualTo(200);
    }

    /**
     * However long someone is gone, they come back no less known than an
     * account that has never played at all — the same ceiling {@link
     * Glicko2#update} holds every result to. Without it a long enough absence
     * would hand a returning player a bigger swing than a brand-new one gets.
     */
    @Test
    void noAbsenceIsWorseThanNeverHavingPlayed() {
        assertThat(Glicko2.inflateForInactivity(340, 0.06, 1000)).isEqualTo(350);
    }
}
