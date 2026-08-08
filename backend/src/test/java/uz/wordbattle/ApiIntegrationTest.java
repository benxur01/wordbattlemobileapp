package uz.wordbattle;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import uz.wordbattle.match.MatchEntity;
import uz.wordbattle.match.MatchRepository;

/** Walks the same path the app does: log in, claim a nickname, read the profile. */
@SpringBootTest
@AutoConfigureMockMvc
class ApiIntegrationTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private MatchRepository matches;

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

    @Test
    void protectedEndpointsRejectAnonymousCallers() throws Exception {
        mvc.perform(get("/api/users/me")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/friends")).andExpect(status().isUnauthorized());
    }

    @Test
    void devLoginIssuesAWorkingToken() throws Exception {
        String token = login("Jasur");

        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.displayName").value("Jasur"));
    }

    /** No network needed: the token is refused before any key lookup happens. */
    @Test
    void googleLoginRefusesATokenItCannotVerify() throws Exception {
        mvc.perform(post("/api/auth/google")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"idToken\":\"not-a-google-token\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("id_token_invalid"));
    }

    @Test
    void aNicknameCanBeClaimedOnlyOnce() throws Exception {
        String first = login("First");
        String second = login("Second");

        mvc.perform(get("/api/users/nickname/check").param("value", "otabek_z")
                        .header("Authorization", "Bearer " + first))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.available").value(true));

        mvc.perform(put("/api/users/me/nickname")
                        .header("Authorization", "Bearer " + first)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"otabek_z\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nickname").value("otabek_z"));

        // Same name, different case — still taken.
        String body = mvc.perform(get("/api/users/nickname/check").param("value", "OTABEK_Z")
                        .header("Authorization", "Bearer " + second))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        JsonNode check = mapper.readTree(body);
        assertThat(check.get("available").asBoolean()).isFalse();
        assertThat(check.get("suggestions")).isNotEmpty();

        mvc.perform(put("/api/users/me/nickname")
                        .header("Authorization", "Bearer " + second)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"otabek_z\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("nickname_taken"));
    }

    @Test
    void invalidNicknamesAreRefusedWithAReason() throws Exception {
        String token = login("Third");

        mvc.perform(get("/api/users/nickname/check").param("value", "ab")
                        .header("Authorization", "Bearer " + token))
                .andExpect(jsonPath("$.available").value(false))
                .andExpect(jsonPath("$.reason").value("Kamida 3 ta belgi"));

        mvc.perform(put("/api/users/me/nickname")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"bad nick\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("nickname_invalid"));
    }

    @Test
    void friendRequestsFlowThroughToTheFriendList() throws Exception {
        String a = login("Aziza");
        String b = login("Bekzod");

        claim(a, "aziza_m");
        claim(b, "bekzod_99");

        long bId = userId(b);
        String requestBody = mvc.perform(post("/api/friends/requests")
                        .header("Authorization", "Bearer " + a)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":" + bId + "}"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        long requestId = mapper.readTree(requestBody).get("id").asLong();

        mvc.perform(get("/api/friends/requests").header("Authorization", "Bearer " + b))
                .andExpect(jsonPath("$[0].user.nickname").value("aziza_m"));

        mvc.perform(post("/api/friends/requests/" + requestId + "/accept")
                        .header("Authorization", "Bearer " + b))
                .andExpect(status().isOk());

        mvc.perform(get("/api/friends").header("Authorization", "Bearer " + a))
                .andExpect(jsonPath("$[0].user.nickname").value("bekzod_99"));
        mvc.perform(get("/api/friends").header("Authorization", "Bearer " + b))
                .andExpect(jsonPath("$[0].user.nickname").value("aziza_m"));
    }

    /**
     * The other player's history outlives the account: the duel happened, and
     * the row that is left has no name on it, so the server has to supply one.
     */
    @Test
    void aDeletedOpponentIsStillNamedInTheHistory() throws Exception {
        String a = login("Gulnora");
        String b = login("Hasan");
        claim(a, "gulnora_t");
        claim(b, "hasan_dev");

        MatchEntity match = new MatchEntity(userId(a), userId(b), false, Instant.now().minusSeconds(300));
        match.setWinnerId(userId(a));
        match.setEndReason(MatchEntity.EndReason.WORDS_LIMIT);
        match.setChainLength(9);
        match.setFinishedAt(Instant.now());
        matches.save(match);

        mvc.perform(get("/api/matches").header("Authorization", "Bearer " + a))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].opponent.nickname").value("hasan_dev"));

        mvc.perform(delete("/api/users/me").header("Authorization", "Bearer " + b))
                .andExpect(status().isNoContent());

        mvc.perform(get("/api/matches").header("Authorization", "Bearer " + a))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].opponent.nickname").doesNotExist())
                .andExpect(jsonPath("$[0].opponent.displayName").value("O'chirilgan akkaunt"))
                .andExpect(jsonPath("$[0].opponent.initial").value("?"));
    }

    @Test
    void leaderboardAndProfileAreServed() throws Exception {
        String token = login("Diyor");
        claim(token, "diyor_k");

        mvc.perform(get("/api/leaderboard/global").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.me.user.nickname").value("diyor_k"));

        mvc.perform(get("/api/users/me/profile").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.badges.length()").value(8))
                .andExpect(jsonPath("$.badges[0].code").value("first_battle"));

        mvc.perform(get("/api/practice/word").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.word").isNotEmpty());
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
