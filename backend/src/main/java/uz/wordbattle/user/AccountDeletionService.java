package uz.wordbattle.user;

import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
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

    /**
     * How many times the erasing is tried when the database turns it down. The
     * only thing it ever loses its row to is a duel of this player's settling in
     * the same instant, and the wait in {@code forfeitAndAwaitSettlement} has
     * already given that every chance to land first, so a second attempt is
     * plenty; the third is there because a deletion that comes back as an error
     * is a store requirement failing in front of the player.
     */
    private static final int ERASE_ATTEMPTS = 3;

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
    private final TransactionTemplate transactions;

    public AccountDeletionService(
            UserRepository users,
            FriendshipRepository friendships,
            FriendRequestRepository friendRequests,
            UserWordRepository userWords,
            RatingHistoryRepository ratingHistory,
            SessionEnder sessionEnder,
            PlatformTransactionManager transactionManager) {
        this.users = users;
        this.friendships = friendships;
        this.friendRequests = friendRequests;
        this.userWords = userWords;
        this.ratingHistory = ratingHistory;
        this.sessionEnder = sessionEnder;
        this.transactions = new TransactionTemplate(transactionManager);
    }

    /**
     * Erases the account, trying again if the database refuses the write.
     *
     * <p>The {@code users} row is versioned, and a settlement racing this one
     * for it is refused at commit — which used to come back to the player as a
     * raw failure, on the one screen the store insists must work. The wait in
     * {@code DuelService.forfeitAndAwaitSettlement} makes that rare rather than
     * impossible: it gives up after five seconds and lets the deletion go ahead,
     * so a slow settlement can still commit in the gap between this reading the
     * row and writing it back.
     *
     * <p>Replaying the whole transaction is both safe and the right amount:
     * every step of it is written to be repeatable, and a settlement that landed
     * between the attempts has its rating-history row swept up by the next one
     * rather than surviving the deletion. The transaction is opened here rather
     * than declared on the method because only a fresh one can be retried — the
     * first attempt is rolled back whole, and there is nothing to carry over.
     */
    public void delete(Long userId) {
        // Out of any duel and off the socket before the row is so much as read:
        // a live session holding a now-anonymous account has nothing sensible
        // to render, and ending a duel writes its result from another thread.
        // Reading the player first would mean deleting rows that settlement was
        // still creating, and writing back over a rating it had already moved.
        sessionEnder.endSessionOf(userId);

        for (int attempt = 1; ; attempt++) {
            try {
                transactions.executeWithoutResult(status -> erase(userId));
                return;
            } catch (OptimisticLockingFailureException e) {
                if (attempt == ERASE_ATTEMPTS) throw e;
                log.warn("Account {} deletion lost a race for its row (attempt {} of {})",
                        userId, attempt, ERASE_ATTEMPTS);
            }
        }
    }

    private void erase(Long userId) {
        User user = users.findById(userId)
                .orElseThrow(() -> ApiException.notFound("user_not_found", "Foydalanuvchi topilmadi"));
        if (user.isDeleted()) return;

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
