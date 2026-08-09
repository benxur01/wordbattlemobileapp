package uz.wordbattle.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.willAnswer;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import uz.wordbattle.friend.FriendRequestEntity.Status;
import uz.wordbattle.friend.FriendRequestRepository;
import uz.wordbattle.friend.FriendshipRepository;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.rating.RatingHistoryRepository;

/**
 * Deleting an account: the one operation in this app that is meant to destroy
 * data, and the one the store the app ships through will look for. It reaches
 * five repositories, strips a row of everything personal without deleting it,
 * and cuts the player out of whatever they were doing at the time — so it is
 * checked from both ends, the API the phone calls and the rows left behind.
 */
@SpringBootTest
@AutoConfigureMockMvc
class AccountDeletionTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    /** Spied rather than injected so one write can be made to lose its race. */
    @MockitoSpyBean
    private UserRepository users;

    @Autowired
    private UserWordRepository userWords;

    @Autowired
    private RatingHistoryRepository ratingHistory;

    @Autowired
    private FriendshipRepository friendships;

    @Autowired
    private FriendRequestRepository friendRequests;

    @Autowired
    private DuelService duels;

    @Test
    void deletingAnAccountTakesEverythingPersonalWithItAndLeavesAnAnonymousShell() throws Exception {
        String leaving = login("Zarina");
        String friend = login("Otabek");
        String stranger = login("Kamron");
        claim(leaving, "zarina_gone");
        claim(friend, "otabek_stays");
        claim(stranger, "kamron_asks");
        setCity(leaving, "Toshkent");

        long leavingId = userId(leaving);
        long friendId = userId(friend);
        befriend(leaving, friend);
        // An unanswered challenge from a third player, which belongs to the
        // account just as much as an accepted one does.
        request(stranger, leavingId);

        // Something in every table the deletion is supposed to reach: a settled
        // duel for the rating chart, and a word the player had learned.
        duels.start(leavingId, friendId);
        duels.forfeit(friendId);
        awaitRatingHistory(leavingId);
        userWords.save(new UserWord(leavingId, "battle"));

        mvc.perform(delete("/api/users/me").header("Authorization", "Bearer " + leaving))
                .andExpect(status().isNoContent());

        // The token outlives the account, and must stop working all the same.
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + leaving))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("user_not_found"));

        // Gone from the friend's side too, not just their own.
        mvc.perform(get("/api/friends").header("Authorization", "Bearer " + friend))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isEmpty());
        assertThat(friendships.findByUserId(leavingId)).isEmpty();
        assertThat(friendships.findByUserId(friendId)).isEmpty();
        assertThat(friendRequests.countByToUserIdAndStatus(leavingId, Status.PENDING)).isZero();
        assertThat(userWords.countByUserId(leavingId)).isZero();
        assertThat(ratingHistory.findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(leavingId, Instant.EPOCH))
                .isEmpty();

        // The row itself stays — the opponent's history points at it — with
        // nothing left on it that says who this was.
        User shell = users.findById(leavingId).orElseThrow();
        assertThat(shell.isDeleted()).isTrue();
        assertThat(shell.getNickname()).isNull();
        assertThat(shell.getDisplayName()).isNull();
        assertThat(shell.getCity()).isNull();
        // Releasing the sign-in identity is what makes signing in again a new
        // account rather than this one coming back.
        assertThat(shell.getGoogleSubject()).isNull();

        // And only this player was erased: the opponent keeps their record.
        assertThat(ratingHistory.findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(friendId, Instant.EPOCH))
                .isNotEmpty();
    }

    /**
     * Deleting mid-duel. The opponent has to be handed the win — a player who
     * no longer exists is not coming back to take their turn — and the result
     * has to be written before the deletion erases anything, or the settlement
     * would land behind it and put a rating-history row back on a row that has
     * just been emptied.
     */
    @Test
    void deletingMidDuelSettlesTheDuelFirstAndThenErases() throws Exception {
        String leaving = login("Shahzod");
        String opponent = login("Nigora");
        claim(leaving, "shahzod_out");
        claim(opponent, "nigora_wins");

        long leavingId = userId(leaving);
        long opponentId = userId(opponent);
        assertThat(duels.start(leavingId, opponentId)).isNotNull();

        mvc.perform(delete("/api/users/me").header("Authorization", "Bearer " + leaving))
                .andExpect(status().isNoContent());

        // No polling: the deletion does not return until the result is written.
        assertThat(duels.isPlaying(opponentId)).isFalse();
        User winner = users.findById(opponentId).orElseThrow();
        assertThat(winner.getBattles()).isEqualTo(1);
        assertThat(winner.getWins()).isEqualTo(1);
        assertThat(ratingHistory.findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(opponentId, Instant.EPOCH))
                .isNotEmpty();

        // The settlement wrote one of these for the leaving player as well; it
        // being gone is the proof that the deletion ran after it, not before.
        assertThat(ratingHistory.findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(leavingId, Instant.EPOCH))
                .isEmpty();
        assertThat(users.findById(leavingId).orElseThrow().isDeleted()).isTrue();
    }

    /**
     * The deletion losing the race for its own row. The {@code users} row is
     * versioned, and a duel of this player's settling in the same instant is
     * refused at commit — the wait before the erasing starts makes that rare
     * rather than impossible, because it gives up after a few seconds and lets
     * the deletion go ahead anyway. It used to come back to the player as a raw
     * failure on the one screen the store insists must work; now the erasing is
     * simply done again over fresh values.
     */
    @Test
    void aDeletionTheDatabaseRefusesIsDoneAgainInsteadOfFailingOnThePlayer() throws Exception {
        String leaving = login("Dilnoza");
        claim(leaving, "dilnoza_race");
        long leavingId = userId(leaving);
        userWords.save(new UserWord(leavingId, "battle"));

        // Refused exactly once, as a settlement committing in the gap would
        // refuse it. The attempt that follows is passed on to save() because
        // Mockito cannot hand an interface-backed repository its own method
        // back: the same write, without the immediate flush.
        AtomicBoolean firstWrite = new AtomicBoolean(true);
        willAnswer(invocation -> {
            if (firstWrite.getAndSet(false)) {
                throw new ObjectOptimisticLockingFailureException(User.class, leavingId);
            }
            return users.save(invocation.<User>getArgument(0));
        }).given(users).saveAndFlush(any(User.class));

        mvc.perform(delete("/api/users/me").header("Authorization", "Bearer " + leaving))
                .andExpect(status().isNoContent());

        User shell = users.findById(leavingId).orElseThrow();
        assertThat(shell.isDeleted()).isTrue();
        assertThat(shell.getNickname()).isNull();
        assertThat(shell.getGoogleSubject()).isNull();
        // The refused attempt was rolled back whole, so the one that replaced
        // it had to erase everything over again rather than carry on from the
        // middle of the first.
        assertThat(userWords.countByUserId(leavingId)).isZero();
    }

    // --------------------------------------------------------------- helpers

    private String login(String name) throws Exception {
        String body = mvc.perform(post("/api/auth/dev")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"displayName\":\"" + name + "\"}"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        return mapper.readTree(body).get("token").asText();
    }

    private void claim(String token, String nickname) throws Exception {
        mvc.perform(put("/api/users/me/nickname")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"" + nickname + "\"}"))
                .andExpect(status().isOk());
    }

    private void setCity(String token, String city) throws Exception {
        mvc.perform(put("/api/users/me/city")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"city\":\"" + city + "\"}"))
                .andExpect(status().isOk());
    }

    private long userId(String token) throws Exception {
        String body = mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + token))
                .andReturn()
                .getResponse()
                .getContentAsString();
        return mapper.readTree(body).get("id").asLong();
    }

    private long request(String from, long toUserId) throws Exception {
        String body = mvc.perform(post("/api/friends/requests")
                        .header("Authorization", "Bearer " + from)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":" + toUserId + "}"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        return mapper.readTree(body).get("id").asLong();
    }

    private void befriend(String a, String b) throws Exception {
        long requestId = request(a, userId(b));
        mvc.perform(post("/api/friends/requests/" + requestId + "/accept").header("Authorization", "Bearer " + b))
                .andExpect(status().isOk());
    }

    /** The duel settles on the duel pool, so the chart point arrives a moment later. */
    private void awaitRatingHistory(long userId) throws Exception {
        long deadline = System.currentTimeMillis() + 10_000;
        while (System.currentTimeMillis() < deadline) {
            if (!ratingHistory.findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(userId, Instant.EPOCH).isEmpty()) {
                return;
            }
            Thread.sleep(50);
        }
        throw new AssertionError("The duel never settled, so there was nothing to delete");
    }
}
