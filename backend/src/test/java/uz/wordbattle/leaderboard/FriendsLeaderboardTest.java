package uz.wordbattle.leaderboard;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
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
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import uz.wordbattle.friend.Friendship;
import uz.wordbattle.friend.FriendshipRepository;

/**
 * The friends board and the friend list are the same roster shown two ways, and
 * they have to agree about who is still a player. A deleted account keeps its
 * row so that other people's match history still points somewhere, and that row
 * has a rating on it and no name at all — exactly the thing a ranking would
 * render as a blank row sitting above or below the player.
 */
@SpringBootTest
@AutoConfigureMockMvc
class FriendsLeaderboardTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private FriendshipRepository friendships;

    @Test
    void aDeletedFriendIsNotRankedOnTheFriendsBoard() throws Exception {
        String player = login("Nodira");
        String leaving = login("Sardor");
        claim(player, "nodira_l");
        claim(leaving, "sardor_l");
        long playerId = userId(player);
        long leavingId = userId(leaving);
        befriend(player, leaving);

        mvc.perform(delete("/api/users/me").header("Authorization", "Bearer " + leaving))
                .andExpect(status().isNoContent());

        // Deleting an account tears its friendship rows down in both directions
        // before the row is anonymised, which is why nobody had seen this go
        // wrong. Putting the edge back by hand is not a contrivance: nothing
        // stops the other player accepting a pending request in the same
        // instant the deletion runs, and the accepted edge then lands behind a
        // deletion that has already swept the table.
        assertThat(friendships.findByUserId(playerId)).isEmpty();
        friendships.save(new Friendship(playerId, leavingId));

        // The friend list has always filtered this out. The board has to agree.
        mvc.perform(get("/api/friends").header("Authorization", "Bearer " + player))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isEmpty());

        mvc.perform(get("/api/leaderboard/friends").header("Authorization", "Bearer " + player))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rows.length()").value(1))
                .andExpect(jsonPath("$.rows[0].user.nickname").value("nodira_l"))
                .andExpect(jsonPath("$.me.rank").value(1));
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

    private void befriend(String a, String b) throws Exception {
        String body = mvc.perform(post("/api/friends/requests")
                        .header("Authorization", "Bearer " + a)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":" + userId(b) + "}"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        long requestId = mapper.readTree(body).get("id").asLong();
        mvc.perform(post("/api/friends/requests/" + requestId + "/accept")
                        .header("Authorization", "Bearer " + b))
                .andExpect(status().isOk());
    }
}
