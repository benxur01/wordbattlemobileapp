package uz.wordbattle.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willAnswer;
import static org.mockito.Mockito.mock;
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
import org.springframework.data.domain.PageRequest;
import org.springframework.http.MediaType;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.socket.WebSocketSession;
import uz.wordbattle.friend.FriendRequestEntity.Status;
import uz.wordbattle.friend.FriendRequestRepository;
import uz.wordbattle.friend.FriendshipRepository;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.match.MatchRepository;
import uz.wordbattle.rating.RatingHistoryRepository;
import uz.wordbattle.ws.SocketRegistry;

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
    private MatchRepository matches;

    /** Spied so a duel can be started from inside the deletion window. */
    @MockitoSpyBean
    private DuelService duels;

    @Autowired
    private SocketRegistry sockets;

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
        // It is refused at the door rather than by the endpoint behind it: the
        // generation an account's tokens are measured against is read only for
        // a row that is not marked deleted, so an erased account has none and
        // nothing it ever issued authenticates anybody. That also covers the
        // socket, which has no endpoint to notice the shell for it.
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + leaving))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthorized"));

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
     * A duel that <em>starts</em> while the account is being deleted, rather
     * than one that was already running.
     *
     * <p>Deleting takes two steps and there is time between them: the session
     * is ended first — matchmaking, invites, and a wait of up to five seconds
     * for any duel of theirs to settle — and only then is the row erased.
     * Nothing about that first step used to stop a new duel: the player's
     * socket stayed open and authenticated for the whole of it, so an invite
     * accepted or a queue frame landing in that window started a duel that
     * {@code forfeitAndAwaitSettlement} had never waited for, because it did
     * not exist yet. When that duel ended, minutes later, the settlement read
     * the player back with a plain {@code findById}, saw nothing wrong with the
     * anonymous shell, and wrote a rating, a battle, a win, a streak, a
     * rating-history point and a list of learned words onto an account the
     * store had been told was erased.
     *
     * <p>Both halves of the answer are checked here. The socket is gone before
     * the wait begins, which is what makes the window unreachable in
     * production — every path into a duel needs a socket, either the player's
     * own frame or a registry lookup by whoever is starting it. And the
     * settlement refuses the shell regardless, which is what holds for a duel
     * that got in anyway; the duel below is started by hand for exactly that
     * reason, since a race measured in microseconds is not something a test can
     * schedule.
     *
     * <p>Here the leaving player is the duel's second, which is the half of the
     * question the settlement always got right — see the test below it for the
     * other half.
     */
    @Test
    void aDuelThatStartsInsideTheDeletionWindowWritesNothingOntoTheShell() throws Exception {
        duelStartedInsideTheDeletionWindow("Kamola", "Jasur", false);
    }

    /**
     * The same duel with the sides swapped, which is not the same test at all.
     *
     * <p>A settlement is anchored on the duel's first player: the match row's
     * {@code player_one_id} cannot be null, so the whole of it used to be
     * abandoned the moment that slot came back empty. With the deleting player
     * sitting in it, their opponent — who has done nothing but accept a
     * challenge — silently lost the battle, the streak, the words they had
     * learned and the match row itself, while the very same duel with the two
     * of them the other way round recorded all four. Which slot a player lands
     * in is not chance either: it is whoever waited longer in the queue, or
     * whoever sent the invite.
     *
     * <p>So the surviving side is moved into the first slot before anything is
     * written, and both orderings now come out here identically — the shell
     * untouched, the survivor's duel recorded and unrated.
     */
    @Test
    void aShellInTheDuelsFirstSlotStillCostsTheSurvivorNothing() throws Exception {
        duelStartedInsideTheDeletionWindow("Zilola", "Bekzod", true);
    }

    /**
     * @param shellPlaysFirst which slot the deleting player takes when the duel
     *     inside the window starts — the one thing the two tests above differ by,
     *     and the one thing that must make no difference to anything below.
     */
    private void duelStartedInsideTheDeletionWindow(
            String leavingName, String opponentName, boolean shellPlaysFirst) throws Exception {

        String leaving = login(leavingName);
        String opponent = login(opponentName);
        claim(leaving, leavingName.toLowerCase() + "_gone");
        claim(opponent, opponentName.toLowerCase() + "_left");

        long leavingId = userId(leaving);
        long opponentId = userId(opponent);

        // A socket for the leaving player, because "was it closed in time" is
        // half of what this test is about and there is nothing to close
        // otherwise. A stand-in rather than a real one: this class drives the
        // API through MockMvc and has no server to open a socket against.
        WebSocketSession socket = mock(WebSocketSession.class);
        given(socket.isOpen()).willReturn(true);
        given(socket.getId()).willReturn("socket-of-the-leaving-player");
        sockets.register(leavingId, socket);

        AtomicBoolean reachableAtTheWait = new AtomicBoolean(true);
        willAnswer(invocation -> {
            // Inside the session teardown, at the point it starts waiting for
            // settlements. A player still reachable here is a player who can
            // still be pulled into a duel.
            reachableAtTheWait.set(sockets.isConnected(leavingId));
            Object result = invocation.callRealMethod();
            // And one is, standing in for the invite that is accepted a
            // microsecond too early.
            long first = shellPlaysFirst ? leavingId : opponentId;
            long second = shellPlaysFirst ? opponentId : leavingId;
            assertThat(duels.start(first, second))
                    .as("the duel this test is about never started")
                    .isNotNull();
            return result;
        })
                .given(duels)
                .forfeitAndAwaitSettlement(leavingId);

        mvc.perform(delete("/api/users/me").header("Authorization", "Bearer " + leaving))
                .andExpect(status().isNoContent());

        assertThat(reachableAtTheWait)
                .as("the socket was still open while the deletion waited, so a frame could still start a duel")
                .isFalse();

        // The duel now ends the way it would have: the opponent walks out and
        // the account that no longer exists is handed the win. Waited for
        // rather than polled — the settlement is what this test is watching.
        duels.forfeitAndAwaitSettlement(opponentId);

        User shell = users.findById(leavingId).orElseThrow();
        assertThat(shell.isDeleted()).isTrue();
        assertThat(shell.getBattles()).isZero();
        assertThat(shell.getWins()).isZero();
        assertThat(shell.getStreakDays()).isZero();
        assertThat(shell.getRating()).isEqualTo(400);
        assertThat(ratingHistory.findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(leavingId, Instant.EPOCH))
                .isEmpty();
        assertThat(userWords.countByUserId(leavingId)).isZero();

        // The player who is still here is not punished for it, from either
        // slot: the duel is recorded, counted and kept in their history, and
        // their opponent's absence costs them only the rating — an unrated
        // result, as a bot duel is, because there is nobody left on the other
        // side of it to have won or lost anything.
        User survivor = users.findById(opponentId).orElseThrow();
        assertThat(survivor.getBattles()).as("the survivor's battle count").isEqualTo(1);
        assertThat(survivor.getStreakDays()).as("the survivor's streak").isEqualTo(1);
        assertThat(matches.findHistory(opponentId, PageRequest.of(0, 10)))
                .as("the survivor's own record of a duel they really played")
                .hasSize(1);
        assertThat(ratingHistory.findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(opponentId, Instant.EPOCH))
                .isEmpty();
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
