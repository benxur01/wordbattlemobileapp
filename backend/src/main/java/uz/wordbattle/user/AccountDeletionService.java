package uz.wordbattle.user;

import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.friend.FriendRequestRepository;
import uz.wordbattle.friend.FriendshipRepository;
import uz.wordbattle.rating.RatingHistoryRepository;

/**
 * Deletes a player's account, which the store this app ships through requires
 * to be reachable from inside the app.
 *
 * <p>Everything that belongs to the player alone is deleted outright:
 * friendships, pending requests, their learned-word list, their rating chart.
 * The {@code users} row itself is kept but stripped of every identifying field
 * — other players' match history points at it, and erasing their record of a
 * duel they played is not this player's to do. What remains is an anonymous
 * shell: no Google identity, no nickname, no name, no city.
 *
 * <p>Releasing the Google subject matters: it means signing in again starts a
 * genuinely new account rather than resurrecting this one.
 */
@Service
public class AccountDeletionService {

    private static final Logger log = LoggerFactory.getLogger(AccountDeletionService.class);

    /** Broken by the socket layer, which the user package must not depend on. */
    public interface SessionEnder {
        void endSessionOf(long userId);
    }

    private final UserRepository users;
    private final FriendshipRepository friendships;
    private final FriendRequestRepository friendRequests;
    private final UserWordRepository userWords;
    private final RatingHistoryRepository ratingHistory;
    private final SessionEnder sessionEnder;

    public AccountDeletionService(
            UserRepository users,
            FriendshipRepository friendships,
            FriendRequestRepository friendRequests,
            UserWordRepository userWords,
            RatingHistoryRepository ratingHistory,
            SessionEnder sessionEnder) {
        this.users = users;
        this.friendships = friendships;
        this.friendRequests = friendRequests;
        this.userWords = userWords;
        this.ratingHistory = ratingHistory;
        this.sessionEnder = sessionEnder;
    }

    @Transactional
    public void delete(Long userId) {
        User user = users.findById(userId)
                .orElseThrow(() -> ApiException.notFound("user_not_found", "Foydalanuvchi topilmadi"));
        if (user.isDeleted()) return;

        // Out of any duel and off the socket first: a live session holding a
        // now-anonymous account has nothing sensible to render.
        sessionEnder.endSessionOf(userId);

        friendships.deleteByUserId(userId);
        friendships.deleteByFriendId(userId);
        friendRequests.deleteByFromUserIdOrToUserId(userId, userId);
        userWords.deleteByUserId(userId);
        ratingHistory.deleteByUserId(userId);

        user.anonymise(Instant.now());
        users.saveAndFlush(user);
        log.info("Account {} deleted", userId);
    }
}
