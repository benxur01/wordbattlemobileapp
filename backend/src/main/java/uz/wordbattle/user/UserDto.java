package uz.wordbattle.user;

import uz.wordbattle.rating.Glicko2;

/** The compact user shape the client renders in avatars, rows and headers. */
public record UserDto(
        Long id,
        String nickname,
        String displayName,
        String initial,
        String city,
        int rating,
        int streakDays,
        boolean provisional) {

    /**
     * The deviation at or above which a rating is shown as provisional — not
     * wrong, just not yet a placement on the ladder anyone should read as one.
     *
     * <p>Every account starts at {@link Glicko2#MAX_DEVIATION} (180) and
     * {@link Glicko2#update} clamps down to a floor of 30, so the cutoff has to
     * sit high enough to be cleared in a session or two and low enough that the
     * rating has stopped lurching by the time it is. 110 is about ten settled
     * duels against evenly-matched opposition: 180 falls to 164 after one, to
     * roughly 130 by the fifth, and crosses 110 somewhere between the ninth and
     * the twelfth depending on how decisive the results were. Past it a single
     * duel moves the rating by a dozen points rather than the 50-75 two
     * brand-new accounts swing.
     *
     * <p>Deliberately well above what one result can clear, so the badge cannot
     * disappear off a single lucky game, and low enough that
     * {@link Glicko2#inflateForInactivity} only carries a settled player back
     * over it after months away — at which point the rating genuinely is stale
     * again and marking it is the point rather than a side effect.
     */
    public static final double PROVISIONAL_DEVIATION = 110;

    public static UserDto of(User user) {
        return new UserDto(
                user.getId(),
                user.getNickname(),
                user.getDisplayName(),
                user.initial(),
                user.getCity(),
                (int) Math.round(user.getRating()),
                user.getStreakDays(),
                user.getRatingDeviation() >= PROVISIONAL_DEVIATION);
    }
}
