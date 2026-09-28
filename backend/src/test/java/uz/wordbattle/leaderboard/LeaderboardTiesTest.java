package uz.wordbattle.leaderboard;

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
import org.springframework.data.domain.PageRequest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * Players on the same rating hold the same place — 1, 1, 3 — on both boards
 * and on the profile alike. The global board used to number its rows by
 * position while the pinned row and the profile counted everyone strictly
 * higher, so the second of two players level at the top was listed second and
 * pinned first. The friends board numbered by position too, in whatever order
 * the sort happened to leave a tie in.
 */
@SpringBootTest
@AutoConfigureMockMvc
class LeaderboardTiesTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private UserRepository users;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @Test
    void playersLevelOnTheGlobalBoardShareARank() throws Exception {
        // The database is shared with every other test class in this context,
        // and the global board is global: the three players go in above
        // whoever is on the ladder already, so they are its first three rows.
        double top = users.topByRating(PageRequest.of(0, 1)).stream()
                .mapToDouble(User::getRating)
                .max()
                .orElse(0);
        double level = Math.floor(top) + 1000;

        player("Dilnoza", "tie_global_a", level);
        String second = player("Tester", "tie_global_b", level);
        player("Sardor", "tie_global_c", level - 1);

        mvc.perform(get("/api/leaderboard/global").header("Authorization", "Bearer " + second))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rows[0].user.nickname").value("tie_global_a"))
                .andExpect(jsonPath("$.rows[0].rank").value(1))
                .andExpect(jsonPath("$.rows[1].user.nickname").value("tie_global_b"))
                .andExpect(jsonPath("$.rows[1].rank").value(1))
                .andExpect(jsonPath("$.rows[1].self").value(true))
                .andExpect(jsonPath("$.rows[2].user.nickname").value("tie_global_c"))
                .andExpect(jsonPath("$.rows[2].rank").value(3))
                .andExpect(jsonPath("$.me.rank").value(1));

        mvc.perform(get("/api/users/me/profile").header("Authorization", "Bearer " + second))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.globalRank").value(1));
    }

    @Test
    void friendsLevelOnTheFriendsBoardShareARankInIdOrder() throws Exception {
        // Made before the player, so by id this friend comes first in the tie —
        // the reverse of the order the roster is put together in, which always
        // starts with the player.
        String level = player("Kamola", "tie_friend_a", 700);
        String me = player("Jasur", "tie_friend_me", 700);
        String above = player("Aziz", "tie_friend_b", 900);
        String below = player("Malika", "tie_friend_c", 500);
        befriend(me, level);
        befriend(me, above);
        befriend(me, below);

        mvc.perform(get("/api/leaderboard/friends").header("Authorization", "Bearer " + me))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rows.length()").value(4))
                .andExpect(jsonPath("$.rows[0].user.nickname").value("tie_friend_b"))
                .andExpect(jsonPath("$.rows[0].rank").value(1))
                .andExpect(jsonPath("$.rows[1].user.nickname").value("tie_friend_a"))
                .andExpect(jsonPath("$.rows[1].rank").value(2))
                .andExpect(jsonPath("$.rows[2].user.nickname").value("tie_friend_me"))
                .andExpect(jsonPath("$.rows[2].rank").value(2))
                .andExpect(jsonPath("$.rows[2].self").value(true))
                .andExpect(jsonPath("$.rows[3].user.nickname").value("tie_friend_c"))
                .andExpect(jsonPath("$.rows[3].rank").value(4))
                .andExpect(jsonPath("$.me.rank").value(2));
    }

    // --------------------------------------------------------------- helpers

    /** A signed-in player with a nickname — which the global board requires — on exactly {@code rating}. */
    private String player(String name, String nickname, double rating) throws Exception {
        String token = login(name);
        claim(token, nickname);
        long id = userId(token);
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            User user = users.findById(id).orElseThrow();
            user.setRating(rating);
            users.save(user);
        });
        return token;
    }

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
