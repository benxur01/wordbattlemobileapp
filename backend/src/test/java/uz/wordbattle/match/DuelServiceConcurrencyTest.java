package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;

/**
 * The two things about a duel that only go wrong when threads overlap, driven
 * through the service rather than a socket because the interleaving is the
 * whole point and a client cannot be made to produce it on cue.
 *
 * <p>Both cases are real: a player two friends challenge in the same instant,
 * and a player whose last duel is still being written to the database when the
 * next one ends. Neither test can force the exact interleaving — that is what
 * makes these bugs what they are — so each puts the server under enough of the
 * same pressure that a regression shows up, while the assertions themselves
 * hold no matter how the threads happen to land.
 */
@SpringBootTest
class DuelServiceConcurrencyTest {

    /** Races run per test: one is a coin toss, a dozen is a reliable verdict. */
    private static final int ROUNDS = 12;

    /** Duels settled back to back by one player, all fighting over their row. */
    private static final int SHARED_PLAYER_DUELS = 10;

    @Autowired
    private DuelService duels;

    @Autowired
    private UserService users;

    @Autowired
    private UserRepository userRepository;

    /**
     * Two challenges accepted at the same moment used to leave the player in two
     * duels at once, of which they were ever shown one. The other kept its timer
     * running with nobody watching and charged them for losing a duel they never
     * saw — an opponent's client, meanwhile, was happily playing it.
     */
    @Test
    void twoDuelsStartedForOnePlayerAtOnceLeaveThemInExactlyOne() throws Exception {
        ExecutorService threads = Executors.newFixedThreadPool(2);
        try {
            for (int round = 0; round < ROUNDS; round++) {
                long host = users.createDevUser("Race host " + round).getId();
                long left = users.createDevUser("Race left " + round).getId();
                long right = users.createDevUser("Race right " + round).getId();

                // Both threads reach start() as close to together as they can.
                CyclicBarrier ready = new CyclicBarrier(2);
                Future<DuelSession> first = threads.submit(() -> {
                    ready.await();
                    return duels.start(host, left);
                });
                Future<DuelSession> second = threads.submit(() -> {
                    ready.await();
                    return duels.start(host, right);
                });

                DuelSession leftDuel = first.get(10, TimeUnit.SECONDS);
                DuelSession rightDuel = second.get(10, TimeUnit.SECONDS);

                DuelSession live = leftDuel != null ? leftDuel : rightDuel;
                long turnedAway = leftDuel != null ? right : left;

                assertThat(leftDuel == null || rightDuel == null)
                        .as("round %d started two duels for one player", round)
                        .isTrue();
                assertThat(live).as("round %d started no duel at all", round).isNotNull();
                // The duel the host is registered for is the one that started:
                // the loser of the race left nothing of itself behind.
                assertThat(duels.duelOf(host)).hasValue(live);
                assertThat(duels.duelOf(turnedAway)).isEmpty();

                duels.forfeit(host);
            }
        } finally {
            threads.shutdownNow();
        }
    }

    /** The same refusal, seen from the caller's side and without any race. */
    @Test
    void aSecondDuelIsRefusedWhileTheFirstIsStillLive() {
        long player = users.createDevUser("Busy").getId();
        long first = users.createDevUser("Busy rival one").getId();
        long second = users.createDevUser("Busy rival two").getId();

        DuelSession started = duels.start(player, first);
        assertThat(started).isNotNull();

        assertThat(duels.start(player, second)).isNull();
        assertThat(duels.startAgainstBot(player)).isNull();
        assertThat(duels.duelOf(player)).hasValue(started);
        assertThat(duels.duelOf(second)).isEmpty();

        duels.forfeit(player);
    }

    /**
     * Results are written off the duel's own thread, so a player who forfeits
     * one duel and is thrown into the next has both settlements in flight at
     * once. Each reads their row, adds a battle to what it read and writes it
     * all back, and without the version column on the row whichever committed
     * last quietly dropped the other — a duel played for nothing.
     */
    @Test
    void settlementsThatShareAPlayerDoNotSwallowEachOther() throws Exception {
        long shared = users.createDevUser("Settle shared").getId();

        for (int duel = 0; duel < SHARED_PLAYER_DUELS; duel++) {
            long rival = users.createDevUser("Settle rival " + duel).getId();
            assertThat(duels.start(shared, rival)).isNotNull();
            // Deregistration is immediate and the writing is not, so the next
            // duel starts while this one is still on its way to the database.
            duels.forfeit(rival);
        }

        assertThat(awaitBattles(shared))
                .as("battles counted for a player who settled %d duels at once", SHARED_PLAYER_DUELS)
                .isEqualTo(SHARED_PLAYER_DUELS);
        User settled = userRepository.findById(shared).orElseThrow();
        assertThat(settled.getWins()).isEqualTo(SHARED_PLAYER_DUELS);
        // Every win moved the rating: a settlement that had been overwritten
        // would have taken its rating change with it.
        assertThat(settled.getRating()).isGreaterThan(1200);
    }

    /** Polls until the pool has drained, rather than guessing at a sleep. */
    private int awaitBattles(long userId) throws Exception {
        long deadline = System.currentTimeMillis() + 10_000;
        int battles = 0;
        while (System.currentTimeMillis() < deadline) {
            battles = userRepository.findById(userId).orElseThrow().getBattles();
            if (battles >= SHARED_PLAYER_DUELS) return battles;
            Thread.sleep(50);
        }
        return battles;
    }
}
