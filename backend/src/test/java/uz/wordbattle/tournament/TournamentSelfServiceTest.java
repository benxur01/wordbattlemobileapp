package uz.wordbattle.tournament;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import uz.wordbattle.admin.AdminAuditLogRepository;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.friend.FriendService;

/**
 * The friends-screen "Turnir tashkil qilish": an ordinary player runs the
 * whole thing an admin otherwise would — create, invite, start — restricted to
 * their own friends and never touching {@link AdminAuditLogRepository}, since
 * this is a player acting on their own tournament rather than an admin acting
 * on somebody else's account.
 */
@SpringBootTest
@AutoConfigureMockMvc
class TournamentSelfServiceTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private TournamentService tournaments;

    @Autowired
    private FriendService friends;

    @Autowired
    private AdminAuditLogRepository auditLog;

    @Test
    void aPlayerCanOrganizeATournamentAmongFriendsAndStartItOnceEveryoneAccepts() throws Exception {
        long before = auditLog.count();

        long organizerId = createPlayer("selforg0");
        long[] friendIds = {createPlayer("selffr1"), createPlayer("selffr2"), createPlayer("selffr3"), createPlayer("selffr4")};
        for (long friendId : friendIds) befriend(organizerId, friendId);

        TournamentEntity tournament = tournaments.createByUser(organizerId, "Do'stlar turniri", 4);
        assertThat(tournament.getCreatedByAdminId()).isEqualTo(organizerId);

        for (long friendId : friendIds) tournaments.inviteByUser(organizerId, tournament.getId(), friendId);
        for (long friendId : friendIds) tournaments.accept(friendId, tournament.getId());

        TournamentEntity started = tournaments.startByUser(organizerId, tournament.getId());
        assertThat(started.getStatus()).isEqualTo(TournamentEntity.Status.IN_PROGRESS);

        // Readable by anyone signed in, same as an admin's tournament, and names
        // its organizer.
        String outsider = login("SelfOutsider");
        JsonNode detail = json(get("/api/tournaments/" + tournament.getId()).header("Authorization", "Bearer " + outsider));
        assertThat(detail.get("organizer").get("id").asLong()).isEqualTo(organizerId);

        // None of this touched the admin audit log.
        assertThat(auditLog.count()).isEqualTo(before);
    }

    @Test
    void invitingSomeoneWhoIsNotAFriendIsRefused() {
        long organizerId = createPlayer("selfnf0");
        long strangerId = createPlayer("selfnf1");
        TournamentEntity tournament = tournaments.createByUser(organizerId, "Yopiq davra", 4);

        assertThatThrownBy(() -> tournaments.inviteByUser(organizerId, tournament.getId(), strangerId))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("not_friends"));
    }

    @Test
    void onlyTheOrganizerMayInviteOrStartTheirOwnTournament() {
        long organizerId = createPlayer("selfown0");
        long otherId = createPlayer("selfown1");
        long friendId = createPlayer("selfown2");
        befriend(otherId, friendId);
        TournamentEntity tournament = tournaments.createByUser(organizerId, "Boshqasiniki", 4);

        assertThatThrownBy(() -> tournaments.inviteByUser(otherId, tournament.getId(), friendId))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("not_organizer"));
        assertThatThrownBy(() -> tournaments.startByUser(otherId, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("not_organizer"));
    }

    @Test
    void selfServiceCreationRefusesAnythingOtherThanAPowerOfTwoUpTo32() throws Exception {
        String player = login("SelfSizePlayer");
        mvc.perform(post("/api/tournaments")
                        .header("Authorization", "Bearer " + player)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Noto'g'ri\",\"size\":6}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("invalid_size"));
    }

    @Test
    void anOrdinaryPlayerCanCreateInviteAndStartOverRestWithNoAdminRole() throws Exception {
        String organizer = login("RestOrganizer");
        long organizerId = userId(organizer);
        long friendId = createPlayer("restfriend0");
        befriend(organizerId, friendId);

        JsonNode created = json(post("/api/tournaments")
                .header("Authorization", "Bearer " + organizer)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Rest turniri\",\"size\":4}"));
        long tournamentId = created.get("id").asLong();

        mvc.perform(post("/api/tournaments/" + tournamentId + "/invite")
                        .header("Authorization", "Bearer " + organizer)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":" + friendId + "}"))
                .andExpect(status().isOk());

        JsonNode participants = json(get("/api/tournaments/" + tournamentId + "/participants")
                .header("Authorization", "Bearer " + organizer));
        assertThat(participants).hasSize(1);
        assertThat(participants.get(0).get("status").asText()).isEqualTo("invited");
    }

    // --------------------------------------------------------------- helpers

    private void befriend(long a, long b) {
        friends.accept(b, friends.sendRequest(a, b).getId());
    }

    private long createPlayer(String nickname) {
        String token = login(nickname);
        claim(token, nickname);
        return userId(token);
    }

    private String login(String name) {
        try {
            String body = mvc.perform(post("/api/auth/dev")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"displayName\":\"" + name + "\"}"))
                    .andExpect(status().isOk())
                    .andReturn()
                    .getResponse()
                    .getContentAsString();
            return mapper.readTree(body).get("token").asText();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private void claim(String token, String nickname) {
        try {
            mvc.perform(put("/api/users/me/nickname")
                            .header("Authorization", "Bearer " + token)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"nickname\":\"" + nickname + "\"}"))
                    .andExpect(status().isOk());
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private long userId(String token) {
        try {
            String body = mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + token))
                    .andExpect(status().isOk())
                    .andReturn()
                    .getResponse()
                    .getContentAsString();
            return mapper.readTree(body).get("id").asLong();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private JsonNode json(org.springframework.test.web.servlet.RequestBuilder request) throws Exception {
        return mapper.readTree(mvc.perform(request)
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString());
    }
}
