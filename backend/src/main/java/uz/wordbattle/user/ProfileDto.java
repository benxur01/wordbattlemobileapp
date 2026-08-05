package uz.wordbattle.user;

import java.time.Instant;
import java.util.List;

/** Everything the profile screen draws, in one response. */
public record ProfileDto(
        UserDto user,
        long globalRank,
        int battles,
        int wins,
        int winPercent,
        int longestChain,
        int wordsLearned,
        int streakDays,
        int weeklyDelta,
        List<RatingPoint> ratingHistory,
        List<Badge> badges) {

    public record RatingPoint(Instant at, int rating) {}

    /** Unlocked badges are rendered filled, locked ones dashed. */
    public record Badge(String code, String label, boolean unlocked, int progress, int target) {}
}
