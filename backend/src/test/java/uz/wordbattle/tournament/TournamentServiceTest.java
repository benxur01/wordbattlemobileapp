package uz.wordbattle.tournament;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.ws.SocketRegistry;

/**
 * The bracket, end to end: seeding an 8-player tournament by rating, playing
 * every round through the same {@link DuelService} a real duel uses, and
 * watching the winner advance itself all the way to a champion — plus the two
 * doors around it: who may read a bracket (anyone signed in) and who may
 * change one (only its own participants, and only the admin who runs it).
 */
@SpringBootTest
@AutoConfigureMockMvc
class TournamentServiceTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private TournamentService tournaments;

    @Autowired
    private TournamentMatchRepository matchRepo;

    @Autowired
    private DuelService duels;

    @Autowired
    private UserRepository users;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @Autowired
    private SocketRegistry sockets;

    /**
     * Seeds by rating, pairs the strongest against the weakest each round, and
     * advances the winner of every duel into the correct next-round slot until
     * a champion is decided — the whole of {@link TournamentService#start} and
     * {@link TournamentService#onDuelFinished} in one pass.
     */
    @Test
    void seedsAnEightPlayerBracketAndPlaysItToAChampion() throws Exception {
        long adminId = adminUserId();

        // ids[0] is rated highest (seed 1) down to ids[7] rated lowest (seed 8).
        long[] ids = new long[8];
        for (int i = 0; i < 8; i++) {
            ids[i] = createPlayer("tbseed" + i, 1700 - i * 100);
        }

        TournamentEntity tournament = tournaments.create(adminId, "Kuz mavsumi", 8);
        for (long id : ids) tournaments.invite(adminId, tournament.getId(), id);
        for (long id : ids) tournaments.accept(id, tournament.getId());

        tournaments.start(adminId, tournament.getId());

        List<TournamentMatch> round1 = matchesOf(tournament.getId(), 1);
        assertThat(round1).hasSize(4);
        assertThat(pairsOf(round1)).containsExactlyInAnyOrder(
                Set.of(ids[0], ids[7]), Set.of(ids[3], ids[4]), Set.of(ids[1], ids[6]), Set.of(ids[2], ids[5]));
        assertThat(round1).allSatisfy(m -> assertThat(m.getStatus()).isEqualTo(TournamentMatch.Status.READY));

        // The better seed (the lower array index) wins every match, all the way
        // to the final — so the champion has to be ids[0], seed one.
        for (TournamentMatch match : round1) {
            playOutFavouringLowerIndex(match, ids);
        }

        List<TournamentMatch> round2 = matchesOf(tournament.getId(), 2);
        assertThat(round2).hasSize(2);
        assertThat(pairsOf(round2)).containsExactlyInAnyOrder(Set.of(ids[0], ids[3]), Set.of(ids[1], ids[2]));
        assertThat(round2).allSatisfy(m -> assertThat(m.getStatus()).isEqualTo(TournamentMatch.Status.READY));

        for (TournamentMatch match : round2) {
            playOutFavouringLowerIndex(match, ids);
        }

        List<TournamentMatch> round3 = matchesOf(tournament.getId(), 3);
        assertThat(round3).hasSize(1);
        TournamentMatch finalMatch = round3.get(0);
        assertThat(Set.of(finalMatch.getPlayerOneUserId(), finalMatch.getPlayerTwoUserId()))
                .isEqualTo(Set.of(ids[0], ids[1]));
        assertThat(finalMatch.getStatus()).isEqualTo(TournamentMatch.Status.READY);

        playOutFavouringLowerIndex(finalMatch, ids);

        TournamentEntity finished = tournaments.require(tournament.getId());
        assertThat(finished.getStatus()).isEqualTo(TournamentEntity.Status.COMPLETED);
        assertThat(finished.getChampionUserId()).isEqualTo(ids[0]);
        assertThat(finished.getFinishedAt()).isNotNull();

        // The bracket is readable by a signed-in player who was never in it —
        // opt-in spectating, not participant-only.
        String outsider = login("Tomoshabin");
        JsonNode detail = json(get("/api/tournaments/" + tournament.getId()).header("Authorization", "Bearer " + outsider));
        assertThat(detail.get("status").asText()).isEqualTo("completed");
        assertThat(detail.get("champion").get("id").asLong()).isEqualTo(ids[0]);
        assertThat(detail.get("rounds")).hasSize(3);

        // A completed tournament is no longer "active" — the discovery card is
        // for the one currently being played.
        JsonNode active = json(get("/api/tournaments/active").header("Authorization", "Bearer " + outsider));
        for (JsonNode row : active) {
            assertThat(row.get("id").asLong()).isNotEqualTo(tournament.getId());
        }
    }

    @Test
    void aTournamentInProgressIsDiscoverableByAnyoneSignedIn() throws Exception {
        long adminId = adminUserId();
        long[] ids = {createPlayer("tbact0", 1500), createPlayer("tbact1", 1400),
                createPlayer("tbact2", 1300), createPlayer("tbact3", 1200)};
        TournamentEntity tournament = tournaments.create(adminId, "Faol turnir", 4);
        for (long id : ids) tournaments.invite(adminId, tournament.getId(), id);
        for (long id : ids) tournaments.accept(id, tournament.getId());
        tournaments.start(adminId, tournament.getId());

        String outsider = login("Tashqi");
        JsonNode active = json(get("/api/tournaments/active").header("Authorization", "Bearer " + outsider));
        boolean present = false;
        for (JsonNode row : active) {
            if (row.get("id").asLong() == tournament.getId()) present = true;
        }
        assertThat(present).as("the in-progress tournament is in the discovery list").isTrue();

        mvc.perform(get("/api/tournaments/" + tournament.getId()).header("Authorization", "Bearer " + outsider))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("in_progress"));
    }

    @Test
    void startingRefusesUntilExactlyTheTargetHasAccepted() {
        long adminId = adminUserId();
        long a = createPlayer("tbready0", 1200);
        long b = createPlayer("tbready1", 1200);
        TournamentEntity tournament = tournaments.create(adminId, "Yarim tayyor", 4);
        tournaments.invite(adminId, tournament.getId(), a);
        tournaments.invite(adminId, tournament.getId(), b);
        tournaments.accept(a, tournament.getId());
        // b never accepts.

        assertThatThrownBy(() -> tournaments.start(adminId, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("not_ready"));
    }

    @Test
    void onlyTheInvitedPlayerCanAnswerTheirOwnInvite() {
        long adminId = adminUserId();
        long invited = createPlayer("tbinv0", 1200);
        long stranger = createPlayer("tbinv1", 1200);
        TournamentEntity tournament = tournaments.create(adminId, "Yopiq taklif", 4);
        tournaments.invite(adminId, tournament.getId(), invited);

        assertThatThrownBy(() -> tournaments.accept(stranger, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("invite_not_found"));

        tournaments.accept(invited, tournament.getId());
        assertThatThrownBy(() -> tournaments.decline(invited, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("invite_resolved"));
    }

    @Test
    void adminCreationRefusesAnythingOtherThanAPowerOfTwoUpTo32() throws Exception {
        String admin = adminLogin("BoshqaruvchiSize", "adm_size_t");
        mvc.perform(post("/api/admin/tournaments")
                        .header("Authorization", "Bearer " + admin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Noto'g'ri\",\"size\":6}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("invalid_size"));
    }

    @Test
    void anOrdinaryPlayerCannotUseTheAdminTournamentRoutes() throws Exception {
        String player = login("OddiyOyinchi");
        mvc.perform(post("/api/admin/tournaments")
                        .header("Authorization", "Bearer " + player)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Sinov\",\"size\":4}"))
                .andExpect(status().isForbidden());
    }

    // ------------------------------------------------------------------- cancel

    @Test
    void cancellingNotifiesEveryParticipantWhetherInvitedOrAccepted() throws Exception {
        long adminId = adminUserId();
        long accepted = createPlayer("tcancel0", 1200);
        long stillInvited = createPlayer("tcancel1", 1200);
        TournamentEntity tournament = tournaments.create(adminId, "Bekor bo'ladigan", 4);
        tournaments.invite(adminId, tournament.getId(), accepted);
        tournaments.invite(adminId, tournament.getId(), stillInvited);
        tournaments.accept(accepted, tournament.getId());
        // stillInvited never answers.

        WebSocketSession acceptedSocket = registerSocket(accepted);
        WebSocketSession invitedSocket = registerSocket(stillInvited);

        TournamentEntity cancelled = tournaments.cancel(adminId, tournament.getId());
        assertThat(cancelled.getStatus()).isEqualTo(TournamentEntity.Status.CANCELLED);
        assertThat(cancelled.getFinishedAt()).isNotNull();

        assertThat(cancellationFrame(acceptedSocket).get("tournamentId").asLong()).isEqualTo(tournament.getId());
        assertThat(cancellationFrame(invitedSocket).get("tournamentId").asLong()).isEqualTo(tournament.getId());
    }

    @Test
    void cancellingAnAlreadyCompletedTournamentIsRefused() throws Exception {
        long adminId = adminUserId();
        long[] ids = {createPlayer("tcancelc0", 1200), createPlayer("tcancelc1", 1100),
                createPlayer("tcancelc2", 1000), createPlayer("tcancelc3", 900)};
        TournamentEntity tournament = tournaments.create(adminId, "Tugagan", 4);
        for (long id : ids) tournaments.invite(adminId, tournament.getId(), id);
        for (long id : ids) tournaments.accept(id, tournament.getId());
        tournaments.start(adminId, tournament.getId());
        for (TournamentMatch match : matchesOf(tournament.getId(), 1)) playOutFavouringLowerIndex(match, ids);
        playOutFavouringLowerIndex(matchesOf(tournament.getId(), 2).get(0), ids);
        assertThat(tournaments.require(tournament.getId()).getStatus()).isEqualTo(TournamentEntity.Status.COMPLETED);

        assertThatThrownBy(() -> tournaments.cancel(adminId, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("tournament_not_active"));
    }

    @Test
    void cancellingAnAlreadyCancelledTournamentIsRefused() {
        long adminId = adminUserId();
        TournamentEntity tournament = tournaments.create(adminId, "Ikki marta bekor", 4);
        tournaments.cancel(adminId, tournament.getId());

        assertThatThrownBy(() -> tournaments.cancel(adminId, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("tournament_not_active"));
    }

    /**
     * The one case cancelling must not touch: a duel already live when its
     * tournament is called off has to be allowed to finish normally for its
     * two players. Only the bracket stops moving — the match itself still
     * gets its winner, and the round it would have fed is left exactly as it
     * was.
     */
    @Test
    void aDuelAlreadyLiveWhenItsTournamentIsCancelledStillSettlesButTheBracketDoesNotMove() throws Exception {
        long adminId = adminUserId();
        long[] ids = {createPlayer("tcancellive0", 1200), createPlayer("tcancellive1", 1200),
                createPlayer("tcancellive2", 1200), createPlayer("tcancellive3", 1200)};
        TournamentEntity tournament = tournaments.create(adminId, "Jonli bekor", 4);
        for (long id : ids) tournaments.invite(adminId, tournament.getId(), id);
        for (long id : ids) tournaments.accept(id, tournament.getId());
        tournaments.start(adminId, tournament.getId());

        TournamentMatch match = matchesOf(tournament.getId(), 1).get(0);
        long winner = match.getPlayerOneUserId();
        long loser = match.getPlayerTwoUserId();
        tournaments.startMatch(winner, match.getId());

        tournaments.cancel(adminId, tournament.getId());

        duels.forfeitAndAwaitSettlement(loser);

        TournamentMatch settled = matchRepo.findById(match.getId()).orElseThrow();
        assertThat(settled.getStatus()).isEqualTo(TournamentMatch.Status.DONE);
        assertThat(settled.getWinnerUserId()).isEqualTo(winner);

        assertThat(tournaments.require(tournament.getId()).getStatus()).isEqualTo(TournamentEntity.Status.CANCELLED);

        int nextSlot = settled.getSlot() / 2;
        TournamentMatch next = matchesOf(tournament.getId(), 2).stream()
                .filter(m -> m.getSlot() == nextSlot)
                .findFirst()
                .orElseThrow();
        assertThat(next.getStatus()).isEqualTo(TournamentMatch.Status.PENDING);
        assertThat(next.getPlayerOneUserId()).isNull();
        assertThat(next.getPlayerTwoUserId()).isNull();
    }

    @Test
    void answeringAnInviteToACancelledTournamentIsRefused() {
        long adminId = adminUserId();
        long invited = createPlayer("tcancelacc0", 1200);
        TournamentEntity tournament = tournaments.create(adminId, "Bekor qilingan taklif", 4);
        tournaments.invite(adminId, tournament.getId(), invited);
        tournaments.cancel(adminId, tournament.getId());

        assertThatThrownBy(() -> tournaments.accept(invited, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("tournament_cancelled"));
        assertThatThrownBy(() -> tournaments.decline(invited, tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("tournament_cancelled"));
    }

    @Test
    void startingAMatchInACancelledTournamentIsRefusedAndStartsNoDuel() throws Exception {
        long adminId = adminUserId();
        long[] ids = {createPlayer("tcancelstart0", 1200), createPlayer("tcancelstart1", 1200),
                createPlayer("tcancelstart2", 1200), createPlayer("tcancelstart3", 1200)};
        TournamentEntity tournament = tournaments.create(adminId, "Bekor bo'lgan jang", 4);
        for (long id : ids) tournaments.invite(adminId, tournament.getId(), id);
        for (long id : ids) tournaments.accept(id, tournament.getId());
        tournaments.start(adminId, tournament.getId());

        TournamentMatch match = matchesOf(tournament.getId(), 1).get(0);
        long sender = match.getPlayerOneUserId();
        tournaments.cancel(adminId, tournament.getId());

        WebSocketSession socket = registerSocket(sender);
        tournaments.startMatch(sender, match.getId());

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(socket).sendMessage(captor.capture());
        JsonNode frame = mapper.readTree(captor.getValue().getPayload());
        assertThat(frame.get("type").asText()).isEqualTo("error");
        assertThat(frame.get("payload").get("code").asText()).isEqualTo("tournament_cancelled");

        assertThat(matchRepo.findById(match.getId()).orElseThrow().getStatus()).isEqualTo(TournamentMatch.Status.READY);
    }

    /** A stand-in socket registered directly with the real {@link SocketRegistry}, the same way {@code AccountDeletionTest} does — there is no server here for a real one to connect to. */
    private WebSocketSession registerSocket(long userId) {
        WebSocketSession socket = mock(WebSocketSession.class);
        given(socket.isOpen()).willReturn(true);
        sockets.register(userId, socket);
        return socket;
    }

    private JsonNode cancellationFrame(WebSocketSession socket) throws Exception {
        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(socket).sendMessage(captor.capture());
        JsonNode frame = mapper.readTree(captor.getValue().getPayload());
        assertThat(frame.get("type").asText()).isEqualTo("tournament.cancelled");
        return frame.get("payload");
    }

    // --------------------------------------------------------------- helpers

    /** Starts the match, forfeits whichever player has the higher array index, and waits for the bracket to move. */
    private void playOutFavouringLowerIndex(TournamentMatch match, long[] ids) throws Exception {
        long playerOne = match.getPlayerOneUserId();
        long playerTwo = match.getPlayerTwoUserId();
        long winner = indexOf(ids, playerOne) < indexOf(ids, playerTwo) ? playerOne : playerTwo;
        long loser = winner == playerOne ? playerTwo : playerOne;

        tournaments.startMatch(winner, match.getId());
        // Waits for the settlement — and with it TournamentService.onDuelFinished
        // — to land before this method returns.
        duels.forfeitAndAwaitSettlement(loser);
    }

    private static int indexOf(long[] ids, long value) {
        for (int i = 0; i < ids.length; i++) {
            if (ids[i] == value) return i;
        }
        throw new AssertionError(value + " is not one of the seeded players");
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
        String token = adminLogin("TAdmin", "tadm" + suffix);
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

    private String adminLogin(String name, String nickname) {
        String token = login(name);
        long id = userId(token);
        claim(token, nickname);
        new TransactionTemplate(transactionManager)
                .executeWithoutResult(status -> assertThat(users.grantAdmin(id)).isEqualTo(1));
        return token;
    }

    private void claim(String token, String nickname) {
        try {
            mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put("/api/users/me/nickname")
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
