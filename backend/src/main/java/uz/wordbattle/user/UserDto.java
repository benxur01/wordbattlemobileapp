package uz.wordbattle.user;

/** The compact user shape the client renders in avatars, rows and headers. */
public record UserDto(
        Long id,
        String nickname,
        String displayName,
        String initial,
        String city,
        int rating,
        int streakDays) {

    public static UserDto of(User user) {
        return new UserDto(
                user.getId(),
                user.getNickname(),
                user.getDisplayName(),
                user.initial(),
                user.getCity(),
                (int) Math.round(user.getRating()),
                user.getStreakDays());
    }
}
