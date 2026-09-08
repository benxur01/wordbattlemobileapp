package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import uz.wordbattle.match.MatchEntity.EndReason;
import uz.wordbattle.user.AccountDeletionService;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;

/**
 * A 2v2 duel settled with one of its four players gone — deleted while the
 * duel was still running.
 *
 * <p>It used to cost all four of them everything: the settlement threw on the
 * missing row, {@code TeamDuelService.recordResult} caught it as it catches any
 * settlement failure, and three players who had just finished a duel were
 * handed a zero delta, no battle, no streak and no learned words. The three who
 * are still here now settle against the side that is left, which for four fresh
 * accounts is arithmetically the same duel — so their deltas are held here
 * against the ones the same duel produces with nobody missing.
 */
@SpringBootTest
class TeamSettlementWithAMissingPlayerTest {

    @Autowired
    private TeamMatchResultService results;

    @Autowired
    private UserService users;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private AccountDeletionService deletions;

    @Autowired
    private TeamMatchRepository matches;

    /** The four ids of one duel, in the order the session takes them. */
    private record Four(long a1, long a2, long b1, long b2) {}

    private Four fourPlayers(String namePrefix) {
        return new Four(
                users.createDevUser(namePrefix + " A one").getId(),
                users.createDevUser(namePrefix + " A two").getId(),
                users.createDevUser(namePrefix + " B one").getId(),
                users.createDevUser(namePrefix + " B two").getId());
    }

    /** A finished-looking chain: the seed plus one word from each of the four. */
    private TeamDuelSession sessionOf(Four four) {
        TeamDuelSession session = new TeamDuelSession(
                "t-" + UUID.randomUUID(), four.a1(), four.a2(), four.b1(), four.b2(), "start", Set.of('x', 'z'));
        List<Long> order = session.order();
        List<String> words = List.of("tiger", "river", "rocket", "tunnel");
        for (int i = 0; i < order.size(); i++) {
            session.addWord(words.get(i), order.get(i), 2_000);
        }
        return session;
    }

    @Test
    void theThreeWhoAreStillHereSettleAsIfTheFourthHadBeenThere() {
        // The same duel twice: once whole, once a player short. Every account
        // is fresh, so both sides average to the same synthetic opponent
        // whether it stands for two players or one — the deltas have to match.
        Four whole = fourPlayers("Whole team");
        TeamMatchResultService.Outcome expected = results.record(sessionOf(whole), true, EndReason.WORDS_LIMIT);
        int winnerDelta = expected.forPlayer(whole.a1()).delta();
        int loserDelta = expected.forPlayer(whole.b1()).delta();
        assertThat(winnerDelta).isPositive();
        assertThat(loserDelta).isNegative();

        Four shortHanded = fourPlayers("Short team");
        deletions.delete(shortHanded.b2());

        TeamMatchResultService.Outcome outcome = results.record(sessionOf(shortHanded), true, EndReason.WORDS_LIMIT);

        assertThat(outcome.forPlayer(shortHanded.a1()).delta()).isEqualTo(winnerDelta);
        assertThat(outcome.forPlayer(shortHanded.a2()).delta()).isEqualTo(winnerDelta);
        assertThat(outcome.forPlayer(shortHanded.b1()).delta()).isEqualTo(loserDelta);

        // And written down, not only reported: the delta a player is shown has
        // to be the one their row actually moved by.
        assertThat(rating(shortHanded.a1())).isEqualTo(outcome.forPlayer(shortHanded.a1()).ratingAfter());
        assertThat(rating(shortHanded.b1())).isEqualTo(outcome.forPlayer(shortHanded.b1()).ratingAfter());
        assertThat(battles(shortHanded.a1())).isEqualTo(1);
        assertThat(battles(shortHanded.a2())).isEqualTo(1);
        assertThat(battles(shortHanded.b1())).isEqualTo(1);
    }

    @Test
    void theMissingPlayerIsWrittenNothingAndReadsBackZeros() {
        Four four = fourPlayers("Nothing written");
        int ratingBeforeDeletion = rating(four.b2());
        deletions.delete(four.b2());

        TeamMatchResultService.Outcome outcome = results.record(sessionOf(four), true, EndReason.WORDS_LIMIT);

        TeamMatchResultService.PlayerResult gone = outcome.forPlayer(four.b2());
        assertThat(gone.delta()).isZero();
        assertThat(gone.ratingAfter()).isZero();
        // The shell is left exactly as the deletion left it. Writing a rating,
        // a battle or a streak back onto it is the thing account deletion
        // promises will not happen.
        assertThat(rating(four.b2())).isEqualTo(ratingBeforeDeletion);
        assertThat(battles(four.b2())).isZero();
    }

    /**
     * Every player column of {@code team_matches} is {@code not null}, so a
     * duel three of whose four players are left has no row to be written as.
     * That is the whole of what the missing one costs the others now.
     */
    @Test
    void noMatchRowIsWrittenForADuelThatLostAPlayer() {
        Four four = fourPlayers("No row");
        deletions.delete(four.b2());
        long before = matches.count();

        TeamMatchResultService.Outcome outcome = results.record(sessionOf(four), true, EndReason.WORDS_LIMIT);

        assertThat(outcome.matchId()).isNull();
        assertThat(matches.count()).isEqualTo(before);
    }

    @Test
    void aWholeDuelIsStillWrittenDownAsBefore() {
        Four four = fourPlayers("Still written");
        long before = matches.count();

        TeamMatchResultService.Outcome outcome = results.record(sessionOf(four), true, EndReason.WORDS_LIMIT);

        assertThat(outcome.matchId()).isNotNull();
        assertThat(matches.count()).isEqualTo(before + 1);
    }

    private int rating(long userId) {
        return (int) Math.round(row(userId).getRating());
    }

    private int battles(long userId) {
        return row(userId).getBattles();
    }

    private User row(long userId) {
        return userRepository.findById(userId).orElseThrow();
    }
}
