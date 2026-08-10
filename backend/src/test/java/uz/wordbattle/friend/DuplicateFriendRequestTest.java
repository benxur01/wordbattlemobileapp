package uz.wordbattle.friend;

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
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * The friend request a player sends twice. Sent twice in a row it has always
 * been harmless — the second call finds the pending row and hands it back — but
 * sent twice in the same instant, as a double-tap does, both calls got past
 * that check and raced to insert. The database refused the second, and the
 * refusal reached the player as a 500 "Kutilmagan xatolik" for pressing a
 * button twice.
 */
@SpringBootTest
@AutoConfigureMockMvc
class DuplicateFriendRequestTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    /** Spied so the insert can be refused the way the index refuses it. */
    @MockitoSpyBean
    private FriendRequestRepository requests;

    @Test
    void aRequestThatLosesTheRaceToInsertIsAConflictRatherThanACrash() throws Exception {
        String sender = login("Sevara");
        String target = login("Ulugbek");
        claim(sender, "sevara_p");
        claim(target, "ulugbek_p");
        long targetId = userId(target);

        // The index that does the refusing is ux_friend_requests_pending, over
        // (from_user_id, to_user_id) where status = 'PENDING'. It is a partial
        // index, so it is created by the migration and lives only on
        // PostgreSQL; these tests run against H2 on a schema generated from the
        // entities, which has no such index and would happily take both rows.
        // Refusing the write here is that index standing in — and it is refused
        // however the row is written, so this says nothing about whether the
        // insert is flushed by hand or left to the commit.
        DataIntegrityViolationException refused =
                new DataIntegrityViolationException("ux_friend_requests_pending");
        willThrow(refused).given(requests).saveAndFlush(any(FriendRequestEntity.class));
        willThrow(refused).given(requests).save(any(FriendRequestEntity.class));

        mvc.perform(post("/api/friends/requests")
                        .header("Authorization", "Bearer " + sender)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":" + targetId + "}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("request_already_sent"));
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
}
