package uz.wordbattle.admin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.willAnswer;
import static org.mockito.BDDMockito.willReturn;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import uz.wordbattle.auth.JwtService;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.user.AccountDeletionService;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;

/**
 * The admin panel's API, from the two sides that matter: who is let in, and what
 * the panel leaves behind when it changes something.
 *
 * <p>The first is the whole of the security of this feature. Every route under
 * {@code /api/admin} is one signed-in player away from reading and editing
 * everybody else's account, and the only thing between the two is a role granted
 * by a filter that runs on this path alone — so an ordinary token being refused
 * is asserted before anything else here is worth having.
 */
@SpringBootTest
@AutoConfigureMockMvc
class AdminControllerTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private UserRepository users;

    @Autowired
    private JwtService jwt;

    @Autowired
    private AdminAuditLogRepository auditLog;

    @Autowired
    private DuelService duels;

    @Autowired
    private AppProperties props;

    @Autowired
    private AdminUserService adminUsers;

    /**
     * Spied so a sign-in can be made to land on an account that already exists
     * and has since been banned. Dev login mints a brand-new account every time,
     * and a brand-new account is never banned — the case the check in {@code
     * AuthController} is written for is a returning Google player, which this
     * suite has no Google to produce.
     */
    @MockitoSpyBean
    private UserService userService;

    /**
     * Spied so the middle of a ban can be looked at. The order of its two halves
     * is the whole of what stops a banned player reconnecting into the teardown
     * of their own ban, and from outside a ban they are over too quickly to tell
     * apart.
     */
    @MockitoSpyBean
    private AccountDeletionService.SessionEnder sessionEnder;

    @Autowired
    private PlatformTransactionManager transactionManager;

    private TransactionTemplate transactions;

    @BeforeEach
    void setUp() {
        transactions = new TransactionTemplate(transactionManager);
    }

    /**
     * A perfectly good token belonging to a player who is not an admin. It has
     * to be refused on every route, and refused as a 403 in the shape the app
     * parses every other failure in — not as a 401, which the app answers by
     * sending the player back to sign in, and not as Spring's own error page.
     */
    @Test
    void anOrdinaryPlayersTokenOpensNothingUnderApiAdmin() throws Exception {
        String player = login("Sanjar");

        for (String path : new String[] {"/api/admin/users", "/api/admin/metrics", "/api/admin/audit-log",
                "/api/admin/matches", "/api/admin/users/1"}) {
            mvc.perform(get(path).header("Authorization", "Bearer " + player))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.code").value("forbidden"))
                    .andExpect(jsonPath("$.message").isNotEmpty());
        }
        // The mutations too: a filter that only guarded the reads would be no
        // guard at all.
        mvc.perform(post("/api/admin/users/1/ban").header("Authorization", "Bearer " + player))
                .andExpect(status().isForbidden());
        mvc.perform(post("/api/admin/users/1/unban").header("Authorization", "Bearer " + player))
                .andExpect(status().isForbidden());
        mvc.perform(put("/api/admin/users/1/nickname")
                        .header("Authorization", "Bearer " + player)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"anything\"}"))
                .andExpect(status().isForbidden());

        // And no token at all is still a 401, because that one the app can act
        // on: there is a sign-in screen behind it.
        mvc.perform(get("/api/admin/users"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthorized"));
    }

    /**
     * The same refusal, against the URLs somebody would try if they were
     * looking for a way past it.
     *
     * <p>The whole security of the panel rests on one boundary being spelled the
     * same way twice — {@code /api/admin/**} in {@code SecurityConfig}, which
     * decides who is refused, and a prefix test in {@code AdminAuthFilter},
     * which decides who is offered the role. A URL that one of them reads
     * differently from the other is the only shape of bug that opens this, and
     * reading the two implementations side by side is not evidence that they
     * agree. So the variants are actually sent.
     *
     * <p>Nothing here asserts a particular status: some of these are turned away
     * by Spring Security's firewall before any of this code runs, some are 404s
     * from the dispatcher, some are the plain 403. What matters is only that
     * none of them comes back 200 holding somebody else's account.
     */
    @Test
    void noSpellingOfTheAdminPathGetsPastTheRoleCheck() throws Exception {
        String player = login("Otabek");

        refused("/api/admin/users", player);
        // The panel root itself, which is inside /api/admin/** and was the one
        // shape the filter's prefix test used to read differently.
        refused("/api/admin", player);
        // Case, which the servlet container and the matcher may disagree about.
        refused("/API/ADMIN/users", player);
        refused("/Api/Admin/Users", player);
        // A trailing slash, an empty segment and a doubled one: three ways to
        // name the same resource that an ant pattern and a prefix test can read
        // differently.
        refused("/api/admin/users/", player);
        refused("/api/admin//users", player);
        refused("//api/admin/users", player);
        // A path parameter, which is the classic way to make a suffix rule stop
        // matching while the container still routes the request.
        refused("/api/admin/users;x=1", player);
        refused("/api/admin/users%2f", player);
        // And traversal back into the panel from outside it.
        refused("/api/users/../admin/users", player);
        refused("/api/admin/../admin/users", player);

        // The canonical one is refused too, which is what proves the loop above
        // was testing a door that is shut rather than a path that does not
        // exist.
        mvc.perform(get("/api/admin/users").header("Authorization", "Bearer " + player))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("forbidden"));
    }

    /** The same routes, with the role granted. */
    @Test
    void anAdminGetsTheListAndCanFindOneAccountInIt() throws Exception {
        String admin = adminLogin("Dilshod", "dilshod_admin");
        String player = login("Umida");
        claim(player, "umida_plays");
        long playerId = userId(player);

        mvc.perform(get("/api/admin/users").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items").isArray())
                .andExpect(jsonPath("$.page").value(0));

        // By nickname...
        JsonNode byNickname = json(get("/api/admin/users")
                .param("q", "umida_plays")
                .header("Authorization", "Bearer " + admin));
        assertThat(byNickname.get("total").asLong()).isEqualTo(1);
        assertThat(byNickname.get("items").get(0).get("id").asLong()).isEqualTo(playerId);
        assertThat(byNickname.get("items").get(0).get("banned").asBoolean()).isFalse();

        // ...by display name, which a player who never picked a nickname is all
        // an admin has to go on...
        assertThat(json(get("/api/admin/users")
                                .param("q", "Umida")
                                .header("Authorization", "Bearer " + admin))
                        .get("total")
                        .asLong())
                .isEqualTo(1);

        // ...and by the id itself, which is what a bug report carries.
        assertThat(json(get("/api/admin/users")
                                .param("q", String.valueOf(playerId))
                                .header("Authorization", "Bearer " + admin))
                        .get("items")
                        .get(0)
                        .get("id")
                        .asLong())
                .isEqualTo(playerId);

        mvc.perform(get("/api/admin/users/" + playerId).header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.nickname").value("umida_plays"))
                .andExpect(jsonPath("$.user.banned").value(false))
                .andExpect(jsonPath("$.globalRank").isNumber());

        mvc.perform(get("/api/admin/users/9999999").header("Authorization", "Bearer " + admin))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("user_not_found"));
    }

    /**
     * Banning, and the only definition of it that means anything: the token the
     * player is holding stops working everywhere, at once.
     *
     * <p>A ban that only closed the REST door would leave the socket — and with
     * it the duel, the queue and the invites — running on the token they already
     * had, for the month it still had left to live. That is why the ban is felt
     * in {@code UserRepository.currentFor}, which is the one question both doors
     * ask.
     */
    @Test
    void aBannedPlayersExistingTokenStopsWorkingEverywhere() throws Exception {
        String admin = adminLogin("Aziz", "aziz_admin");
        String player = login("Ravshan");
        claim(player, "ravshan_out");
        long playerId = userId(player);

        mvc.perform(post("/api/admin/users/" + playerId + "/ban")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"so'kindi\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.banned").value(true))
                .andExpect(jsonPath("$.bannedAt").isNotEmpty());

        // Not one endpoint — every one of them, and the ones the app calls first
        // above all.
        for (String path : new String[] {"/api/users/me", "/api/users/me/profile", "/api/friends", "/api/matches"}) {
            mvc.perform(get(path).header("Authorization", "Bearer " + player))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.code").value("unauthorized"));
        }

        // Banning again changes nothing and does not move the timestamp that
        // records when they actually lost the account.
        Instant bannedAt = users.findById(playerId).orElseThrow().getBannedAt();
        mvc.perform(post("/api/admin/users/" + playerId + "/ban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.banned").value(true));
        assertThat(users.findById(playerId).orElseThrow().getBannedAt()).isEqualTo(bannedAt);

        // Lifting it gives the account back — to a fresh token. The old ones
        // were revoked on the way out, so an unban is not an amnesty for every
        // token that was ever copied off the phone.
        mvc.perform(post("/api/admin/users/" + playerId + "/unban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.banned").value(false));
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + player))
                .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + issueFor(playerId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nickname").value("ravshan_out"));
    }

    /**
     * Signing in again while banned. The account is real and the credentials are
     * good, so without the check in {@code AuthController} the sign-in would
     * succeed and hand back a token that authenticates nobody — and the app,
     * seeing the 401 on its very next call, would send the player round to sign
     * in once more. A 403 naming the reason is the only answer that ends
     * anywhere.
     */
    @Test
    void aBannedAccountIsTurnedAwayAtSignInRatherThanHandedADeadToken() throws Exception {
        String admin = adminLogin("Shohruh", "shohruh_admin");
        long playerId = userId(login("Botir"));

        mvc.perform(post("/api/admin/users/" + playerId + "/ban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk());

        // Standing in for a returning Google player: the same account coming
        // back to the same login route, which is what devLogin cannot be.
        User banned = users.findById(playerId).orElseThrow();
        assertThat(banned.isBanned()).isTrue();
        willReturn(banned).given(userService).createDevUser(anyString());

        mvc.perform(post("/api/auth/dev")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"displayName\":\"Botir\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("account_banned"));
    }

    /**
     * The audit trail. An admin acting on somebody else's account is the one
     * thing this server does that nobody can reconstruct afterwards — a ban
     * leaves a timestamp but no name, a rename leaves nothing whatsoever — so
     * every mutation has to leave a row saying who did it, and the row commits
     * with the change rather than after it.
     */
    @Test
    void everyChangeThePanelMakesLeavesAnAuditRowNamingTheAdmin() throws Exception {
        String admin = adminLogin("Nodir", "nodir_admin");
        long adminId = userId(admin);
        String player = login("Guli");
        claim(player, "guli_before");
        long playerId = userId(player);

        long before = auditLog.count();

        mvc.perform(post("/api/admin/users/" + playerId + "/ban")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"spam\"}"))
                .andExpect(status().isOk());
        mvc.perform(post("/api/admin/users/" + playerId + "/unban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk());
        mvc.perform(put("/api/admin/users/" + playerId + "/nickname")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"guli_after\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nickname").value("guli_after"));

        assertThat(auditLog.count()).isEqualTo(before + 3);

        // Newest first, and each row says what it was, who did it and to whom.
        JsonNode entries = json(get("/api/admin/audit-log").header("Authorization", "Bearer " + admin))
                .get("items");
        assertThat(entries.get(0).get("action").asText()).isEqualTo(AdminAuditService.NICKNAME);
        assertThat(entries.get(0).get("detail").asText()).isEqualTo("guli_before → guli_after");
        assertThat(entries.get(0).get("adminUserId").asLong()).isEqualTo(adminId);
        assertThat(entries.get(0).get("admin").asText()).isEqualTo("nodir_admin");
        assertThat(entries.get(0).get("targetUserId").asLong()).isEqualTo(playerId);
        assertThat(entries.get(1).get("action").asText()).isEqualTo(AdminAuditService.UNBAN);
        assertThat(entries.get(2).get("action").asText()).isEqualTo(AdminAuditService.BAN);
        assertThat(entries.get(2).get("detail").asText()).isEqualTo("spam");

        // A ban that changes nothing is not an event, so it writes no row: a log
        // padded with actions that did not happen is one nobody reads.
        mvc.perform(post("/api/admin/users/" + playerId + "/unban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk());
        assertThat(auditLog.count()).isEqualTo(before + 3);
    }

    /**
     * The panel renames players by the same rules the onboarding screen does —
     * it goes through {@code UserService.claimNickname} rather than around it.
     * An admin who could set a name the game itself refuses would be creating
     * rows nothing else on the server knows how to handle.
     */
    @Test
    void renamingIsHeldToTheRulesThePlayerIsHeldTo() throws Exception {
        String admin = adminLogin("Jasur", "jasur_admin");
        String player = login("Laylo");
        claim(player, "laylo_one");
        long playerId = userId(player);
        claim(login("Mavluda"), "mavluda_taken");

        mvc.perform(put("/api/admin/users/" + playerId + "/nickname")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"no\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("nickname_invalid"));

        mvc.perform(put("/api/admin/users/" + playerId + "/nickname")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"mavluda_taken\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("nickname_taken"));

        // A refused rename leaves no audit row either, because nothing happened.
        long before = auditLog.count();
        mvc.perform(put("/api/admin/users/" + playerId + "/nickname")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"admin\"}"))
                .andExpect(status().isBadRequest());
        assertThat(auditLog.count()).isEqualTo(before);
        assertThat(users.findById(playerId).orElseThrow().getNickname()).isEqualTo("laylo_one");
    }

    /** The dashboard, and the one number on it this test can pin down exactly. */
    @Test
    void theDashboardCountsBansAsTheyHappen() throws Exception {
        String admin = adminLogin("Kamron", "kamron_admin");
        long playerId = userId(login("Sitora"));

        JsonNode before = json(get("/api/admin/metrics").header("Authorization", "Bearer " + admin));
        assertThat(before.get("totalUsers").asLong()).isPositive();
        assertThat(before.get("botBattles").asLong()).isNotNegative();
        assertThat(before.get("humanBattles").asLong()).isNotNegative();
        assertThat(before.get("battlesToday").asLong()).isNotNegative();

        mvc.perform(post("/api/admin/users/" + playerId + "/ban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk());

        JsonNode after = json(get("/api/admin/metrics").header("Authorization", "Bearer " + admin));
        assertThat(after.get("bannedUsers").asLong()).isEqualTo(before.get("bannedUsers").asLong() + 1);
    }

    /**
     * Two admins reaching for the same account in the same instant — two people
     * working a report queue, or one admin whose button was pressed twice.
     *
     * <p>The ban is read-check-write like every other double-tap in this server,
     * and the check is made by the database rather than by the code above it:
     * the update carries {@code and banned_at is null}, so the second one
     * matches no row and its whole transaction — audit entry included — is
     * rolled back. Without that the log would show the account being taken away
     * twice by two different people, and the timestamp would say the later of
     * the two moments.
     */
    @Test
    void twoAdminsBanningAtOnceLeaveOneBanAndOneLineInTheLog() throws Exception {
        String first = adminLogin("Anvar", "anvar_admin");
        String second = adminLogin("Bahrom", "bahrom_admin");
        long firstId = userId(first);
        long secondId = userId(second);
        long targetId = userId(login("Qobil"));

        CountDownLatch ready = new CountDownLatch(2);
        CountDownLatch go = new CountDownLatch(1);
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            List<Future<?>> both = List.of(
                    pool.submit(() -> banTogether(ready, go, firstId, targetId)),
                    pool.submit(() -> banTogether(ready, go, secondId, targetId)));
            ready.await(5, TimeUnit.SECONDS);
            go.countDown();
            for (Future<?> attempt : both) {
                attempt.get(20, TimeUnit.SECONDS);
            }
        } finally {
            pool.shutdownNow();
        }

        assertThat(users.findById(targetId).orElseThrow().isBanned()).isTrue();
        assertThat(auditLog.findAll().stream()
                        .filter(entry -> targetId == entry.getTargetUserId()
                                && AdminAuditService.BAN.equals(entry.getAction()))
                        .toList())
                .as("one ban, one line — whichever admin got there first")
                .hasSize(1);
    }

    /**
     * A duel of the banned player's settling <em>after</em> the ban commits, in
     * both the ways that can still happen.
     *
     * <p>The first is the ordinary one: a duel already under way when the ban
     * lands. The row is written first and the session torn down afterwards, so
     * the forfeit that ends the duel — and the result it writes — is behind the
     * ban by construction. A new duel is not, and cannot be: {@code
     * DuelService.start} refuses a banned account outright, which is what {@code
     * BannedPlayerCannotDuelTest} is about.
     *
     * <p>The second is a settlement that was already in flight when the
     * transaction committed — a duel that ended a moment before the admin
     * pressed the button. It read the player beforehand and writes every column
     * of the row back afterwards, which is the exact shape of write that used to
     * bring a signed-out token back to life before {@code token_generation} was
     * made unwritable through the entity. {@code banned_at} is unwritable for the
     * same reason, and this is that reason being checked rather than asserted.
     *
     * <p>That the settlement writes the duel at all is deliberate — see {@code
     * MatchResultService.playerBehind} for why a ban is not a deletion here.
     */
    @Test
    void aSettlementThatLandsAfterTheBanCannotUndoIt() throws Exception {
        String admin = adminLogin("Tohir", "tohir_admin");
        String player = login("Alisher");
        claim(player, "alisher_late");
        long playerId = userId(player);
        long opponentId = userId(login("Doniyor"));

        // Mid-duel, which is where a player about to be banned usually is.
        assertThat(duels.start(playerId, opponentId)).isNotNull();

        mvc.perform(post("/api/admin/users/" + playerId + "/ban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.banned").value(true));

        // No polling: the teardown does not return until the forfeit it caused
        // has been written, so the settlement has already landed here.
        User banned = users.findById(playerId).orElseThrow();
        assertThat(banned.isBanned()).as("the ban survived the settlement it caused").isTrue();
        // The duel itself was recorded, which is the decision documented on
        // MatchResultService.playerBehind: a ban erases nothing, so there is
        // nothing for this write to resurrect, and the opponent keeps the duel
        // they really played.
        assertThat(banned.getBattles()).isEqualTo(1);
        assertThat(users.findById(opponentId).orElseThrow().getBattles()).isEqualTo(1);

        // And the other one, on an account of its own because a stale copy has
        // to be read while the row is still where the settlement left it: a
        // whole-row write from a copy taken before the ban committed.
        String late = login("Nafisa");
        long lateId = userId(late);
        User loadedBeforeTheBan = users.findById(lateId).orElseThrow();
        mvc.perform(post("/api/admin/users/" + lateId + "/ban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk());
        loadedBeforeTheBan.setCity("Toshkent");
        users.saveAndFlush(loadedBeforeTheBan);
        assertThat(users.findById(lateId).orElseThrow().isBanned())
                .as("the ban survived a whole-row write from before it")
                .isTrue();

        // And the accounts are still shut, which is the whole of what a ban
        // promises: no token for them works, old or new.
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + player))
                .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + issueFor(playerId)))
                .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + late))
                .andExpect(status().isUnauthorized());
    }

    /**
     * The ban is committed before the session is torn down, and this is what
     * holds it there.
     *
     * <p>Tearing a session down is not instant: the socket closes, the queue and
     * the invites go, and then it waits up to five seconds for a duel of theirs
     * to settle. The app reconnects on its own a second after its socket drops,
     * and the question the reconnect is answered with — {@code
     * UserRepository.currentFor} — is asked of the database every time, of a row
     * nothing caches. So with the teardown running first, the player came back
     * inside the teardown of their own ban on a token that was still perfectly
     * good, and could queue, take an invite and finish a rated duel with it.
     *
     * <p>What is read below is exactly what that reconnect would have been
     * measured against, at the moment it would have arrived. Asserting the order
     * of the two calls would not be the same thing: it is the {@code commit}
     * that closes the door, not the call.
     */
    @Test
    void theBanIsAlreadyCommittedWhenTheSessionIsTornDown() throws Exception {
        String admin = adminLogin("Sardor", "sardor_admin");
        long playerId = userId(login("Nigina"));

        AtomicBoolean bannedByThen = new AtomicBoolean();
        willAnswer(invocation -> {
            bannedByThen.set(users.findById(playerId).orElseThrow().isBanned());
            return invocation.callRealMethod();
        })
                .given(sessionEnder)
                .endSessionOf(playerId);

        mvc.perform(post("/api/admin/users/" + playerId + "/ban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.banned").value(true));

        assertThat(bannedByThen)
                .as("the session was torn down before the ban committed, so a reconnect in that window is let in")
                .isTrue();
        verify(sessionEnder).endSessionOf(playerId);

        // A second ban changes nothing, so it tears nothing down either: there
        // is no session left to end, and the wait would only be served twice.
        mvc.perform(post("/api/admin/users/" + playerId + "/ban").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk());
        verify(sessionEnder, times(1)).endSessionOf(playerId);
    }

    /**
     * An admin banning themselves. The panel is the only thing that lifts a ban
     * and a ban shuts the panel, so this is a door that locks from the inside
     * with the key still in it — and the account is one of the few on the server
     * that cannot be replaced by signing up again.
     */
    @Test
    void anAdminCannotBanThemselvesOutOfThePanel() throws Exception {
        String admin = adminLogin("Zafar", "zafar_admin");
        long adminId = userId(admin);
        long before = auditLog.count();

        mvc.perform(post("/api/admin/users/" + adminId + "/ban")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"xato bosildi\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("cannot_ban_self"))
                .andExpect(jsonPath("$.message").isNotEmpty());

        // Nothing happened, so nothing was written down and the panel still
        // opens.
        assertThat(users.findById(adminId).orElseThrow().isBanned()).isFalse();
        assertThat(auditLog.count()).isEqualTo(before);
        mvc.perform(get("/api/admin/users").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk());
    }

    /**
     * The same lockout one step out: the last account that can open the panel.
     * With it banned there is nobody left to lift anything, and no endpoint hands
     * the role to somebody new — getting back in means a redeploy with {@code
     * ADMIN_BOOTSTRAP_USER_ID} set.
     *
     * <p>Driven through the service rather than the API, and the reason is worth
     * writing down. The filter only lets an admin reach the route, and an admin
     * banning somebody else is two active admins by definition — so through the
     * API the count can only be one when the caller's own role has gone since the
     * filter looked at it, which a revoke-role screen will make ordinary. The
     * caller below is exactly that: a real id that is not an admin.
     */
    @Test
    void theLastAdminLeftCannotBeBanned() throws Exception {
        long lastAdminId = userId(adminLogin("Rustam", "rustam_admin"));
        long caller = userId(login("Malika"));

        // "The last one" is a fact about the whole table, and the suite shares
        // one database, so every other admin still standing in it is put out of
        // the way first — straight at the column, since this is the scene being
        // set rather than something the panel did.
        transactions.executeWithoutResult(status -> users.findAll().stream()
                .filter(user -> user.isAdmin() && !user.isBanned() && !user.isDeleted())
                .filter(user -> !user.getId().equals(lastAdminId))
                .forEach(user -> users.ban(user.getId(), Instant.now())));
        assertThat(users.countActiveAdmins()).isEqualTo(1);

        long before = auditLog.count();
        assertThatThrownBy(() -> adminUsers.ban(caller, lastAdminId, "oxirgisi"))
                .isInstanceOfSatisfying(
                        ApiException.class, refused -> assertThat(refused.code()).isEqualTo("last_admin"));
        assertThat(users.findById(lastAdminId).orElseThrow().isBanned()).isFalse();
        assertThat(auditLog.count()).isEqualTo(before);

        // With a second admin back it goes through: the guard is about the
        // count and nothing else.
        long secondId = userId(adminLogin("Sevara", "sevara_admin"));
        assertThat(adminUsers.ban(secondId, lastAdminId, "endi mumkin").isBanned()).isTrue();
    }

    /**
     * The only way an admin can come to exist in the first place. Nothing in the
     * API grants the role — deliberately, since a panel that can create admins
     * is a panel one compromised account can keep forever — so this runs from
     * configuration on startup, and if it did not work there would be no way in
     * at all.
     *
     * <p>Driven by hand rather than through the property, because the id has to
     * belong to an account that exists and the real runner has already come and
     * gone by the time a test can make one. What it is really holding is that the
     * grant works from a startup hook: it is a JPQL update, which needs a
     * transaction, and a hook is the worst place to find out that an annotation
     * was never proxied.
     */
    @Test
    void theBootstrapIsHowTheFirstAdminIsMade() throws Exception {
        long id = userId(login("Ilhom"));
        assertThat(users.isAdmin(id)).isFalse();

        bootstrapFor(String.valueOf(id)).run(null);
        assertThat(users.isAdmin(id)).isTrue();

        // Run on every start, so a second one has to be a no-op rather than an
        // error — the variable is meant to be left set.
        bootstrapFor(String.valueOf(id)).run(null);
        assertThat(users.isAdmin(id)).isTrue();

        // And the ways it can be misconfigured cost the server nothing: it is an
        // optional feature, and a duel in progress outranks it.
        bootstrapFor("").run(null);
        bootstrapFor("not-a-number").run(null);
        bootstrapFor("9999999").run(null);
        assertThat(users.isAdmin(id)).isTrue();
    }

    /**
     * The match list is bound to no account, which is the whole difference
     * between it and the history endpoint the players call. A duel neither of
     * these two admins played has to be in it.
     */
    @Test
    void theMatchListReachesDuelsTheAdminHadNoPartIn() throws Exception {
        String admin = adminLogin("Feruz", "feruz_admin");
        long one = userId(login("Olim"));
        long two = userId(login("Sardorbek"));

        assertThat(duels.start(one, two)).isNotNull();
        duels.forfeitAndAwaitSettlement(one);

        JsonNode page = json(get("/api/admin/matches").header("Authorization", "Bearer " + admin));
        assertThat(page.get("total").asLong()).isPositive();

        // Newest first, so the duel just settled is the first row.
        JsonNode newest = page.get("items").get(0);
        assertThat(newest.get("playerOneId").asLong()).isIn(one, two);
        assertThat(newest.get("playerTwoId").asLong()).isIn(one, two);
        assertThat(newest.get("winnerId").asLong()).isEqualTo(two);
        assertThat(newest.get("endReason").asText()).isEqualTo("forfeit");
        assertThat(newest.get("botOpponent").asBoolean()).isFalse();
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

    /**
     * A player with the admin role, granted the way {@code AdminBootstrap}
     * grants it — straight at the column, since there is no endpoint that hands
     * the role out and deliberately so.
     */
    private String adminLogin(String name, String nickname) throws Exception {
        String token = login(name);
        long id = userId(token);
        claim(token, nickname);
        transactions.executeWithoutResult(status -> assertThat(users.grantAdmin(id)).isEqualTo(1));
        return token;
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
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        return mapper.readTree(body).get("id").asLong();
    }

    /**
     * Sends {@code path} with a token that is valid and holds no admin role, and
     * insists the answer is not somebody else's account.
     *
     * <p>A request the firewall throws out never reaches a handler at all, which
     * is the strongest possible refusal — and it arrives as an exception rather
     * than a status, so it counts as a pass here. The only failure this can miss
     * is a 200, which is the only one worth catching.
     */
    /** Both threads wait on the gate, so the two bans really are concurrent. */
    private void banTogether(CountDownLatch ready, CountDownLatch go, long adminId, long targetId) {
        try {
            ready.countDown();
            go.await(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
        adminUsers.ban(adminId, targetId, "bir vaqtda");
    }

    private void refused(String path, String token) {
        int status;
        try {
            status = mvc.perform(get(path).header("Authorization", "Bearer " + token))
                    .andReturn()
                    .getResponse()
                    .getStatus();
        } catch (Exception rejected) {
            return;
        }
        assertThat(status / 100)
                .as("GET %s answered %d, as though the admin routes were open", path, status)
                .isNotEqualTo(2);
    }

    /** The startup hook as it would be built with {@code ADMIN_BOOTSTRAP_USER_ID} set. */
    private AdminBootstrap bootstrapFor(String bootstrapUserId) {
        AppProperties configured = new AppProperties(
                props.jwt(),
                props.google(),
                props.duel(),
                props.matchmaking(),
                props.rating(),
                props.cors(),
                props.limits(),
                props.auth(),
                new AppProperties.Admin(bootstrapUserId),
                props.tournament(),
                props.timeZone(),
                props.devLoginEnabled());
        return new AdminBootstrap(users, configured, transactionManager);
    }

    /** A second sign-in of an existing account, as {@code AuthController} does it. */
    private String issueFor(long id) {
        User user = users.findById(id).orElseThrow();
        return jwt.issue(user.getId(), user.getTokenGeneration());
    }

    private JsonNode json(org.springframework.test.web.servlet.RequestBuilder request) throws Exception {
        return mapper.readTree(mvc.perform(request)
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString());
    }
}
