package uz.wordbattle.moderation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import uz.wordbattle.admin.AdminAuditLogRepository;
import uz.wordbattle.user.UserRepository;

/**
 * Blocking and reporting through the API the app calls, and the admin panel's
 * side of a report. What a block does to a live duel, an invite and the queue
 * is the socket's business — see {@code BlockedPlayersSocketTest}.
 */
@SpringBootTest
@AutoConfigureMockMvc
class BlockAndReportTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private UserRepository users;

    @Autowired
    private UserReportRepository reports;

    @Autowired
    private AdminAuditLogRepository auditLog;

    @Autowired
    private PlatformTransactionManager transactionManager;

    // ------------------------------------------------------------- blocking

    @Test
    void blockingEndsTheFriendshipAndAPendingRequestAndRefusesNewOnesEitherWay() throws Exception {
        String aziza = login("Aziza");
        String bobur = login("Bobur");
        String dilnoza = login("Dilnoza");
        long boburId = userId(bobur);
        long dilnozaId = userId(dilnoza);
        long azizaId = userId(aziza);
        befriend(aziza, bobur);
        // A request still waiting, from somebody about to be blocked too.
        call(post("/api/friends/requests"), dilnoza, "{\"userId\":" + azizaId + "}").andExpect(status().isOk());

        call(post("/api/users/" + boburId + "/block"), aziza, null).andExpect(status().isNoContent());
        call(post("/api/users/" + dilnozaId + "/block"), aziza, null).andExpect(status().isNoContent());

        assertThat(friendIds(aziza)).doesNotContain(boburId);
        assertThat(friendIds(bobur)).doesNotContain(azizaId);
        assertThat(json(get("/api/friends/requests"), aziza)).isEmpty();

        // Neither side can ask again, and the refusal is the same whichever of
        // the two is asking.
        call(post("/api/friends/requests"), bobur, "{\"userId\":" + azizaId + "}")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("blocked"));
        call(post("/api/friends/requests"), aziza, "{\"userId\":" + boburId + "}")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("blocked"));
    }

    @Test
    void aBlockHidesEachPlayerFromTheOthersSearch() throws Exception {
        String one = login("Hidden one");
        String two = login("Hidden two");
        String three = login("Hidden three");
        claim(one, "hid_one");
        claim(two, "hid_two");
        claim(three, "hid_three");

        call(post("/api/users/" + userId(two) + "/block"), one, null).andExpect(status().isNoContent());

        assertThat(searchNicknames(one, "hid_")).containsExactlyInAnyOrder("hid_three");
        assertThat(searchNicknames(two, "hid_")).containsExactlyInAnyOrder("hid_three");
        assertThat(searchNicknames(three, "hid_")).containsExactlyInAnyOrder("hid_one", "hid_two");
    }

    @Test
    void theBlockedListShowsWhoWasBlockedAndUnblockingLiftsTheBlock() throws Exception {
        String malika = login("Malika");
        String nodir = login("Nodir");
        claim(nodir, "blk_nodir");
        long nodirId = userId(nodir);

        call(post("/api/users/" + nodirId + "/block"), malika, null).andExpect(status().isNoContent());
        // Twice is still once.
        call(post("/api/users/" + nodirId + "/block"), malika, null).andExpect(status().isNoContent());

        JsonNode blocked = json(get("/api/users/me/blocks"), malika);
        assertThat(blocked).hasSize(1);
        assertThat(blocked.get(0).get("user").get("id").asLong()).isEqualTo(nodirId);
        assertThat(blocked.get(0).get("user").get("nickname").asText()).isEqualTo("blk_nodir");
        assertThat(blocked.get(0).get("blockedAt").asText()).isNotEmpty();
        // The list is the blocker's own: the blocked player is not told.
        assertThat(json(get("/api/users/me/blocks"), nodir)).isEmpty();

        call(delete("/api/users/" + nodirId + "/block"), malika, null).andExpect(status().isNoContent());
        call(delete("/api/users/" + nodirId + "/block"), malika, null).andExpect(status().isNoContent());

        assertThat(json(get("/api/users/me/blocks"), malika)).isEmpty();
        call(post("/api/friends/requests"), nodir, "{\"userId\":" + userId(malika) + "}")
                .andExpect(status().isOk());
    }

    @Test
    void nobodyBlocksOrReportsThemselvesOrAnAccountThatIsNotThere() throws Exception {
        String sardor = login("Sardor");
        long sardorId = userId(sardor);

        call(post("/api/users/" + sardorId + "/block"), sardor, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("self_block"));
        call(post("/api/users/" + sardorId + "/report"), sardor, "{\"reason\":\"SPAM\"}")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("self_report"));
        call(post("/api/users/9999999/block"), sardor, null)
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("user_not_found"));
        call(post("/api/users/9999999/report"), sardor, "{\"reason\":\"SPAM\"}")
                .andExpect(status().isNotFound());

        mvc.perform(post("/api/users/" + sardorId + "/block")).andExpect(status().isUnauthorized());
    }

    // ------------------------------------------------------------ reporting

    @Test
    void aReportIsFiledWithWhatItSaysAndARequestThatMakesNoSenseIsRefused() throws Exception {
        String reporter = login("Reporter");
        long reportedId = userId(login("Reported"));

        JsonNode filed = json(
                post("/api/users/" + reportedId + "/report"),
                reporter,
                "{\"reason\":\"abuse\",\"details\":\"  haqorat qildi  \",\"context\":\"CHAT\",\"matchRef\":\"duel-42\"}",
                201);
        UserReport report = reports.findById(filed.get("id").asLong()).orElseThrow();
        assertThat(report.getReporterId()).isEqualTo(userId(reporter));
        assertThat(report.getReportedId()).isEqualTo(reportedId);
        assertThat(report.getReason()).isEqualTo(UserReport.Reason.ABUSE);
        assertThat(report.getDetails()).isEqualTo("haqorat qildi");
        assertThat(report.getContext()).isEqualTo(UserReport.Context.CHAT);
        assertThat(report.getMatchRef()).isEqualTo("duel-42");
        assertThat(report.getStatus()).isEqualTo(UserReport.Status.OPEN);

        // Only a reason is required.
        call(post("/api/users/" + reportedId + "/report"), reporter, "{\"reason\":\"INAPPROPRIATE_NAME\"}")
                .andExpect(status().isCreated());

        call(post("/api/users/" + reportedId + "/report"), reporter, "{}")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("invalid_reason"));
        call(post("/api/users/" + reportedId + "/report"), reporter, "{\"reason\":\"RUDE\"}")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("invalid_reason"));
        call(post("/api/users/" + reportedId + "/report"), reporter, "{\"reason\":\"SPAM\",\"context\":\"lobby\"}")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("invalid_context"));
        call(
                        post("/api/users/" + reportedId + "/report"),
                        reporter,
                        mapper.writeValueAsString(Map.of("reason", "OTHER", "details", "x".repeat(501))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"));
    }

    @Test
    void aPlayerFilesAtMostTenReportsADay() throws Exception {
        String busy = login("Busy reporter");
        long target = userId(login("Much reported"));

        for (int i = 0; i < ReportService.MAX_REPORTS_PER_DAY; i++) {
            call(post("/api/users/" + target + "/report"), busy, "{\"reason\":\"SPAM\"}")
                    .andExpect(status().isCreated());
        }
        call(post("/api/users/" + target + "/report"), busy, "{\"reason\":\"SPAM\"}")
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.code").value("report_limit"));
    }

    // ----------------------------------------------------------- admin panel

    @Test
    void anOrdinaryPlayerCannotReadOrResolveReports() throws Exception {
        String player = login("Curious");

        call(get("/api/admin/reports"), player, null)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));
        call(post("/api/admin/reports/1/resolve"), player, null)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));
    }

    @Test
    void anAdminSeesOpenReportsWithNamesAndResolvingOneIsAuditedOnce() throws Exception {
        String admin = login("Moderator");
        claim(admin, "blk_moderator");
        long adminId = userId(admin);
        new TransactionTemplate(transactionManager)
                .executeWithoutResult(status -> assertThat(users.grantAdmin(adminId)).isEqualTo(1));

        String reporter = login("Upset");
        claim(reporter, "blk_upset");
        String reported = login("Rude");
        claim(reported, "blk_rude");
        long reportedId = userId(reported);
        long reportId = json(
                        post("/api/users/" + reportedId + "/report"),
                        reporter,
                        "{\"reason\":\"ABUSE\",\"details\":\"chatda so'kindi\",\"context\":\"chat\"}",
                        201)
                .get("id")
                .asLong();

        JsonNode open = reportRow(admin, "open", reportId);
        assertThat(open.get("reporter").asText()).isEqualTo("blk_upset");
        assertThat(open.get("reportedId").asLong()).isEqualTo(reportedId);
        assertThat(open.get("reported").asText()).isEqualTo("blk_rude");
        assertThat(open.get("reason").asText()).isEqualTo("abuse");
        assertThat(open.get("context").asText()).isEqualTo("chat");
        assertThat(open.get("details").asText()).isEqualTo("chatda so'kindi");
        assertThat(open.get("status").asText()).isEqualTo("open");

        JsonNode resolved = json(post("/api/admin/reports/" + reportId + "/resolve"), admin, null, 200);
        assertThat(resolved.get("status").asText()).isEqualTo("resolved");
        assertThat(resolved.get("resolvedBy").asText()).isEqualTo("blk_moderator");
        assertThat(resolved.get("resolvedAt").asText()).isNotEmpty();
        assertThat(auditRowsFor(reportedId)).isEqualTo(1);

        // A second click neither moves the record nor writes another row.
        JsonNode again = json(post("/api/admin/reports/" + reportId + "/resolve"), admin, null, 200);
        assertThat(again.get("resolvedAt").asText()).isEqualTo(resolved.get("resolvedAt").asText());
        assertThat(auditRowsFor(reportedId)).isEqualTo(1);

        assertThat(reportRow(admin, "resolved", reportId)).isNotNull();
        assertThat(reportRow(admin, "open", reportId)).isNull();

        call(get("/api/admin/reports").param("status", "archived"), admin, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("invalid_status"));
        call(post("/api/admin/reports/9999999/resolve"), admin, null)
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("report_not_found"));
    }

    // --------------------------------------------------------------- helpers

    /** The row for {@code reportId} on the admin list of {@code status}, or null when it is not there. */
    private JsonNode reportRow(String admin, String status, long reportId) throws Exception {
        JsonNode page = json(
                get("/api/admin/reports").param("status", status).param("size", "100"), admin, null, 200);
        for (JsonNode item : page.get("items")) {
            if (item.get("id").asLong() == reportId) return item;
        }
        return null;
    }

    private long auditRowsFor(long reportedId) {
        return auditLog.findAll().stream()
                .filter(entry -> "report_resolve".equals(entry.getAction()))
                .filter(entry -> Long.valueOf(reportedId).equals(entry.getTargetUserId()))
                .count();
    }

    private List<Long> friendIds(String token) throws Exception {
        List<Long> ids = new ArrayList<>();
        for (JsonNode friend : json(get("/api/friends"), token)) {
            ids.add(friend.get("user").get("id").asLong());
        }
        return ids;
    }

    private List<String> searchNicknames(String token, String query) throws Exception {
        List<String> nicknames = new ArrayList<>();
        for (JsonNode user : json(get("/api/users/search").param("q", query), token)) {
            nicknames.add(user.get("nickname").asText());
        }
        return nicknames;
    }

    private void befriend(String a, String b) throws Exception {
        long requestId = json(post("/api/friends/requests"), a, "{\"userId\":" + userId(b) + "}", 200)
                .get("id")
                .asLong();
        call(post("/api/friends/requests/" + requestId + "/accept"), b, null).andExpect(status().isOk());
    }

    private ResultActions call(MockHttpServletRequestBuilder request, String token, String body) throws Exception {
        request.header("Authorization", "Bearer " + token);
        if (body != null) request.contentType(MediaType.APPLICATION_JSON).content(body);
        return mvc.perform(request);
    }

    private JsonNode json(MockHttpServletRequestBuilder request, String token) throws Exception {
        return json(request, token, null, 200);
    }

    private JsonNode json(MockHttpServletRequestBuilder request, String token, String body, int expectedStatus)
            throws Exception {
        String response = call(request, token, body)
                .andExpect(status().is(expectedStatus))
                .andReturn()
                .getResponse()
                .getContentAsString();
        return mapper.readTree(response);
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
        call(put("/api/users/me/nickname"), token, "{\"nickname\":\"" + nickname + "\"}").andExpect(status().isOk());
    }

    private long userId(String token) throws Exception {
        return json(get("/api/users/me"), token).get("id").asLong();
    }
}
