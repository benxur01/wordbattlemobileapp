package uz.wordbattle.match;

import org.junit.jupiter.api.extension.AfterEachCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.junit.jupiter.SpringExtension;
import uz.wordbattle.friend.PresenceService;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * Calls off the ten-second disconnect-grace forfeits a test leaves armed behind
 * it.
 *
 * <p>Closing a socket on a player who is still in a duel schedules one — that
 * is the whole point of {@code DuelService.connectionLost} — and the scheduler
 * it goes on belongs to a Spring context the test framework keeps alive for the
 * rest of the run. So a duel a socket test walked away from settles ten seconds
 * later, in the middle of a test that has nothing to do with it, and if a
 * context with its own mocked beans has rebuilt the schema in between, the
 * settlement fails on rows that are no longer there and puts a stack trace in
 * the log of an unrelated green test.
 *
 * <p>{@code @DirtiesContext} would also do it and costs far more than it looks:
 * closing the context runs {@code create-drop}'s drop against the in-memory
 * database every cached context shares, which takes the schema out from under
 * whichever of them runs next.
 *
 * <p>Every account is offered to both engines rather than only the players the
 * test knows about: cancelling a forfeit nobody armed is a map lookup that
 * finds nothing, and a test that fetched a token without ever reading the id
 * behind it would otherwise be the one that still leaks.
 */
class CancelPendingForfeits implements AfterEachCallback {

    /**
     * A socket close is handled on a container thread, so the arming can still
     * be in flight when the test's own teardown returns. {@code PresenceService}
     * is cleared on the line after both engines are told, which makes it the one
     * thing to wait on to know a forfeit is there to be cancelled rather than
     * about to be scheduled behind this extension's back.
     */
    private static final long CLOSE_HANDLED_TIMEOUT_MS = 5_000;

    @Override
    public void afterEach(ExtensionContext context) {
        ApplicationContext spring = SpringExtension.getApplicationContext(context);
        PresenceService presence = spring.getBean(PresenceService.class);
        DuelService duels = spring.getBean(DuelService.class);
        TeamDuelService teamDuels = spring.getBean(TeamDuelService.class);

        for (User account : spring.getBean(UserRepository.class).findAll()) {
            Long playerId = account.getId();
            awaitCloseHandled(presence, playerId);
            duels.connectionRestored(playerId);
            teamDuels.connectionRestored(playerId);
        }
    }

    private void awaitCloseHandled(PresenceService presence, Long playerId) {
        long deadline = System.currentTimeMillis() + CLOSE_HANDLED_TIMEOUT_MS;
        while (presence.isInBattle(playerId) && System.currentTimeMillis() < deadline) {
            try {
                Thread.sleep(5);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
    }
}
