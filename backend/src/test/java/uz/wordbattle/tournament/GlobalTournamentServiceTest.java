package uz.wordbattle.tournament;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.friend.FriendService;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * The weekly Global bracket, which nobody runs: it invites the top of the
 * ladder itself, offers every seat that comes back a no on down the ladder —
 * refused or simply never answered — and kicks off at its own fixed hour,
 * there being no organizer to press start and no way in from the outside
 * either. Filling early buys it nothing; the clock is the only thing that
 * starts one.
 *
 * <p>Every player here is rated far above the ones the rest of the suite plays
 * at, and each test takes a band higher than the last, so "the top of the
 * ladder" is always exactly the players the test in hand has just made. The
 * database is shared with every other test class in this context, and the
 * ranking these features run on is global by nature.
 */
@SpringBootTest
@AutoConfigureMockMvc
class GlobalTournamentServiceTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private TournamentService tournaments;

    @Autowired
    private TournamentMatchRepository matchRepo;

    @Autowired
    private FriendService friends;

    @Autowired
    private UserRepository users;

    @Autowired
    private PlatformTransactionManager transactionManager;

    /** Handed out one per test, so no two tests can be at the top of the ladder at once. */
    private static final AtomicInteger nextBand = new AtomicInteger();

    /**
     * Nobody is asked to join a Global bracket; it asks them. Whoever is best
     * at the game that week is invited and answers as they would answer a
     * friend's invite — and then everybody waits. A bracket full days early
     * does not start early: the one tournament everybody is in kicks off at
     * its hour, which is a thing a player can plan a Sunday around.
     */
    @Test
    void invitesTheTopOfTheLadderAndKicksOffOnlyWhenItsHourComesRoundEvenIfItFilledEarly() {
        List<Long> ladder = ladder("gtsolo", 5);
        TournamentEntity tournament = tournaments.createGlobalTournament(4, 1500);
        tournaments.inviteTopRankedSolo(tournament);

        // The best four and nobody else — the fifth is next in line, not in it.
        assertThat(everyoneIn(tournament.getId())).containsExactlyInAnyOrderElementsOf(ladder.subList(0, 4));
        assertThat(tournaments.participantViews(tournament.getId()))
                .allSatisfy(seat -> assertThat(seat.status()).isEqualTo("invited"));

        // Invite-only while it fills, which is what closes the self-join door
        // on it: there is nothing here for a stranger scrolling the browse
        // list, whose guest list was decided the moment the bracket opened.
        assertThat(tournament.getVisibility()).isEqualTo(TournamentEntity.Visibility.PRIVATE);
        assertThat(browsableIds()).doesNotContain(tournament.getId());

        // Nobody sent the invite, and it says so rather than crediting an
        // admin who did nothing.
        TournamentInviteDto invite = inviteTo(ladder.get(0), tournament.getId());
        assertThat(invite.kind()).isEqualTo("global");
        assertThat(invite.organizer()).isNull();

        for (long id : ladder.subList(0, 4)) tournaments.accept(id, tournament.getId());

        // Every seat taken, and nothing has started: no player's acceptance
        // brings a bracket forward, however full it leaves it.
        TournamentEntity waiting = tournaments.require(tournament.getId());
        assertThat(waiting.getStatus()).isEqualTo(TournamentEntity.Status.OPEN);
        assertThat(tournaments.summaryOf(waiting).acceptedCount()).isEqualTo(4);
        assertThat(matchesOf(tournament.getId(), 1)).isEmpty();

        tournaments.finalizeOpenGlobal(TournamentEntity.Format.SOLO);

        TournamentEntity started = tournaments.require(tournament.getId());
        assertThat(started.getStatus()).isEqualTo(TournamentEntity.Status.IN_PROGRESS);
        assertThat(started.getSize()).as("a bracket that filled is not shrunk").isEqualTo(4);
        assertThat(matchesOf(tournament.getId(), 1)).hasSize(2);

        // And now that there is something to watch, it is discoverable.
        assertThat(browsableIds()).contains(tournament.getId());
    }

    /** A refusal costs the bracket nothing but a name: the seat carries on down the ladder. */
    @Test
    void aRefusedSeatIsOfferedToTheNextPlayerDown() {
        List<Long> ladder = ladder("gtdec", 5);
        TournamentEntity tournament = tournaments.createGlobalTournament(4, 1500);
        tournaments.inviteTopRankedSolo(tournament);

        tournaments.decline(ladder.get(3), tournament.getId());

        assertThat(statusOf(tournament.getId(), ladder.get(3))).isEqualTo("declined");
        assertThat(waitingIn(tournament.getId()))
                .containsExactlyInAnyOrder(ladder.get(0), ladder.get(1), ladder.get(2), ladder.get(4));

        // The replacement is a seat like any other, and fills the bracket.
        for (long id : List.of(ladder.get(0), ladder.get(1), ladder.get(2), ladder.get(4))) {
            tournaments.accept(id, tournament.getId());
        }
        assertThat(tournaments.summaryOf(tournaments.require(tournament.getId())).acceptedCount()).isEqualTo(4);
    }

    /**
     * Silence, not refusal, is what a bracket actually has to survive: a player
     * who has not opened the app since the invite went out is never going to
     * tap "Hozir emas". Past the configured patience the seat is given up on
     * for them and cascades exactly as a tapped refusal would.
     */
    @Test
    void anInviteNobodyEverAnsweredExpiresAndTheSeatMovesOn() {
        List<Long> ladder = ladder("gtexp", 5);
        TournamentEntity tournament = tournaments.createGlobalTournament(4, 1500);
        tournaments.inviteTopRankedSolo(tournament);
        for (long id : ladder.subList(0, 3)) tournaments.accept(id, tournament.getId());

        // A patience of nothing at all expires every invite still outstanding,
        // which here is the one nobody answered.
        assertThat(tournaments.expireStaleGlobalInvites(Duration.ZERO)).isPositive();

        assertThat(statusOf(tournament.getId(), ladder.get(3))).isEqualTo("declined");
        assertThat(waitingIn(tournament.getId())).containsExactly(ladder.get(4));
        for (long id : ladder.subList(0, 3)) {
            assertThat(statusOf(tournament.getId(), id))
                    .as("an answered seat is not swept out from under its player")
                    .isEqualTo("accepted");
        }

        tournaments.accept(ladder.get(4), tournament.getId());
        assertThat(tournaments.summaryOf(tournaments.require(tournament.getId())).acceptedCount()).isEqualTo(4);
    }

    /**
     * The 2v2 bracket, which has to invent the teams as well as invite them.
     * Strongest is seated with weakest so that every seat comes out about as
     * strong as every other — pairing the top two together would decide the
     * bracket before a word was played — and a seat half of which refuses is
     * repaired in place, leaving the acceptance the other half already gave.
     */
    @Test
    void aTeamBracketPairsStrongestWithWeakestAndRepairsASeatInPlace() {
        List<Long> ladder = ladder("gtteam", 9);
        TournamentEntity tournament = tournaments.createGlobalTeamTournament(4, 1500);
        tournaments.inviteTopRankedTeam(tournament);

        assertThat(seatsOf(tournament.getId())).containsExactlyInAnyOrder(
                Set.of(ladder.get(0), ladder.get(7)),
                Set.of(ladder.get(1), ladder.get(6)),
                Set.of(ladder.get(2), ladder.get(5)),
                Set.of(ladder.get(3), ladder.get(4)));
        assertThat(everyoneIn(tournament.getId())).doesNotContain(ladder.get(8));

        tournaments.accept(ladder.get(7), tournament.getId());
        tournaments.decline(ladder.get(0), tournament.getId());

        TournamentParticipantDto seat = seatHolding(tournament.getId(), ladder.get(7));
        assertThat(Set.of(seat.userId(), seat.partnerUserId()))
                .as("the refused half, and only that half, changed hands")
                .isEqualTo(Set.of(ladder.get(8), ladder.get(7)));
        assertThat(answerOf(seat, ladder.get(8))).isEqualTo("invited");
        assertThat(answerOf(seat, ladder.get(7)))
                .as("a player who already accepted is not made to answer again")
                .isEqualTo("accepted");
        assertThat(everyoneIn(tournament.getId())).doesNotContain(ladder.get(0));
    }

    /**
     * Sunday evening. The week collected five of the eight seats it hoped for, so the
     * bracket becomes the largest one those five fill — a four — and the
     * weakest of the five is the one left out, the tournament being played by
     * the strongest of whoever actually answered.
     *
     * <p>And the door shuts behind it: nobody still sitting on an invite when
     * the hour came can wander in afterwards, and nobody new is asked
     * either. Closing the window is not a vacancy.
     */
    @Test
    void theKickoffShrinksAPartlyFilledBracketAndShutsTheDoorOnWhoeverNeverAnswered() {
        List<Long> ladder = ladder("gtfin", 8);
        TournamentEntity tournament = tournaments.createGlobalTournament(8, 1500);
        tournaments.inviteTopRankedSolo(tournament);
        for (long id : ladder.subList(0, 5)) tournaments.accept(id, tournament.getId());

        tournaments.finalizeOpenGlobal(TournamentEntity.Format.SOLO);

        TournamentEntity closed = tournaments.require(tournament.getId());
        assertThat(closed.getStatus()).isEqualTo(TournamentEntity.Status.IN_PROGRESS);
        assertThat(closed.getSize()).as("eight seats were never going to fill, four did").isEqualTo(4);
        assertThat(matchesOf(tournament.getId(), 1)).hasSize(2);
        assertThat(playersIn(matchesOf(tournament.getId(), 1)))
                .containsExactlyInAnyOrderElementsOf(ladder.subList(0, 4));

        assertThat(statusOf(tournament.getId(), ladder.get(4)))
                .as("the weakest of those who accepted is the one trimmed")
                .isEqualTo("declined");
        for (long id : ladder.subList(5, 8)) {
            assertThat(statusOf(tournament.getId(), id)).isEqualTo("declined");
        }
        assertThat(everyoneIn(tournament.getId()))
                .as("the kickoff asked nobody new — this is a window closing, not a seat coming free")
                .containsExactlyInAnyOrderElementsOf(ladder);

        assertThatThrownBy(() -> tournaments.accept(ladder.get(5), tournament.getId()))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("invite_resolved"));
    }

    /** A week that could not raise even the smallest bracket is called off rather than played four-handed. */
    @Test
    void theKickoffCancelsABracketFewerThanFourPlayersAcceptedInto() {
        List<Long> ladder = ladder("gtfinx", 8);
        TournamentEntity tournament = tournaments.createGlobalTournament(8, 1500);
        tournaments.inviteTopRankedSolo(tournament);
        for (long id : ladder.subList(0, 3)) tournaments.accept(id, tournament.getId());

        tournaments.finalizeOpenGlobal(TournamentEntity.Format.SOLO);

        TournamentEntity closed = tournaments.require(tournament.getId());
        assertThat(closed.getStatus()).isEqualTo(TournamentEntity.Status.CANCELLED);
        assertThat(closed.getFinishedAt()).isNotNull();
        assertThat(matchesOf(tournament.getId(), 1)).isEmpty();
    }

    /**
     * The same kickoff over 2v2 seats, where "accepted" takes two people: a
     * seat only one half of which answered is not one of the four the shrunk
     * bracket is built from.
     */
    @Test
    void theKickoffShrinksATeamBracketCountingOnlySeatsBothHalvesAccepted() {
        List<Long> ladder = ladder("gttfin", 16);
        TournamentEntity tournament = tournaments.createGlobalTeamTournament(8, 1500);
        tournaments.inviteTopRankedTeam(tournament);

        // Seats are rank i beside rank 15-i, so these four are whole teams.
        for (int i = 0; i < 4; i++) {
            tournaments.accept(ladder.get(i), tournament.getId());
            tournaments.accept(ladder.get(15 - i), tournament.getId());
        }
        // A fifth seat where only one of the two ever answered.
        tournaments.accept(ladder.get(4), tournament.getId());

        tournaments.finalizeOpenGlobal(TournamentEntity.Format.TEAM);

        TournamentEntity closed = tournaments.require(tournament.getId());
        assertThat(closed.getStatus()).isEqualTo(TournamentEntity.Status.IN_PROGRESS);
        assertThat(closed.getSize()).isEqualTo(4);

        List<TournamentMatch> round1 = matchesOf(tournament.getId(), 1);
        assertThat(round1).hasSize(2);
        assertThat(playersIn(round1))
                .as("the four whole teams, named by the primary member each was seated under")
                .containsExactlyInAnyOrderElementsOf(ladder.subList(0, 4));
        for (TournamentMatch match : round1) {
            assertThat(match.getPlayerOnePartnerUserId()).isNotNull();
            assertThat(match.getPlayerTwoPartnerUserId()).isNotNull();
        }

        TournamentParticipantDto halfAnswered = seatHolding(tournament.getId(), ladder.get(4));
        assertThat(answerOf(halfAnswered, ladder.get(4))).isEqualTo("accepted");
        assertThat(answerOf(halfAnswered, ladder.get(11)))
                .as("the half that never answered was closed out with the window")
                .isEqualTo("declined");
    }

    /**
     * A player who accepted on Monday and was banned on Thursday cannot be
     * seeded on Sunday, and there is nobody watching the kickoff to be told
     * so. Their seat is dropped and the week goes on with whoever is left —
     * where an organizer pressing start would still be refused, because there
     * is somebody there to read the refusal and do something about it.
     */
    @Test
    void theKickoffDropsASeatWhosePlayerIsNoLongerThereRatherThanFailingOverIt() {
        List<Long> ladder = ladder("gtgone", 8);
        TournamentEntity tournament = tournaments.createGlobalTournament(8, 1500);
        tournaments.inviteTopRankedSolo(tournament);
        for (long id : ladder.subList(0, 5)) tournaments.accept(id, tournament.getId());

        ban(ladder.get(0));

        tournaments.finalizeOpenGlobal(TournamentEntity.Format.SOLO);

        TournamentEntity closed = tournaments.require(tournament.getId());
        assertThat(closed.getStatus()).isEqualTo(TournamentEntity.Status.IN_PROGRESS);
        assertThat(closed.getSize()).isEqualTo(4);
        assertThat(playersIn(matchesOf(tournament.getId(), 1)))
                .as("four of the five who accepted are still here, and they are the bracket")
                .containsExactlyInAnyOrderElementsOf(ladder.subList(1, 5));
        assertThat(statusOf(tournament.getId(), ladder.get(0))).isEqualTo("declined");
    }

    /** Half a team is no team: the seat goes whole, and its surviving member is not seeded alone. */
    @Test
    void theKickoffDropsATeamSeatThatLostOneOfItsTwo() {
        List<Long> ladder = ladder("gttgone", 16);
        TournamentEntity tournament = tournaments.createGlobalTeamTournament(8, 1500);
        tournaments.inviteTopRankedTeam(tournament);
        for (int i = 0; i < 5; i++) {
            tournaments.accept(ladder.get(i), tournament.getId());
            tournaments.accept(ladder.get(15 - i), tournament.getId());
        }

        deleteAccount(ladder.get(0));

        tournaments.finalizeOpenGlobal(TournamentEntity.Format.TEAM);

        TournamentEntity closed = tournaments.require(tournament.getId());
        assertThat(closed.getStatus()).isEqualTo(TournamentEntity.Status.IN_PROGRESS);
        assertThat(closed.getSize()).isEqualTo(4);
        assertThat(playersIn(matchesOf(tournament.getId(), 1)))
                .as("the four seats still holding two live players")
                .containsExactlyInAnyOrderElementsOf(ladder.subList(1, 5));
        assertThat(statusOf(tournament.getId(), ladder.get(0))).isEqualTo("declined");
        assertThat(everyoneIn(tournament.getId()))
                .as("the teammate is out with the seat, not carried on into a bracket alone")
                .contains(ladder.get(15));
        assertThat(playersIn(matchesOf(tournament.getId(), 1))).doesNotContain(ladder.get(15));
    }

    /** Four teams is the smallest 2v2 bracket there is; three whole teams is not a tournament. */
    @Test
    void theKickoffCancelsATeamBracketFewerThanFourTeamsAcceptedInto() {
        List<Long> ladder = ladder("gttfinx", 8);
        TournamentEntity tournament = tournaments.createGlobalTeamTournament(4, 1500);
        tournaments.inviteTopRankedTeam(tournament);

        tournaments.accept(ladder.get(0), tournament.getId());
        tournaments.accept(ladder.get(7), tournament.getId());

        tournaments.finalizeOpenGlobal(TournamentEntity.Format.TEAM);

        TournamentEntity closed = tournaments.require(tournament.getId());
        assertThat(closed.getStatus()).isEqualTo(TournamentEntity.Status.CANCELLED);
        assertThat(matchesOf(tournament.getId(), 1)).isEmpty();
    }

    /**
     * Filling a bracket starts nothing, whoever runs it. A Global one waits for
     * its hour; everybody else's waits on the organizer who ran it, who may
     * well be waiting for something the server cannot see.
     */
    @Test
    void aFriendsBracketStillWaitsForItsOrganizerEvenOnceEveryoneHasAccepted() {
        List<Long> ladder = ladder("gtfr", 5);
        long organizerId = ladder.get(0);
        List<Long> guests = ladder.subList(1, 5);
        for (long id : guests) befriend(organizerId, id);

        TournamentEntity tournament =
                tournaments.createByUser(organizerId, "Do'stona", 4, TournamentEntity.Visibility.PRIVATE);
        for (long id : guests) tournaments.inviteByUser(organizerId, tournament.getId(), id);
        for (long id : guests) tournaments.accept(id, tournament.getId());

        assertThat(tournaments.summaryOf(tournaments.require(tournament.getId())).acceptedCount()).isEqualTo(4);
        assertThat(tournaments.require(tournament.getId()).getStatus()).isEqualTo(TournamentEntity.Status.OPEN);

        tournaments.startByUser(organizerId, tournament.getId());
        assertThat(tournaments.require(tournament.getId()).getStatus())
                .isEqualTo(TournamentEntity.Status.IN_PROGRESS);
    }

    // --------------------------------------------------------------- helpers

    /** {@code count} fresh players, best first and every one of them above everybody else in the database. */
    private List<Long> ladder(String prefix, int count) {
        int base = 100_000 + nextBand.getAndIncrement() * 1_000;
        List<Long> ids = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            ids.add(createPlayer(prefix + i, base + (count - i) * 10));
        }
        return ids;
    }

    /** Everyone this bracket has a seat for, on either side of one. */
    private Set<Long> everyoneIn(long tournamentId) {
        Set<Long> ids = new HashSet<>();
        for (TournamentParticipantDto seat : tournaments.participantViews(tournamentId)) {
            ids.add(seat.userId());
            if (seat.partnerUserId() != null) ids.add(seat.partnerUserId());
        }
        return ids;
    }

    /** Each seat as the pair of people holding it. */
    private Set<Set<Long>> seatsOf(long tournamentId) {
        Set<Set<Long>> seats = new HashSet<>();
        for (TournamentParticipantDto seat : tournaments.participantViews(tournamentId)) {
            seats.add(Set.of(seat.userId(), seat.partnerUserId()));
        }
        return seats;
    }

    /** Whoever still owes this bracket an answer. */
    private List<Long> waitingIn(long tournamentId) {
        return tournaments.participantViews(tournamentId).stream()
                .filter(seat -> "invited".equals(seat.status()))
                .map(TournamentParticipantDto::userId)
                .toList();
    }

    private String statusOf(long tournamentId, long userId) {
        return tournaments.participantViews(tournamentId).stream()
                .filter(seat -> seat.userId().equals(userId))
                .findFirst()
                .orElseThrow(() -> new AssertionError(userId + " holds no seat here"))
                .status();
    }

    private TournamentParticipantDto seatHolding(long tournamentId, Long memberId) {
        return tournaments.participantViews(tournamentId).stream()
                .filter(seat -> memberId.equals(seat.userId()) || memberId.equals(seat.partnerUserId()))
                .findFirst()
                .orElseThrow(() -> new AssertionError(memberId + " holds no seat here"));
    }

    /** How whichever half of this seat {@code memberId} is answered for themselves. */
    private static String answerOf(TournamentParticipantDto seat, long memberId) {
        return seat.userId().equals(memberId) ? seat.status() : seat.partnerStatus();
    }

    private TournamentInviteDto inviteTo(long userId, long tournamentId) {
        return tournaments.mine(userId).invites().stream()
                .filter(invite -> invite.tournamentId().equals(tournamentId))
                .findFirst()
                .orElseThrow(() -> new AssertionError(userId + " was not invited to " + tournamentId));
    }

    private List<Long> browsableIds() {
        return tournaments.browse(0, 100).stream().map(TournamentSummaryDto::id).toList();
    }

    /** Whoever a round is drawn between — a team's primary member standing for the pair, as the bracket knows it. */
    private static List<Long> playersIn(List<TournamentMatch> round) {
        List<Long> ids = new ArrayList<>();
        for (TournamentMatch match : round) {
            ids.add(match.getPlayerOneUserId());
            ids.add(match.getPlayerTwoUserId());
        }
        return ids;
    }

    private List<TournamentMatch> matchesOf(long tournamentId, int round) {
        return matchRepo.findByTournamentIdOrderByRoundAscSlotAsc(tournamentId).stream()
                .filter(m -> m.getRound() == round)
                .toList();
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

    /** Bans the account the way the admin panel does — the participant row it holds is left exactly as it was. */
    private void ban(long id) {
        new TransactionTemplate(transactionManager)
                .executeWithoutResult(status -> assertThat(users.ban(id, Instant.now())).isEqualTo(1));
    }

    /** The other way a player stops being seedable: the anonymised shell a deleted account leaves behind. */
    private void deleteAccount(long id) {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            User user = users.findById(id).orElseThrow();
            user.anonymise(Instant.now());
            users.save(user);
        });
    }

    private void setRating(long id, double rating) {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            User user = users.findById(id).orElseThrow();
            user.setRating(rating);
            users.save(user);
        });
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
}
