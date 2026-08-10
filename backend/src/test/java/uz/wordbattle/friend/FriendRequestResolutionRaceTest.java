package uz.wordbattle.friend;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.willThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import uz.wordbattle.friend.FriendRequestEntity.Status;

/**
 * The friend request answered twice in the same instant — the other half of what
 * {@link DuplicateFriendRequestTest} covers for sending one.
 *
 * <p>Answering is read-check-write with nothing holding the two ends together:
 * is this row still pending, and if so mark it and write the friendship. A
 * double-tapped "Qabul qilish" is two calls on the wire, and so is accepting
 * while the decline the thumb was resting on is still in flight. Both read
 * PENDING and both carried on — the second reached a friendship the first had
 * already written and came back as a raw 500 "Kutilmagan xatolik" for pressing a
 * button twice, and an accept that lost to a decline could leave the row
 * DECLINED with the edges the accept had made sitting beside it: a friend
 * neither player ever agreed to.
 *
 * <p>The version column on the row is what settles it, and it is simulated here
 * rather than raced for. Both refusals below are the database's — the version
 * check on {@code friend_requests}, and the unique constraint over a friendship
 * pair — and neither depends on how the row was written, so making the write
 * fail says the same thing as losing the race that makes it fail.
 */
@SpringBootTest
@AutoConfigureMockMvc
class FriendRequestResolutionRaceTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    /** Spied so the version check can refuse the write the way a lost race does. */
    @MockitoSpyBean
    private FriendRequestRepository requests;

    /** And so the pair constraint can refuse an edge somebody else just made. */
    @MockitoSpyBean
    private FriendshipRepository friendships;

    @Test
    void anAcceptThatLosesTheRaceForTheRequestIsAConflictRatherThanACrash() throws Exception {
        String sender = login("Nodira");
        String target = login("Alisher");
        claim(sender, "nodira_asks");
        claim(target, "alisher_taps");
        long senderId = userId(sender);
        long requestId = request(sender, userId(target));

        willThrow(new ObjectOptimisticLockingFailureException(FriendRequestEntity.class, requestId))
                .given(requests)
                .saveAndFlush(any(FriendRequestEntity.class));

        mvc.perform(post("/api/friends/requests/" + requestId + "/accept")
                        .header("Authorization", "Bearer " + target))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("request_resolved"));

        // And nothing of the losing call is left behind. This is the half that
        // matters most: an accept beaten by a decline must not leave a
        // friendship standing on a request the player turned down.
        assertThat(friendships.findByUserId(senderId)).isEmpty();
        assertThat(friendships.findByUserId(userId(target))).isEmpty();
    }

    /** The same race seen from the decline side, which loses it just as often. */
    @Test
    void aDeclineThatLosesTheRaceForTheRequestIsAConflictRatherThanACrash() throws Exception {
        String sender = login("Gulnora");
        String target = login("Rustam");
        claim(sender, "gulnora_asks");
        claim(target, "rustam_taps");
        long requestId = request(sender, userId(target));

        willThrow(new ObjectOptimisticLockingFailureException(FriendRequestEntity.class, requestId))
                .given(requests)
                .saveAndFlush(any(FriendRequestEntity.class));

        mvc.perform(post("/api/friends/requests/" + requestId + "/decline")
                        .header("Authorization", "Bearer " + target))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("request_resolved"));
    }

    /**
     * The friendship itself refused. Two players who challenged each other in
     * the same instant hold a pending request each, and accepting both writes
     * the very same pair of edges — a race the version column cannot see,
     * because the two calls are settling different rows.
     */
    @Test
    void anAcceptWhoseFriendshipTheDatabaseRefusesIsAConflictRatherThanACrash() throws Exception {
        String sender = login("Malika");
        String target = login("Sardor");
        claim(sender, "malika_asks");
        claim(target, "sardor_taps");
        long requestId = request(sender, userId(target));

        // uq_friendship, over (user_id, friend_id), standing in — and refusing
        // however the row is written, so this says nothing about whether the
        // insert is flushed by hand or left to the commit.
        DataIntegrityViolationException refused = new DataIntegrityViolationException("uq_friendship");
        willThrow(refused).given(friendships).saveAndFlush(any(Friendship.class));
        willThrow(refused).given(friendships).save(any(Friendship.class));

        mvc.perform(post("/api/friends/requests/" + requestId + "/accept")
                        .header("Authorization", "Bearer " + target))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("already_friends"));

        // Rolled back whole: a request marked answered with no friendship to
        // show for it would be a request nobody could ever answer again.
        assertThat(requests.findById(requestId).orElseThrow().getStatus()).isEqualTo(Status.PENDING);
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
}
