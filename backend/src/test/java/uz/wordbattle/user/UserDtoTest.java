package uz.wordbattle.user;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import uz.wordbattle.rating.Glicko2;

class UserDtoTest {

    /**
     * The deviation an account is created with is the one case the badge exists
     * for, so it is pinned against {@link Glicko2#MAX_DEVIATION} itself rather
     * than a number copied out of it — a retune that lowers the starting
     * deviation past the cutoff has to be noticed here.
     */
    @Test
    void aBrandNewAccountReadsAsProvisional() {
        assertThat(UserDto.of(new User()).provisional()).isTrue();
        assertThat(Glicko2.MAX_DEVIATION).isGreaterThan(UserDto.PROVISIONAL_DEVIATION);
    }

    @Test
    void aSettledAccountDoesNot() {
        User settled = new User();
        settled.setRatingDeviation(60);

        assertThat(UserDto.of(settled).provisional()).isFalse();
    }

    /** The cutoff itself is still unreliable; only what is under it is not. */
    @Test
    void theThresholdIsInclusive() {
        User user = new User();

        user.setRatingDeviation(UserDto.PROVISIONAL_DEVIATION);
        assertThat(UserDto.of(user).provisional()).isTrue();

        user.setRatingDeviation(UserDto.PROVISIONAL_DEVIATION - 0.01);
        assertThat(UserDto.of(user).provisional()).isFalse();
    }

    /**
     * The path a real account actually takes out of the badge: ten duels
     * against evenly-matched opposition, which is what the cutoff was chosen
     * against. Fewer than five must not clear it — that is the whole point of
     * putting the badge where it is — and ten must.
     */
    @Test
    void tenEvenlyMatchedDuelsClearTheBadgeAndFiveDoNot() {
        Glicko2.Rating rating = new Glicko2.Rating(400, Glicko2.MAX_DEVIATION, 0.06);
        Glicko2.Rating opponent = new Glicko2.Rating(400, Glicko2.MAX_DEVIATION, 0.06);

        for (int i = 0; i < 5; i++) {
            rating = Glicko2.update(rating, opponent, i % 2 == 0 ? Glicko2.Outcome.WIN : Glicko2.Outcome.LOSS);
        }
        assertThat(rating.deviation()).isGreaterThan(UserDto.PROVISIONAL_DEVIATION);

        for (int i = 5; i < 10; i++) {
            rating = Glicko2.update(rating, opponent, i % 2 == 0 ? Glicko2.Outcome.WIN : Glicko2.Outcome.LOSS);
        }
        assertThat(rating.deviation()).isLessThan(UserDto.PROVISIONAL_DEVIATION);
    }
}
