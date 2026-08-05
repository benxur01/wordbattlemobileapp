package uz.wordbattle.user;

import java.util.List;
import uz.wordbattle.user.ProfileDto.Badge;

/** The eight tiles on the profile screen, derived from the player's stats. */
public final class BadgeCatalog {

    private BadgeCatalog() {}

    public static List<Badge> forUser(User user) {
        return List.of(
                badge("first_battle", "Ilk jang", user.getBattles(), 1),
                badge("streak_7", "7 kun", user.getStreakDays(), 7),
                badge("wins_50", "50 g'alaba", user.getWins(), 50),
                badge("chain_20", "20 zanjir", user.getLongestChain(), 20),
                badge("rating_1500", "1500", (int) Math.round(user.getRating()), 1500),
                badge("streak_30", "30 kun", user.getStreakDays(), 30),
                badge("friend_top", "Do'st №1", 0, 1),
                badge("words_1000", "1000 so'z", user.getWordsLearned(), 1000));
    }

    private static Badge badge(String code, String label, int progress, int target) {
        return new Badge(code, label, progress >= target, Math.min(progress, target), target);
    }
}
