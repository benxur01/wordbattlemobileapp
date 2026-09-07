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
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import uz.wordbattle.admin.AdminAuditLog;
import uz.wordbattle.admin.AdminAuditLogRepository;
import uz.wordbattle.admin.AdminAuditService;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.friend.FriendService;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.match.TeamDuelService;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * The same bracket {@code TournamentServiceTest} plays through, with a pair of
 * players in every seat instead of one: invited two at a time, seeded on the
 * two ratings averaged, played through {@link TeamDuelService} rather than
 * {@link DuelService}, and advanced by the winning team's primary member — the
 * only id the bracket ever knows a team by, which is what lets every piece of
 * seeding and advancement stay exactly what it is for a solo tournament.
 */
@SpringBootTest
@AutoConfigureMockMvc
class TeamTournamentServiceTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private TournamentService tournaments;

    @Autowired
    private TournamentMatchRepository matchRepo;

    @Autowired
    private TeamDuelService teamDuels;

    @Autowired
    private DuelService duels;

    @Autowired
    private FriendService friends;

    @Autowired
    private UserRepository users;

    @Autowired
    private AdminAuditLogRepository auditEntries;

    @Autowired
    private PlatformTransactionManager transactionManager;

    /** The two people holding one seat: the id the bracket goes by, and their teammate. */
    private record Team(long primary, long partner) {}

    /**
     * Four teams, eight people, one champion. The ratings are chosen so that
     * seeding by a team's <em>average</em> and seeding by its primary member's
     * own rating disagree: team C's primary is rated above team B's, and team C
     * still seeds below team B because its partner drags the pair's average
     * under.
     */
    @Test
    void seedsATeamBracketByAverageRatingAndPlaysItToAChampion() {
        long organizerId = createPlayer("ttorg", 1500);
        Team a = team("ttteama", 1900, 1900, organizerId);
        Team b = team("ttteamb", 1600, 1800, organizerId);
        Team c = team("ttteamc", 1850, 1150, organizerId);
        Team d = team("ttteamd", 1000, 1000, organizerId);
        List<Team> teams = List.of(a, b, c, d);

        TournamentEntity tournament = tournaments.createByUser(
                organizerId,
                "Jamoaviy turnir",
                4,
                TournamentEntity.Visibility.PRIVATE,
                TournamentEntity.Format.TEAM);
        assertThat(tournament.getFormat()).isEqualTo(TournamentEntity.Format.TEAM);

        for (Team team : teams) {
            tournaments.inviteTeamByUser(organizerId, tournament.getId(), team.primary(), team.partner());
        }

        // One accepted half is not an accepted seat: the bracket is still empty
        // as far as starting it goes.
        for (Team team : teams) tournaments.accept(team.primary(), tournament.getId());
        assertThat(tournaments.summaryOf(tournaments.require(tournament.getId())).acceptedCount()).isZero();
        assertThatThrownBy(() -> tournaments.startByUser(organizerId, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("not_ready"));

        for (Team team : teams) tournaments.accept(team.partner(), tournament.getId());
        assertThat(tournaments.summaryOf(tournaments.require(tournament.getId())).acceptedCount()).isEqualTo(4);

        tournaments.startByUser(organizerId, tournament.getId());

        assertThat(seedOf(tournament.getId(), a)).isEqualTo(1);
        assertThat(seedOf(tournament.getId(), b)).as("the higher team average outseeds the higher single rating")
                .isEqualTo(2);
        assertThat(seedOf(tournament.getId(), c)).isEqualTo(3);
        assertThat(seedOf(tournament.getId(), d)).isEqualTo(4);

        // Seeds 1v4 and 2v3, drawn from the primary members exactly as a solo
        // bracket is — with each seat's teammate carried alongside.
        List<TournamentMatch> round1 = matchesOf(tournament.getId(), 1);
        assertThat(round1).hasSize(2);
        assertThat(pairsOf(round1)).containsExactlyInAnyOrder(
                Set.of(a.primary(), d.primary()), Set.of(b.primary(), c.primary()));
        for (TournamentMatch match : round1) {
            assertThat(match.getPlayerOnePartnerUserId()).isNotNull();
            assertThat(match.getPlayerTwoPartnerUserId()).isNotNull();
        }

        // The teammate is told about the match too, and is told who the other
        // three people on the board are.
        TournamentMatch first = matchFor(round1, a.primary());
        List<TournamentMatchPromptDto> waiting = tournaments.mine(a.partner()).readyMatches();
        assertThat(waiting).hasSize(1);
        assertThat(waiting.get(0).tournamentMatchId()).isEqualTo(first.getId());
        assertThat(waiting.get(0).format()).isEqualTo("team");
        assertThat(waiting.get(0).partner().id()).isEqualTo(a.primary());
        assertThat(waiting.get(0).opponent().id()).isEqualTo(d.primary());
        assertThat(waiting.get(0).opponentPartner().id()).isEqualTo(d.partner());

        // Starting it runs a 2v2 duel, not a 1v1 one, and all four are in it.
        tournaments.startMatch(a.partner(), first.getId());
        for (long member : List.of(a.primary(), a.partner(), d.primary(), d.partner())) {
            assertThat(teamDuels.isPlaying(member)).as("player %s is in the team duel", member).isTrue();
            assertThat(duels.isPlaying(member)).as("player %s is in no 1v1 duel", member).isFalse();
        }
        assertThat(matchRepo.findById(first.getId()).orElseThrow().getStatus())
                .isEqualTo(TournamentMatch.Status.LIVE);

        playOutLosing(first, d);
        playOutLosing(matchFor(matchesOf(tournament.getId(), 1), b.primary()), c);

        // Both winners advanced as whole teams: the final is A against B, and
        // each slot still names two people.
        List<TournamentMatch> round2 = matchesOf(tournament.getId(), 2);
        assertThat(round2).hasSize(1);
        TournamentMatch finalMatch = round2.get(0);
        assertThat(Set.of(finalMatch.getPlayerOneUserId(), finalMatch.getPlayerTwoUserId()))
                .isEqualTo(Set.of(a.primary(), b.primary()));
        assertThat(Set.of(finalMatch.getPlayerOnePartnerUserId(), finalMatch.getPlayerTwoPartnerUserId()))
                .isEqualTo(Set.of(a.partner(), b.partner()));
        assertThat(finalMatch.getStatus()).isEqualTo(TournamentMatch.Status.READY);

        playOutLosing(finalMatch, b);

        TournamentEntity finished = tournaments.require(tournament.getId());
        assertThat(finished.getStatus()).isEqualTo(TournamentEntity.Status.COMPLETED);
        assertThat(finished.getChampionUserId()).isEqualTo(a.primary());

        // The settled 2v2 duel is recorded in its own column: match_id points at
        // the 1v1 table and would be the wrong row to name here.
        TournamentMatch settledFinal = matchRepo.findById(finalMatch.getId()).orElseThrow();
        assertThat(settledFinal.getTeamMatchId()).isNotNull();
        assertThat(settledFinal.getMatchId()).isNull();

        TournamentDetailDto detail = tournaments.detail(tournament.getId());
        assertThat(detail.format()).isEqualTo("team");
        assertThat(detail.champion().id()).isEqualTo(a.primary());
        assertThat(detail.championPartner().id()).isEqualTo(a.partner());
        assertThat(detail.rounds().get(0).matches().get(0).playerOnePartner()).isNotNull();
    }

    @Test
    void invitingATeamNeedsTheOrganizerToBeFriendsWithBothOfThem() {
        long organizerId = createPlayer("ttnforg", 1500);
        long friendId = createPlayer("ttnffr", 1500);
        long strangerId = createPlayer("ttnfst", 1500);
        befriend(organizerId, friendId);

        TournamentEntity tournament = tournaments.createByUser(
                organizerId, "Yarim tanish", 4, TournamentEntity.Visibility.PRIVATE, TournamentEntity.Format.TEAM);

        assertThatThrownBy(() -> tournaments.inviteTeamByUser(organizerId, tournament.getId(), friendId, strangerId))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("not_friends"));
        assertThat(tournaments.participantViews(tournament.getId())).isEmpty();
    }

    @Test
    void aPlayerCannotBeSeatedInTwoTeamsOfTheSameBracket() {
        long organizerId = createPlayer("ttdborg", 1500);
        Team first = team("ttdbone", 1500, 1500, organizerId);
        long thirdId = createPlayer("ttdbthird", 1500);
        befriend(organizerId, thirdId);

        TournamentEntity tournament = tournaments.createByUser(
                organizerId, "Ikki jamoada", 4, TournamentEntity.Visibility.PRIVATE, TournamentEntity.Format.TEAM);
        tournaments.inviteTeamByUser(organizerId, tournament.getId(), first.primary(), first.partner());

        assertThatThrownBy(() ->
                        tournaments.inviteTeamByUser(organizerId, tournament.getId(), first.partner(), thirdId))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("already_seated"));
    }

    /** Neither format accepts the other's invite, and nobody joins a team bracket on their own. */
    @Test
    void theTwoFormatsRefuseEachOthersInvites() {
        long organizerId = createPlayer("ttfmorg", 1500);
        Team pair = team("ttfmteam", 1500, 1500, organizerId);
        long strangerId = createPlayer("ttfmstr", 1500);

        TournamentEntity teamTournament = tournaments.createByUser(
                organizerId, "Jamoaviy", 4, TournamentEntity.Visibility.PUBLIC, TournamentEntity.Format.TEAM);
        assertThatThrownBy(() -> tournaments.inviteByUser(organizerId, teamTournament.getId(), pair.primary()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("team_invite_required"));
        assertThatThrownBy(() -> tournaments.join(strangerId, teamTournament.getId()))
                .isInstanceOfSatisfying(
                        ApiException.class, e -> assertThat(e.code()).isEqualTo("tournament_not_joinable"));

        TournamentEntity soloTournament = tournaments.createByUser(
                organizerId, "Yakkalik", 4, TournamentEntity.Visibility.PRIVATE, TournamentEntity.Format.SOLO);
        assertThatThrownBy(() ->
                        tournaments.inviteTeamByUser(
                                organizerId, soloTournament.getId(), pair.primary(), pair.partner()))
                .isInstanceOfSatisfying(
                        ApiException.class, e -> assertThat(e.code()).isEqualTo("not_a_team_tournament"));
    }

    @Test
    void selfServiceCreationDefaultsToSoloButHonoursAnExplicitTeamRequest() throws Exception {
        String player = login("TeamFormatDefault");

        JsonNode defaultCreated = json(post("/api/tournaments")
                .header("Authorization", "Bearer " + player)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Standart\",\"size\":4}"));
        assertThat(defaultCreated.get("format").asText()).isEqualTo("solo");

        JsonNode teamCreated = json(post("/api/tournaments")
                .header("Authorization", "Bearer " + player)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Jamoaviy\",\"size\":4,\"format\":\"team\"}"));
        assertThat(teamCreated.get("format").asText()).isEqualTo("team");

        mvc.perform(post("/api/tournaments")
                        .header("Authorization", "Bearer " + player)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Noto'g'ri\",\"size\":4,\"format\":\"nonsense\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("invalid_format"));
    }

    @Test
    void aTeamIsInvitedAndAcceptedOverRestByBothOfItsMembers() throws Exception {
        String organizer = login("TeamRestOrganizer");
        long organizerId = userId(organizer);
        Team pair = team("ttrest", 1500, 1500, organizerId);

        JsonNode created = json(post("/api/tournaments")
                .header("Authorization", "Bearer " + organizer)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Rest jamoasi\",\"size\":4,\"format\":\"team\"}"));
        long tournamentId = created.get("id").asLong();

        mvc.perform(post("/api/tournaments/" + tournamentId + "/invite-team")
                        .header("Authorization", "Bearer " + organizer)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":" + pair.primary() + ",\"partnerUserId\":" + pair.partner() + "}"))
                .andExpect(status().isOk());

        JsonNode participants = json(get("/api/tournaments/" + tournamentId + "/participants")
                .header("Authorization", "Bearer " + organizer));
        assertThat(participants).hasSize(1);
        assertThat(participants.get(0).get("userId").asLong()).isEqualTo(pair.primary());
        assertThat(participants.get(0).get("partnerUserId").asLong()).isEqualTo(pair.partner());
        assertThat(participants.get(0).get("status").asText()).isEqualTo("invited");
        assertThat(participants.get(0).get("partnerStatus").asText()).isEqualTo("invited");

        tournaments.accept(pair.partner(), tournamentId);
        participants = json(get("/api/tournaments/" + tournamentId + "/participants")
                .header("Authorization", "Bearer " + organizer));
        assertThat(participants.get(0).get("status").asText()).isEqualTo("invited");
        assertThat(participants.get(0).get("partnerStatus").asText()).isEqualTo("accepted");
    }

    // ------------------------------------------------------------------- admin

    /**
     * The admin panel's own way into a 2v2 bracket. It seats any two registered
     * players — none of the eight below is a friend of the admin or of each
     * other, which the friends-screen path refuses and this one deliberately
     * does not — and leaves the same audit trail every other admin action does.
     */
    @Test
    void anAdminSeatsPairsOfStrangersInATeamBracketAndPlaysItToARound() {
        long adminId = adminUserId();
        TournamentEntity tournament =
                tournaments.create(adminId, "Admin jamoaviy", 4, TournamentEntity.Format.TEAM);
        assertThat(tournament.getFormat()).isEqualTo(TournamentEntity.Format.TEAM);
        assertThat(tournament.getKind()).isEqualTo(TournamentEntity.Kind.ADMIN);

        List<Team> teams = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            teams.add(new Team(
                    createPlayer("ttadmin" + i + "a", 1600 - i * 100),
                    createPlayer("ttadmin" + i + "b", 1500 - i * 100)));
        }
        for (Team team : teams) {
            tournaments.inviteTeam(adminId, tournament.getId(), team.primary(), team.partner());
        }

        List<TournamentParticipantDto> seats = tournaments.participantViews(tournament.getId());
        assertThat(seats).hasSize(4);
        assertThat(seats).allSatisfy(seat -> {
            assertThat(seat.partnerUserId()).isNotNull();
            assertThat(seat.status()).isEqualTo("invited");
            assertThat(seat.partnerStatus()).isEqualTo("invited");
        });

        // Both halves of every seat are named in the log, since both were
        // acted on.
        assertThat(auditTargetsOf(adminId, AdminAuditService.TOURNAMENT_INVITE))
                .containsExactlyInAnyOrderElementsOf(
                        teams.stream().flatMap(t -> Stream.of(t.primary(), t.partner())).toList());

        // One half's acceptance is not a seat, exactly as on the friends path.
        for (Team team : teams) tournaments.accept(team.primary(), tournament.getId());
        assertThatThrownBy(() -> tournaments.start(adminId, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("not_ready"));

        for (Team team : teams) tournaments.accept(team.partner(), tournament.getId());
        tournaments.start(adminId, tournament.getId());

        List<TournamentMatch> round1 = matchesOf(tournament.getId(), 1);
        assertThat(round1).hasSize(2);
        for (TournamentMatch match : round1) {
            assertThat(match.getPlayerOnePartnerUserId()).isNotNull();
            assertThat(match.getPlayerTwoPartnerUserId()).isNotNull();
        }
    }

    @Test
    void theAdminTeamInviteRefusesASoloBracketAndAPairOfTheSamePlayer() {
        long adminId = adminUserId();
        long one = createPlayer("ttadmref1", 1500);
        long two = createPlayer("ttadmref2", 1500);

        TournamentEntity solo = tournaments.create(adminId, "Admin yakka", 4);
        assertThatThrownBy(() -> tournaments.inviteTeam(adminId, solo.getId(), one, two))
                .isInstanceOfSatisfying(
                        ApiException.class, e -> assertThat(e.code()).isEqualTo("not_a_team_tournament"));

        TournamentEntity team = tournaments.create(adminId, "Admin jamoa", 4, TournamentEntity.Format.TEAM);
        assertThatThrownBy(() -> tournaments.inviteTeam(adminId, team.getId(), one, one))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("same_player"));
        assertThatThrownBy(() -> tournaments.invite(adminId, team.getId(), one))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("team_invite_required"));
    }

    @Test
    void adminCreationDefaultsToSoloButHonoursAnExplicitTeamRequest() throws Exception {
        String admin = adminLogin("AdminTeamFormat", "adm_team_fmt");

        JsonNode defaultCreated = json(post("/api/admin/tournaments")
                .header("Authorization", "Bearer " + admin)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Standart\",\"size\":4}"));
        assertThat(defaultCreated.get("format").asText()).isEqualTo("solo");

        JsonNode teamCreated = json(post("/api/admin/tournaments")
                .header("Authorization", "Bearer " + admin)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Jamoaviy\",\"size\":4,\"format\":\"team\"}"));
        assertThat(teamCreated.get("format").asText()).isEqualTo("team");

        mvc.perform(post("/api/admin/tournaments")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Noto'g'ri\",\"size\":4,\"format\":\"nonsense\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("invalid_format"));
    }

    @Test
    void anAdminInvitesAWholeSeatOverRestAndTheDetailNamesBothOfItsMembers() throws Exception {
        String admin = adminLogin("AdminTeamInvite", "adm_team_inv");
        long primaryId = createPlayer("ttadmrest1", 1500);
        long partnerId = createPlayer("ttadmrest2", 1400);

        JsonNode created = json(post("/api/admin/tournaments")
                .header("Authorization", "Bearer " + admin)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Admin jamoasi\",\"size\":4,\"format\":\"team\"}"));
        long tournamentId = created.get("id").asLong();

        mvc.perform(post("/api/admin/tournaments/" + tournamentId + "/invite-team")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":" + primaryId + ",\"partnerUserId\":" + partnerId + "}"))
                .andExpect(status().isOk());

        JsonNode detail = json(get("/api/admin/tournaments/" + tournamentId)
                .header("Authorization", "Bearer " + admin));
        assertThat(detail.get("tournament").get("format").asText()).isEqualTo("team");
        JsonNode seat = detail.get("participants").get(0);
        assertThat(seat.get("userId").asLong()).isEqualTo(primaryId);
        assertThat(seat.get("label").asText()).isEqualTo("ttadmrest1");
        assertThat(seat.get("partnerUserId").asLong()).isEqualTo(partnerId);
        assertThat(seat.get("partnerLabel").asText()).isEqualTo("ttadmrest2");
        assertThat(seat.get("status").asText()).isEqualTo("invited");
        assertThat(seat.get("partnerStatus").asText()).isEqualTo("invited");
    }

    @Test
    void anOrdinaryPlayerCannotInviteATeamThroughTheAdminRoute() throws Exception {
        String player = login("OddiyJamoachi");
        mvc.perform(post("/api/admin/tournaments/1/invite-team")
                        .header("Authorization", "Bearer " + player)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":1,\"partnerUserId\":2}"))
                .andExpect(status().isForbidden());
    }

    // --------------------------------------------------------------- helpers

    /** Every account {@code adminId} has been logged as acting on under {@code action}. */
    private List<Long> auditTargetsOf(long adminId, String action) {
        return auditEntries.findAll().stream()
                .filter(entry -> entry.getAdminUserId() == adminId && entry.getAction().equals(action))
                .map(AdminAuditLog::getTargetUserId)
                .toList();
    }

    /** Starts the match and forfeits for {@code loser}, whose whole team goes out; returns once the bracket has moved. */
    private void playOutLosing(TournamentMatch match, Team loser) {
        tournaments.startMatch(match.getPlayerOneUserId(), match.getId());
        // Waits for the settlement — and with it TournamentService.onTeamDuelFinished
        // — to land before this method returns.
        teamDuels.forfeitAndAwaitSettlement(loser.primary());
    }

    private TournamentMatch matchFor(List<TournamentMatch> round, long primaryUserId) {
        return round.stream()
                .filter(m -> m.hasPlayer(primaryUserId))
                .findFirst()
                .orElseThrow(() -> new AssertionError(primaryUserId + " plays no match in this round"));
    }

    private List<TournamentMatch> matchesOf(long tournamentId, int round) {
        return matchRepo.findByTournamentIdOrderByRoundAscSlotAsc(tournamentId).stream()
                .filter(m -> m.getRound() == round)
                .toList();
    }

    private static Set<Set<Long>> pairsOf(List<TournamentMatch> round) {
        Set<Set<Long>> pairs = new HashSet<>();
        for (TournamentMatch match : round) {
            pairs.add(Set.of(match.getPlayerOneUserId(), match.getPlayerTwoUserId()));
        }
        return pairs;
    }

    private int seedOf(long tournamentId, Team team) {
        return tournaments.participantViews(tournamentId).stream()
                .filter(p -> p.userId() == team.primary())
                .findFirst()
                .orElseThrow()
                .seed();
    }

    /** Two fresh players, both befriended by the organizer so the team may be invited. */
    private Team team(String prefix, double primaryRating, double partnerRating, long organizerId) {
        long primary = createPlayer(prefix + "1", primaryRating);
        long partner = createPlayer(prefix + "2", partnerRating);
        befriend(organizerId, primary);
        befriend(organizerId, partner);
        return new Team(primary, partner);
    }

    private void befriend(long a, long b) {
        friends.accept(b, friends.sendRequest(a, b).getId());
    }

    private long createPlayer(String nickname, double rating) {
        String token = login(nickname);
        claim(token, nickname);
        long id = userId(token);
        setRating(id, rating);
        return id;
    }

    private void setRating(long id, double rating) {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            User user = users.findById(id).orElseThrow();
            user.setRating(rating);
            users.save(user);
        });
    }

    private long adminUserId() {
        String suffix = String.valueOf(System.nanoTime() % 100000);
        return userId(adminLogin("TTAdmin", "ttadm" + suffix));
    }

    private String adminLogin(String name, String nickname) {
        String token = login(name);
        long id = userId(token);
        claim(token, nickname);
        new TransactionTemplate(transactionManager)
                .executeWithoutResult(status -> assertThat(users.grantAdmin(id)).isEqualTo(1));
        return token;
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
