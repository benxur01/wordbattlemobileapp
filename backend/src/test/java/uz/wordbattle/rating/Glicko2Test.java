package uz.wordbattle.rating;

import static org.assertj.core.api.Assertions.assertThat;

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
}
