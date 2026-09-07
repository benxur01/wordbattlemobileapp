package uz.wordbattle.tournament;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import uz.wordbattle.admin.AdminAuditService;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.friend.FriendService;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.match.DuelSession;
import uz.wordbattle.match.TeamDuelService;
import uz.wordbattle.match.TeamDuelSession;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.SocketRegistry;

/**
 * Single-elimination tournaments, curated by the admin panel, by an ordinary
 * player organizing one among their own friends, or — since {@link #join} —
 * by nobody at all: a {@code PUBLIC} tournament lets a stranger seat
 * themselves, no invitation required. No payment anywhere near any of the
 * three — that scope was cut deliberately — and every rule enforced here
 * rather than trusted from the client, the same way {@link DuelService} owns
 * every duel rule.
 *
 * <p>The admin and self-service paths share every rule except who may be
 * invited and who is told about it: the admin path may invite anyone and is
 * logged to {@link AdminAuditService}; the self-service path — {@link
 * #createByUser}, {@link #inviteByUser}, {@link #startByUser} — may only
 * invite the organizer's own friends and is not audited, since it is not an
 * admin acting on somebody else's account. {@link #join} is audited by
 * neither, for the same reason: a player joining themselves is not anybody
 * acting on anybody else's account either.
 *
 * <p>A bracket is seeded once — its organizer starting it by hand, the last
 * open seat of a public one being claimed, or a {@code GLOBAL} one reaching
 * its weekly hour — and from then on advances itself:
 * {@link #onDuelFinished} is {@link DuelService}'s hook for a duel tagged as a
 * tournament match, and it is the only thing that ever moves a winner into the
 * next round.
 *
 * <p>A {@code GLOBAL} tournament has no organizer and no self-join door of its
 * own. Its guest list is the top of the ladder, invited by the system when the
 * bracket opens ({@link #inviteTopRankedSolo}, {@link #inviteTopRankedTeam}),
 * and every seat that comes back a no — refused, or left unanswered past the
 * expiry {@link #expireStaleGlobalInvites} enforces — is offered on down the
 * ladder until somebody takes it. Nobody is watching such a bracket on the
 * server's behalf, which is why refusing a seat has to refill it and why
 * {@link #finalizeOpenGlobal} — the clock, not a person and not the last
 * acceptance — is the only thing that ever starts one.
 *
 * <p>A {@code TEAM} tournament — see {@link TournamentEntity.Format} — seats a
 * pair of players where a {@code SOLO} one seats a player, and changes almost
 * nothing here. Each team's <em>primary</em> member is the id every bracket
 * mechanism in this class and in {@link TournamentBracket} goes on working
 * against unchanged: seeding, pairing, {@link #advance}, {@code findReadyFor}.
 * The teammate is carried beside it and read at exactly four points — who may
 * be invited ({@link #inviteTeam}, {@link #inviteTeamByUser}), how a seat is
 * rated for seeding ({@link #seedRatingOf}), which engine plays a round
 * ({@link #startMatch}), and who is told about it ({@link #notifyMatchReady}
 * and the DTOs it builds).
 * {@link #onTeamDuelFinished} is {@link TeamDuelService}'s hook, and reports a
 * winning team by its primary member so that {@link #advance} never has to
 * know a team was playing at all.
 */
@Service
public class TournamentService {

    private static final Set<Integer> ALLOWED_SIZES = Set.of(4, 8, 16, 32);

    /** The lobby's discovery banner never scans further back than this. */
    private static final int ACTIVE_LIMIT = 20;

    /** Big enough for a screenful, small enough that a typo cannot ask for the table. */
    private static final int MAX_BROWSE_PAGE_SIZE = 100;

    private final TournamentRepository tournaments;
    private final TournamentParticipantRepository participants;
    private final TournamentMatchRepository matches;
    private final UserRepository users;
    private final UserService userService;
    private final FriendService friends;
    private final SocketRegistry sockets;
    private final AdminAuditService audit;
    private final DuelService duels;
    private final TeamDuelService teamDuels;

    /**
     * One lock per tournament, guarding every read-modify-write that could
     * otherwise race: {@link #onDuelFinished} advancing a winner into the next
     * round's match, and {@link #join} seating the last player a public
     * tournament has room for. Two round-1 duels can finish within the same
     * instant and feed the same round-2 slot pair — and two strangers can
     * just as easily race for the very last open seat — and without this each
     * pair could both read the state before either had written to it: a lost
     * update that leaves a match missing a player, or seats one more player
     * than the bracket has room for. A plain Java lock is enough because the
     * server this runs on is meant to be a single instance — see the README —
     * the same assumption {@code PresenceService} and {@code
     * MatchmakingService} already make.
     */
    private final Map<Long, Object> tournamentLocks = new ConcurrentHashMap<>();

    public TournamentService(
            TournamentRepository tournaments,
            TournamentParticipantRepository participants,
            TournamentMatchRepository matches,
            UserRepository users,
            UserService userService,
            FriendService friends,
            SocketRegistry sockets,
            AdminAuditService audit,
            DuelService duels,
            TeamDuelService teamDuels) {
        this.tournaments = tournaments;
        this.participants = participants;
        this.matches = matches;
        this.users = users;
        this.userService = userService;
        this.friends = friends;
        this.sockets = sockets;
        this.audit = audit;
        this.duels = duels;
        this.teamDuels = teamDuels;
    }

    // ------------------------------------------------------------- admin: create, invite, start

    @Transactional
    public TournamentEntity create(long adminId, String name, int size) {
        return create(adminId, name, size, TournamentEntity.Format.SOLO);
    }

    /** The same, when the admin asks for a 2v2 bracket instead of the one-player-per-seat default. */
    @Transactional
    public TournamentEntity create(long adminId, String name, int size, TournamentEntity.Format format) {
        TournamentEntity tournament = createEntity(
                adminId, name, size, TournamentEntity.Kind.ADMIN, TournamentEntity.Visibility.PRIVATE, format);
        audit.record(adminId, AdminAuditService.TOURNAMENT_CREATE, null, tournament.getName() + " (" + size + ")");
        return tournament;
    }

    /**
     * The friends-screen "Turnir tashkil qilish" flow — otherwise identical to
     * {@link #create}, minus the audit log. Defaults to {@code PRIVATE}, the
     * same as an admin's, but lets the organizer ask for {@code PUBLIC}
     * instead so a stranger may seat themselves through {@link #join} rather
     * than waiting on an invite.
     */
    @Transactional
    public TournamentEntity createByUser(long userId, String name, int size, TournamentEntity.Visibility visibility) {
        return createByUser(userId, name, size, visibility, TournamentEntity.Format.SOLO);
    }

    /** The same, when the organizer asks for a 2v2 bracket instead of the one-player-per-seat default. */
    @Transactional
    public TournamentEntity createByUser(
            long userId,
            String name,
            int size,
            TournamentEntity.Visibility visibility,
            TournamentEntity.Format format) {
        return createEntity(userId, name, size, TournamentEntity.Kind.FRIEND, visibility, format);
    }

    /**
     * Parses the create request's {@code visibility} field — {@code "private"}
     * (the default when absent or blank) or {@code "public"} — refusing
     * anything else the same way {@code invalid_size} refuses a bad size.
     */
    public TournamentEntity.Visibility parseVisibility(String raw) {
        if (raw == null || raw.isBlank()) return TournamentEntity.Visibility.PRIVATE;
        try {
            return TournamentEntity.Visibility.valueOf(raw.strip().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw ApiException.badRequest("invalid_visibility", "Ko'rinish private yoki public bo'lishi kerak");
        }
    }

    /** The same for {@code format} — {@code "solo"} when absent or blank, or {@code "team"} for a 2v2 bracket. */
    public TournamentEntity.Format parseFormat(String raw) {
        if (raw == null || raw.isBlank()) return TournamentEntity.Format.SOLO;
        try {
            return TournamentEntity.Format.valueOf(raw.strip().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw ApiException.badRequest("invalid_format", "Format solo yoki team bo'lishi kerak");
        }
    }

    /** {@code GlobalTournamentScheduler}'s own creation path — no organizer to audit, since nobody is acting on anybody's behalf here. */
    @Transactional
    public TournamentEntity createGlobalTournament(int size, double minRating) {
        return tournaments.save(TournamentEntity.global("Global turnir", size, minRating));
    }

    /** The same for the weekly 2v2 bracket, where {@code size} counts teams — twice as many people. */
    @Transactional
    public TournamentEntity createGlobalTeamTournament(int size, double minRating) {
        return tournaments.save(TournamentEntity.globalTeam("Global 2v2 turnir", size, minRating));
    }

    private TournamentEntity createEntity(
            long creatorId,
            String name,
            int size,
            TournamentEntity.Kind kind,
            TournamentEntity.Visibility visibility,
            TournamentEntity.Format format) {
        String trimmed = name == null ? "" : name.strip();
        if (trimmed.isEmpty()) throw ApiException.badRequest("name_required", "Turnir nomini kiriting");
        if (trimmed.length() > 64) throw ApiException.badRequest("name_too_long", "Ko'pi bilan 64 ta belgi");
        if (!ALLOWED_SIZES.contains(size)) {
            throw ApiException.badRequest("invalid_size", "O'lcham 4, 8, 16 yoki 32 bo'lishi kerak");
        }
        return tournaments.save(new TournamentEntity(trimmed, size, creatorId, kind, visibility, format));
    }

    /**
     * Refuses anyone but the organizer who created this tournament — the
     * self-service path's only gate the admin path skips. A {@code GLOBAL}
     * tournament has no organizer at all, so this refuses everyone for one —
     * there is nobody it could ever let through.
     */
    private void requireOrganizer(TournamentEntity tournament, long userId) {
        if (tournament.getCreatedByAdminId() == null || tournament.getCreatedByAdminId() != userId) {
            throw ApiException.forbidden("not_organizer", "Bu turnirni faqat tashkilotchisi boshqara oladi");
        }
    }

    public TournamentEntity require(long id) {
        return tournaments.findById(id)
                .orElseThrow(() -> ApiException.notFound("tournament_not_found", "Turnir topilmadi"));
    }

    public Page<TournamentEntity> list(Pageable pageable) {
        return tournaments.findAllByOrderByIdDesc(pageable);
    }

    public List<TournamentParticipant> participantsOf(long tournamentId) {
        return participants.findByTournamentIdOrderByIdAsc(tournamentId);
    }

    /**
     * Invites a player. Re-invites one who had declined, and does nothing to
     * one who already accepted — inviting twice must not cost them their spot.
     */
    @Transactional
    public void invite(long adminId, long tournamentId, long userId) {
        TournamentEntity tournament = require(tournamentId);
        TournamentParticipant saved = inviteInternal(tournament, userId);
        if (saved == null) return;
        audit.record(adminId, AdminAuditService.TOURNAMENT_INVITE, userId, tournament.getName());
        sendInvite(tournament, saved, userId);
    }

    /**
     * {@link #invite} for a {@code TEAM} tournament, whose seats are held by
     * two. An admin may pair any two registered players — there is no
     * friendship to check, which is the only thing this does not do that
     * {@link #inviteTeamByUser} does — and each of the two still answers for
     * themselves.
     *
     * <p>Audited once per invited member: the log is read by who was acted on,
     * and this acted on both of them.
     */
    @Transactional
    public void inviteTeam(long adminId, long tournamentId, long primaryUserId, long partnerUserId) {
        TournamentEntity tournament = require(tournamentId);
        if (tournament.getFormat() != TournamentEntity.Format.TEAM) {
            throw ApiException.badRequest("not_a_team_tournament", "Bu turnirga jamoa taklif qilinmaydi");
        }
        if (primaryUserId == partnerUserId) {
            throw ApiException.badRequest("same_player", "Jamoada ikki xil o'yinchi bo'lishi kerak");
        }
        TournamentParticipant saved = inviteTeamInternal(tournament, primaryUserId, partnerUserId);
        if (saved == null) return;
        audit.record(adminId, AdminAuditService.TOURNAMENT_INVITE, primaryUserId, tournament.getName());
        audit.record(adminId, AdminAuditService.TOURNAMENT_INVITE, partnerUserId, tournament.getName());
        sendInvite(tournament, saved, primaryUserId);
        sendInvite(tournament, saved, partnerUserId);
    }

    /**
     * The friends-screen equivalent of {@link #invite}: only the tournament's
     * own organizer may call it, and only to invite one of their own friends —
     * the abuse guard this path relies on instead of an admin role. See
     * {@link FriendService#areFriends} for what "friend" means here.
     */
    @Transactional
    public void inviteByUser(long organizerId, long tournamentId, long userId) {
        TournamentEntity tournament = require(tournamentId);
        requireOrganizer(tournament, organizerId);
        if (!friends.areFriends(organizerId, userId)) {
            throw ApiException.badRequest("not_friends", "Faqat do'stlaringizni turnirga taklif qila olasiz");
        }
        TournamentParticipant saved = inviteInternal(tournament, userId);
        if (saved == null) return;
        sendInvite(tournament, saved, userId);
    }

    /**
     * {@link #inviteByUser} for a {@code TEAM} tournament, where a seat is
     * offered to two people at once rather than one. The organizer has to be a
     * friend of both — one friend cannot bring a stranger in behind them — and
     * each of the two answers the invite for themselves; the seat only counts
     * towards the bracket once both have.
     *
     * <p>{@code primaryUserId} is the member the bracket will seed, pair and
     * advance this team by; which of the two it is changes nothing a player can
     * see.
     */
    @Transactional
    public void inviteTeamByUser(long organizerId, long tournamentId, long primaryUserId, long partnerUserId) {
        TournamentEntity tournament = require(tournamentId);
        requireOrganizer(tournament, organizerId);
        if (tournament.getFormat() != TournamentEntity.Format.TEAM) {
            throw ApiException.badRequest("not_a_team_tournament", "Bu turnirga jamoa taklif qilinmaydi");
        }
        if (primaryUserId == partnerUserId) {
            throw ApiException.badRequest("same_player", "Jamoada ikki xil o'yinchi bo'lishi kerak");
        }
        if (!friends.areFriends(organizerId, primaryUserId) || !friends.areFriends(organizerId, partnerUserId)) {
            throw ApiException.badRequest("not_friends", "Faqat do'stlaringizni turnirga taklif qila olasiz");
        }
        TournamentParticipant saved = inviteTeamInternal(tournament, primaryUserId, partnerUserId);
        if (saved == null) return;
        sendInvite(tournament, saved, primaryUserId);
        sendInvite(tournament, saved, partnerUserId);
    }

    /** @return the saved invite, or null when the player had already accepted and there is nothing to (re)send. */
    private TournamentParticipant inviteInternal(TournamentEntity tournament, long userId) {
        if (tournament.getFormat() == TournamentEntity.Format.TEAM) {
            throw ApiException.badRequest("team_invite_required", "Bu turnirga yakka o'yinchi taklif qilinmaydi");
        }
        if (tournament.getStatus() != TournamentEntity.Status.OPEN) {
            throw ApiException.badRequest("tournament_not_open", "Turnir allaqachon boshlangan");
        }
        userService.require(userId);

        TournamentParticipant participant = participants.findByTournamentIdAndUserId(tournament.getId(), userId)
                .orElse(null);
        if (participant != null && participant.getStatus() == TournamentParticipant.Status.ACCEPTED) return null;
        if (participant == null) {
            participant = new TournamentParticipant(tournament.getId(), userId);
        } else {
            participant.reinvite();
        }
        return participants.save(participant);
    }

    /** {@link #inviteInternal} for a whole seat — same re-invite rules, refusing anyone already seated elsewhere in this bracket. */
    private TournamentParticipant inviteTeamInternal(
            TournamentEntity tournament, long primaryUserId, long partnerUserId) {
        if (tournament.getStatus() != TournamentEntity.Status.OPEN) {
            throw ApiException.badRequest("tournament_not_open", "Turnir allaqachon boshlangan");
        }
        userService.require(primaryUserId);
        userService.require(partnerUserId);

        TournamentParticipant seat = participants.findSeatOf(tournament.getId(), primaryUserId).orElse(null);
        TournamentParticipant partnerSeat = participants.findSeatOf(tournament.getId(), partnerUserId).orElse(null);
        if (seat == null && partnerSeat == null) {
            return participants.save(new TournamentParticipant(tournament.getId(), primaryUserId, partnerUserId));
        }

        // Whichever of the two was found already holds a seat: it has to be
        // this very pair's, or one of them is being invited into a second team.
        TournamentParticipant held = seat != null ? seat : partnerSeat;
        if (!held.isHeldBy(primaryUserId, partnerUserId)) {
            throw ApiException.badRequest("already_seated", "Bu o'yinchi turnirda allaqachon qatnashmoqda");
        }
        if (held.fullyAccepted()) return null;
        held.reinvite();
        return participants.save(held);
    }

    /** The push that tells one member of a seat there is an invite waiting for their answer. */
    private void sendInvite(TournamentEntity tournament, TournamentParticipant seat, long recipientId) {
        sockets.send(recipientId, "tournament.invite", inviteView(tournament, seat, recipientId));
    }

    // ------------------------------------------------------- global: the system's own guest list

    /**
     * Fills a fresh Global bracket's guest list: the {@code size} best-rated
     * players there are, invited the moment it opens. Nobody organizes a Global
     * tournament — {@link #requireOrganizer} refuses everyone for one — so the
     * invites go out from here rather than from a person, which is why this
     * calls {@link #inviteInternal} directly: the friends-only gate lives in
     * {@link #inviteByUser} above it, and there is no friendship to check when
     * the invitation is the ladder's.
     *
     * <p>An invite, not a seat. Each of them still answers for themselves, and
     * whoever says no — or says nothing for long enough — is replaced from
     * further down the ladder: see {@link #decline}.
     */
    @Transactional
    public void inviteTopRankedSolo(TournamentEntity tournament) {
        for (User candidate : users.topEligibleByRating(PageRequest.of(0, tournament.getSize()))) {
            TournamentParticipant saved = inviteInternal(tournament, candidate.getId());
            if (saved != null) sendInvite(tournament, saved, candidate.getId());
        }
    }

    /**
     * The same for a 2v2 bracket, which needs {@code size * 2} people arranged
     * into {@code size} seats. They are paired strongest with weakest — rank 1
     * beside the last of them, rank 2 beside the second to last — so that every
     * seat comes out about as strong as every other. Pairing 1 with 2 instead
     * would stack the whole top of the ladder onto one seat and decide the
     * bracket before a word was played.
     *
     * <p>The stronger half of each pair is its primary member, the id the
     * bracket seeds, pairs and advances the seat by; which one it is changes
     * nothing either of them can see.
     */
    @Transactional
    public void inviteTopRankedTeam(TournamentEntity tournament) {
        List<User> ranked = users.topEligibleByRating(PageRequest.of(0, tournament.getSize() * 2));
        // An odd one out in the middle has nobody to be seated with, and is
        // left uninvited rather than seated alone.
        for (int i = 0; i < ranked.size() / 2; i++) {
            long primaryUserId = ranked.get(i).getId();
            long partnerUserId = ranked.get(ranked.size() - 1 - i).getId();
            TournamentParticipant saved = inviteTeamInternal(tournament, primaryUserId, partnerUserId);
            if (saved == null) continue;
            sendInvite(tournament, saved, primaryUserId);
            sendInvite(tournament, saved, partnerUserId);
        }
    }

    /**
     * Asks the next-strongest player after a Global invite came back a no. A
     * bracket nobody organizes cannot wait for somebody to notice a hole in it,
     * so every refusal cascades: the seat is offered on down the ladder until
     * one of them says yes or the ladder runs out.
     *
     * <p>A {@code SOLO} seat is simply a new invite. A {@code TEAM} seat is
     * repaired in place — see {@link TournamentParticipant#replaceHalf} — so
     * that a teammate who already accepted keeps their acceptance and is not
     * made to answer again for somebody else's change of mind.
     *
     * <p>Callers hold this tournament's lock: two refusals landing together
     * must not be offered the same replacement.
     */
    private void backfillGlobalSeat(TournamentEntity tournament, TournamentParticipant seat, long decliningUserId) {
        if (tournament.getKind() != TournamentEntity.Kind.GLOBAL
                || tournament.getStatus() != TournamentEntity.Status.OPEN) {
            return;
        }
        Long replacementId = nextCandidateFor(tournament);
        // Nobody left to ask: this bracket has already been offered to every
        // player there is. It waits, exactly as it would have waited for the
        // refusal that has just arrived.
        if (replacementId == null) return;

        if (tournament.getFormat() == TournamentEntity.Format.TEAM) {
            seat.replaceHalf(decliningUserId, replacementId);
            sendInvite(tournament, participants.save(seat), replacementId);
        } else {
            TournamentParticipant saved = inviteInternal(tournament, replacementId);
            if (saved != null) sendInvite(tournament, saved, replacementId);
        }
    }

    /**
     * The best-rated player this bracket has not already asked, in any seat, on
     * either side of one, whatever they answered. Reading one more candidate
     * than there are people in the tournament is enough to guarantee one of
     * them is new: there cannot be more names already used than there are used
     * names.
     *
     * <p>A {@code TEAM} seat repaired in place no longer names whoever refused
     * it, so somebody who turned one pairing down may later be offered a seat
     * beside a different partner. That is a different question from the one
     * they answered, and the alternative — a row remembering a refusal — would
     * be a row holding a seat the bracket has already given away.
     */
    private Long nextCandidateFor(TournamentEntity tournament) {
        Set<Long> used = new HashSet<>();
        for (TournamentParticipant seat : participantsOf(tournament.getId())) {
            used.addAll(membersOf(seat));
        }
        for (User candidate : users.topEligibleByRating(PageRequest.of(0, used.size() + 1))) {
            if (!used.contains(candidate.getId())) return candidate.getId();
        }
        return null;
    }

    /**
     * Treats a Global invite nobody ever answered as the no it is in practice.
     * Silence is the common case — a player who has not opened the app since
     * the bracket went out is not going to decline it — and a bracket that
     * waited on one would never fill, so past {@code ttl} the seat is declined
     * on their behalf and cascaded down the ladder exactly as a tapped
     * "Hozir emas" would be.
     *
     * <p>Global only. An admin's or a friend's invite has never expired and
     * still does not: somebody is watching that bracket and can re-invite or
     * cancel it themselves.
     *
     * @return how many unanswered halves were given up on, for the sweep's log.
     */
    @Transactional
    public int expireStaleGlobalInvites(Duration ttl) {
        Instant cutoff = Instant.now().minus(ttl);
        int expired = 0;
        for (TournamentEntity tournament : tournaments.findOpenGlobal()) {
            synchronized (tournamentLocks.computeIfAbsent(tournament.getId(), id -> new Object())) {
                for (TournamentParticipant seat : participantsOf(tournament.getId())) {
                    if (!seat.getInvitedAt().isBefore(cutoff)) continue;
                    // Resolved before anything is written: a backfill moves an
                    // id out of this seat, and the member still to be looked at
                    // would no longer be found in it.
                    List<Long> silent = membersOf(seat).stream()
                            .filter(memberId -> seat.answerOf(memberId) == TournamentParticipant.Status.INVITED)
                            .toList();
                    for (long memberId : silent) {
                        seat.declineAs(memberId);
                        participants.save(seat);
                        backfillGlobalSeat(tournament, seat, memberId);
                        expired++;
                    }
                }
            }
        }
        return expired;
    }

    /**
     * The week's kickoff, and the only thing that ever starts a Global bracket.
     * It runs at its hour whether or not the bracket filled and whether or not
     * it filled early — one that was full by Tuesday waits here with the rest,
     * because a tournament everybody is invited to has to be at a time
     * everybody can plan around rather than at whatever moment the last invite
     * happened to be answered.
     *
     * <p>Which makes it the end of the collecting too: whoever has accepted by
     * now plays and whoever has not is out. That end has to exist — nobody is
     * watching for the moment a bracket is full enough, and a 32 that only ever
     * gathered eleven would otherwise sit open until the ladder itself ran out
     * of people to ask.
     *
     * <p>So the bracket shrinks to fit rather than waiting or being called off:
     * the largest of {@link #ALLOWED_SIZES} the accepted seats fill, with the
     * overflow above it trimmed weakest-first — a bracket half the size the
     * week hoped for is still a tournament, and the strongest of those who did
     * answer are the ones who get to play it. Only a week that could not raise
     * even the smallest bracket is cancelled outright.
     *
     * <p>Nothing here cascades. Every invite still outstanding is declined
     * because the window has closed, not because a seat has come free, so
     * {@link #backfillGlobalSeat} is deliberately not on this path: there is
     * nobody left who could answer in time.
     *
     * <p>And nothing here throws. A seat whose player has been deleted or
     * banned in the days since they accepted is dropped rather than allowed to
     * fail the bracket — see {@link #stillPlayable} for why this one path
     * swallows what every other one reports.
     *
     * @return the brackets this closed, started or cancelled, for the scheduler's log.
     */
    @Transactional
    public List<TournamentEntity> finalizeOpenGlobal(TournamentEntity.Format format) {
        List<TournamentEntity> finalized = new ArrayList<>();
        for (TournamentEntity tournament : tournaments.findOpenGlobal()) {
            if (tournament.getFormat() != format) continue;
            synchronized (tournamentLocks.computeIfAbsent(tournament.getId(), id -> new Object())) {
                finalized.add(finalizeInternal(tournament));
            }
        }
        return finalized;
    }

    private TournamentEntity finalizeInternal(TournamentEntity tournament) {
        for (TournamentParticipant seat : participantsOf(tournament.getId())) {
            if (declineOutstanding(seat)) participants.save(seat);
        }

        List<TournamentParticipant> answered = acceptedSeats(tournament.getId());
        Map<Long, User> byUserId = playersOf(answered);
        List<TournamentParticipant> accepted = new ArrayList<>();
        for (TournamentParticipant seat : answered) {
            if (stillPlayable(seat, byUserId)) {
                accepted.add(seat);
                continue;
            }
            declineWholeSeat(seat);
            participants.save(seat);
        }

        int size = largestBracketFor(accepted.size());
        if (size == 0) return cancelInternal(tournament);

        // Strongest first, the same order the bracket would have seeded them
        // in, so what is trimmed off the end is the weakest of the week.
        List<TournamentParticipant> ordered = accepted.stream()
                .sorted(Comparator
                        .<TournamentParticipant>comparingDouble(seat -> -seedRatingOf(seat, byUserId))
                        .thenComparing(TournamentParticipant::getUserId))
                .toList();
        for (TournamentParticipant trimmed : ordered.subList(size, ordered.size())) {
            declineWholeSeat(trimmed);
            participants.save(trimmed);
        }

        tournament.setSize(size);
        return startInternal(tournaments.save(tournament));
    }

    /** Answers "no" for every half of this seat still sitting on an invite. @return whether anything changed. */
    private static boolean declineOutstanding(TournamentParticipant seat) {
        boolean changed = false;
        for (long memberId : membersOf(seat)) {
            if (seat.answerOf(memberId) != TournamentParticipant.Status.INVITED) continue;
            seat.declineAs(memberId);
            changed = true;
        }
        return changed;
    }

    /** Takes a seat back out of a bracket it had accepted into — both halves of a team's, so the seat stops counting. */
    private static void declineWholeSeat(TournamentParticipant seat) {
        for (long memberId : membersOf(seat)) {
            seat.declineAs(memberId);
        }
    }

    /**
     * Whether the people holding this seat can still be seeded — nobody
     * deleted, nobody banned, the same thing {@link #startInternal} demands.
     * A team's seat needs both of them: one live member is not half a team, it
     * is no team at all.
     *
     * <p>Asked here so that {@link #finalizeInternal} can drop such a seat
     * quietly rather than let {@code startInternal} refuse the whole bracket
     * over it. That refusal is right everywhere else — a player, an organizer
     * or an admin is looking at the screen and can go and fix it — but the
     * Sunday kickoff runs with nobody watching, and a bracket left
     * {@code OPEN} by a thrown error would sit there blocking next week's as
     * well as never playing its own.
     */
    private static boolean stillPlayable(TournamentParticipant seat, Map<Long, User> byUserId) {
        for (long memberId : membersOf(seat)) {
            User member = byUserId.get(memberId);
            if (member == null || member.isDeleted() || member.isBanned()) return false;
        }
        return true;
    }

    /** The biggest bracket {@code accepted} seats can fill, or 0 when there are not enough for even the smallest. */
    private static int largestBracketFor(int accepted) {
        int largest = 0;
        for (int size : ALLOWED_SIZES) {
            if (size <= accepted && size > largest) largest = size;
        }
        return largest;
    }

    private Map<Long, User> playersOf(List<TournamentParticipant> seats) {
        Set<Long> memberIds = seats.stream().flatMap(seat -> membersOf(seat).stream()).collect(Collectors.toSet());
        return users.findAllById(memberIds).stream().collect(Collectors.toMap(User::getId, user -> user));
    }

    /**
     * Seeds the bracket and begins round one. Refuses unless exactly the target
     * number of players has accepted — the organizer decides when that is true
     * and this only checks it, the same division {@code DuelService.start}
     * keeps with its own callers.
     */
    @Transactional
    public TournamentEntity start(long adminId, long tournamentId) {
        TournamentEntity tournament = require(tournamentId);
        TournamentEntity saved = startInternal(tournament);
        audit.record(adminId, AdminAuditService.TOURNAMENT_START, null, tournament.getName());
        return saved;
    }

    /** The friends-screen equivalent of {@link #start} — the organizer only, no audit log. */
    @Transactional
    public TournamentEntity startByUser(long organizerId, long tournamentId) {
        TournamentEntity tournament = require(tournamentId);
        requireOrganizer(tournament, organizerId);
        return startInternal(tournament);
    }

    private TournamentEntity startInternal(TournamentEntity tournament) {
        long tournamentId = tournament.getId();
        if (tournament.getStatus() != TournamentEntity.Status.OPEN) {
            throw ApiException.conflict("tournament_already_started", "Turnir allaqachon boshlangan");
        }
        List<TournamentParticipant> accepted = acceptedSeats(tournamentId);
        if (accepted.size() != tournament.getSize()) {
            throw ApiException.badRequest(
                    "not_ready", accepted.size() + "/" + tournament.getSize() + " o'yinchi qabul qildi");
        }

        Map<Long, User> byUserId = new HashMap<>();
        for (TournamentParticipant participant : accepted) {
            for (long memberId : membersOf(participant)) {
                User user = users.findById(memberId)
                        .filter(u -> !u.isDeleted() && !u.isBanned())
                        .orElse(null);
                if (user == null) {
                    throw ApiException.badRequest(
                            "participant_unavailable",
                            "Qatnashchilardan biri endi mavjud emas — qaytadan qabul qilishni so'rang");
                }
                byUserId.put(memberId, user);
            }
        }

        // Highest rating first, ties broken by id so two equal ratings seed the
        // same way every time this runs.
        List<TournamentParticipant> ordered = accepted.stream()
                .sorted(Comparator
                        .<TournamentParticipant>comparingDouble(p -> -seedRatingOf(p, byUserId))
                        .thenComparing(TournamentParticipant::getUserId))
                .toList();
        Map<Integer, TournamentParticipant> seatBySeed = new HashMap<>();
        for (int i = 0; i < ordered.size(); i++) {
            int seed = i + 1;
            ordered.get(i).setSeed(seed);
            seatBySeed.put(seed, ordered.get(i));
        }
        participants.saveAll(ordered);

        int size = tournament.getSize();
        int totalRounds = TournamentBracket.rounds(size);
        List<TournamentMatch> created = new ArrayList<>();
        List<int[]> firstRound = TournamentBracket.firstRoundPairs(size);
        for (int slot = 0; slot < firstRound.size(); slot++) {
            int[] pair = firstRound.get(slot);
            TournamentParticipant one = seatBySeed.get(pair[0]);
            TournamentParticipant two = seatBySeed.get(pair[1]);
            TournamentMatch match = new TournamentMatch(tournamentId, 1, slot);
            match.setPlayerOneUserId(one.getUserId());
            match.setPlayerOnePartnerUserId(one.getPartnerUserId());
            match.setPlayerTwoUserId(two.getUserId());
            match.setPlayerTwoPartnerUserId(two.getPartnerUserId());
            match.setStatus(TournamentMatch.Status.READY);
            created.add(match);
        }
        for (int round = 2; round <= totalRounds; round++) {
            int matchesInRound = size >> round;
            for (int slot = 0; slot < matchesInRound; slot++) {
                created.add(new TournamentMatch(tournamentId, round, slot));
            }
        }
        matches.saveAll(created);

        tournament.setStatus(TournamentEntity.Status.IN_PROGRESS);
        tournament.setStartedAt(Instant.now());
        TournamentEntity saved = tournaments.save(tournament);

        for (TournamentMatch match : created) {
            if (match.getRound() == 1) notifyMatchReady(saved, match);
        }
        broadcastBracketUpdate(tournamentId);
        return saved;
    }

    /**
     * The seats that count towards filling a bracket. For a {@code SOLO}
     * tournament these are exactly the {@code ACCEPTED} rows; a {@code TEAM}
     * seat needs its second member's own acceptance too, so a team half of
     * which never answered is not one of the {@code size} the bracket waits
     * for.
     */
    private List<TournamentParticipant> acceptedSeats(long tournamentId) {
        return participants.findByTournamentIdAndStatus(tournamentId, TournamentParticipant.Status.ACCEPTED).stream()
                .filter(TournamentParticipant::fullyAccepted)
                .toList();
    }

    /** Everyone holding this seat: one player, or a team's two. */
    private static List<Long> membersOf(TournamentParticipant seat) {
        return seat.getPartnerUserId() == null
                ? List.of(seat.getUserId())
                : List.of(seat.getUserId(), seat.getPartnerUserId());
    }

    /**
     * What this seat is seeded on: a lone player's own rating, or a team's two
     * averaged — the same "a pair plays as the strength of its middle" the 2v2
     * rating settlement already builds its synthetic opponent from, see {@code
     * TeamMatchResultService}.
     */
    private static double seedRatingOf(TournamentParticipant seat, Map<Long, User> byUserId) {
        double own = byUserId.get(seat.getUserId()).getRating();
        if (seat.getPartnerUserId() == null) return own;
        return (own + byUserId.get(seat.getPartnerUserId()).getRating()) / 2.0;
    }

    // ------------------------------------------------------------------------ public: self-join

    /**
     * A stranger's own way into a {@code PUBLIC} tournament — nobody has to
     * invite them. Joining twice costs nothing, the same way accepting twice
     * does not in {@link #inviteInternal}.
     *
     * <p>Only a self-service bracket its organizer chose to open, these days: a
     * {@code GLOBAL} tournament is {@code PRIVATE} and never reaches the rating
     * floor below, because it invites the top of the ladder itself rather than
     * waiting to be found — see {@link #inviteTopRankedSolo}.
     *
     * <p>The whole thing runs under this tournament's lock, the same one
     * {@link #onDuelFinished} uses: two players racing for the last open slot
     * must not both see room and both get seated, which an unguarded
     * check-then-insert would allow.
     *
     * <p>Closed to a {@code TEAM} bracket, whose seats are held by two: there
     * is nobody for a stranger arriving on their own to play alongside, and
     * this is the only way into a tournament that does not name both.
     */
    @Transactional
    public TournamentEntity join(long userId, long tournamentId) {
        User user = userService.require(userId);
        synchronized (tournamentLocks.computeIfAbsent(tournamentId, id -> new Object())) {
            TournamentEntity tournament = require(tournamentId);
            if (tournament.getStatus() != TournamentEntity.Status.OPEN
                    || tournament.getVisibility() != TournamentEntity.Visibility.PUBLIC
                    || tournament.getFormat() != TournamentEntity.Format.SOLO) {
                throw ApiException.badRequest("tournament_not_joinable", "Bu turnirga o'zingiz qo'shila olmaysiz");
            }
            if (tournament.getKind() == TournamentEntity.Kind.GLOBAL && user.getRating() < tournament.getMinRating()) {
                throw ApiException.badRequest("rating_too_low", "Reytingingiz bu turnir uchun yetarli emas");
            }

            TournamentParticipant existing =
                    participants.findByTournamentIdAndUserId(tournamentId, userId).orElse(null);
            if (existing != null && existing.getStatus() == TournamentParticipant.Status.ACCEPTED) {
                return tournament;
            }
            if (existing == null) {
                participants.save(TournamentParticipant.selfJoined(tournamentId, userId));
            } else {
                existing.accept();
                participants.save(existing);
            }

            long acceptedCount = acceptedSeats(tournamentId).size();
            return acceptedCount == tournament.getSize() ? startInternal(tournament) : tournament;
        }
    }

    // ---------------------------------------------------------------------------- admin: cancel

    /**
     * Calls off a tournament that is stuck — a participant who never accepts,
     * one who never starts their ready match — with no way back from it: this
     * is deliberately cancel-only, there is no resuming a cancelled tournament.
     */
    @Transactional
    public TournamentEntity cancel(long adminId, long tournamentId) {
        TournamentEntity tournament = require(tournamentId);
        TournamentEntity saved = cancelInternal(tournament);
        audit.record(adminId, AdminAuditService.TOURNAMENT_CANCEL, null, tournament.getName());
        return saved;
    }

    /** The friends-screen equivalent of {@link #cancel} — the organizer only, no audit log. */
    @Transactional
    public TournamentEntity cancelByUser(long organizerId, long tournamentId) {
        TournamentEntity tournament = require(tournamentId);
        requireOrganizer(tournament, organizerId);
        return cancelInternal(tournament);
    }

    private TournamentEntity cancelInternal(TournamentEntity tournament) {
        if (tournament.getStatus() == TournamentEntity.Status.COMPLETED
                || tournament.getStatus() == TournamentEntity.Status.CANCELLED) {
            throw ApiException.conflict("tournament_not_active", "Turnir allaqachon tugagan yoki bekor qilingan");
        }
        tournament.setStatus(TournamentEntity.Status.CANCELLED);
        tournament.setFinishedAt(Instant.now());
        TournamentEntity saved = tournaments.save(tournament);

        Map<String, Object> payload = Map.of("tournamentId", tournament.getId(), "name", tournament.getName());
        for (TournamentParticipant participant : participantsOf(tournament.getId())) {
            for (long memberId : membersOf(participant)) {
                sockets.send(memberId, "tournament.cancelled", payload);
            }
        }
        return saved;
    }

    // ------------------------------------------------------------ participant: accept, decline

    /**
     * Accepting never starts anything, whoever is accepting and however full
     * the bracket now is. An admin's or a friend's waits for its organizer to
     * press start; a {@code GLOBAL} one waits for its hour — see
     * {@link #finalizeOpenGlobal} — because the one tournament everybody is in
     * has to kick off when it said it would and not whenever the last invite
     * happened to be answered.
     */
    @Transactional
    public void accept(long userId, long tournamentId) {
        TournamentParticipant participant = requireAnswerable(tournamentId, userId);
        participant.acceptAs(userId);
        participants.save(participant);
    }

    /**
     * "Hozir emas". On a {@code GLOBAL} bracket the seat does not simply go
     * empty: it cascades on down the ladder — see {@link #backfillGlobalSeat} —
     * because there is no organizer to notice the hole and invite somebody into
     * it. Under this tournament's lock, so two refusals landing together are
     * not handed the same replacement.
     */
    @Transactional
    public void decline(long userId, long tournamentId) {
        synchronized (tournamentLocks.computeIfAbsent(tournamentId, id -> new Object())) {
            TournamentParticipant participant = requireAnswerable(tournamentId, userId);
            participant.declineAs(userId);
            participants.save(participant);
            backfillGlobalSeat(require(tournamentId), participant, userId);
        }
    }

    /**
     * The seat this player may still answer for. In a team's seat each of the
     * two answers for themselves, so what has to be unanswered is this
     * player's own half of it rather than the seat as a whole — for a
     * {@code SOLO} seat the two are the same thing.
     */
    private TournamentParticipant requireAnswerable(long tournamentId, long userId) {
        TournamentParticipant participant = participants.findSeatOf(tournamentId, userId)
                .orElseThrow(() -> ApiException.notFound("invite_not_found", "Taklif topilmadi"));
        if (require(tournamentId).getStatus() == TournamentEntity.Status.CANCELLED) {
            throw ApiException.conflict("tournament_cancelled", "Turnir bekor qilingan");
        }
        if (participant.answerOf(userId) != TournamentParticipant.Status.INVITED) {
            throw ApiException.conflict("invite_resolved", "Taklif allaqachon hal qilingan");
        }
        return participant;
    }

    // --------------------------------------------------------- participant: start a ready match

    /**
     * The lobby's "Boshlash" button on a ready tournament match. Either player
     * may press it — both already committed to playing by accepting the
     * tournament — and whichever one does starts the duel for both, the same
     * way accepting a friend's challenge needs only the acceptor's tap. In a
     * {@code TEAM} bracket any of the four may press it, and it starts the one
     * 2v2 duel for all of them.
     */
    public void startMatch(long userId, long tournamentMatchId) {
        TournamentMatch match = matches.findById(tournamentMatchId)
                .orElseThrow(() -> ApiException.notFound("match_not_found", "Jang topilmadi"));
        if (!match.hasPlayer(userId)) {
            throw ApiException.badRequest("not_your_match", "Bu turnir jangi sizniki emas");
        }
        TournamentEntity tournament = require(match.getTournamentId());
        if (tournament.getStatus() == TournamentEntity.Status.CANCELLED) {
            sockets.sendError(userId, "tournament_cancelled", "Turnir bekor qilingan");
            return;
        }
        if (match.getStatus() != TournamentMatch.Status.READY) {
            sockets.sendError(userId, "match_not_ready", "Jang hali tayyor emas");
            return;
        }
        if (!startDuelFor(tournament, match)) {
            sockets.sendError(userId, "duel_unavailable", "Jang boshlanmadi, birozdan keyin urinib ko'ring");
            return;
        }
        match.setStatus(TournamentMatch.Status.LIVE);
        matches.save(match);
        broadcastBracketUpdate(match.getTournamentId());
    }

    /**
     * Hands this round to whichever engine plays it — the 1v1 {@link
     * DuelService} or, for a {@code TEAM} bracket, the 2v2 {@link
     * TeamDuelService}, with each slot's primary member passed first so the
     * winner comes back as an id this bracket already knows.
     *
     * @return false when the engine refused, exactly as it does for a player
     *     who is already playing or banned.
     */
    private boolean startDuelFor(TournamentEntity tournament, TournamentMatch match) {
        if (tournament.getFormat() == TournamentEntity.Format.TEAM) {
            TeamDuelSession session = teamDuels.startTournamentMatch(
                    match.getPlayerOneUserId(),
                    match.getPlayerOnePartnerUserId(),
                    match.getPlayerTwoUserId(),
                    match.getPlayerTwoPartnerUserId(),
                    match.getId());
            return session != null;
        }
        DuelSession session =
                duels.startTournamentMatch(match.getPlayerOneUserId(), match.getPlayerTwoUserId(), match.getId());
        return session != null;
    }

    // ------------------------------------------------------------------- bracket advancement

    /**
     * {@link DuelService}'s hook: a duel tagged as tournament match {@code
     * tournamentMatchId} has just settled. Records the winner and, unless this
     * was the final, fills the slot it feeds in the next round — pushing a
     * fresh {@code tournament.match_ready} the moment both of that match's
     * slots are filled.
     */
    @Transactional
    public void onDuelFinished(long tournamentMatchId, long winnerUserId, Long matchEntityId) {
        TournamentMatch match = matches.findById(tournamentMatchId).orElse(null);
        // Gone, or already recorded — the second of two racing settlements for
        // the very same match, which cannot happen but is worth refusing calmly
        // rather than corrupting the bracket if it ever did.
        if (match == null || match.getStatus() == TournamentMatch.Status.DONE) return;

        synchronized (tournamentLocks.computeIfAbsent(match.getTournamentId(), id -> new Object())) {
            match.setMatchId(matchEntityId);
            advance(match, winnerUserId);
        }
        broadcastBracketUpdate(match.getTournamentId());
    }

    /**
     * {@link TeamDuelService}'s hook, and {@link #onDuelFinished} in every
     * other respect: a 2v2 duel tagged as tournament match {@code
     * tournamentMatchId} has settled, and the team that won it is named by its
     * primary member — the only id this bracket ever knew that team by, which
     * is why {@link #advance} below needs to know nothing about teams at all.
     * The settled duel is recorded in {@code teamMatchId} rather than {@code
     * matchId}: a 2v2 result lives in its own table.
     */
    @Transactional
    public void onTeamDuelFinished(long tournamentMatchId, long winningPrimaryUserId, Long teamMatchEntityId) {
        TournamentMatch match = matches.findById(tournamentMatchId).orElse(null);
        if (match == null || match.getStatus() == TournamentMatch.Status.DONE) return;

        synchronized (tournamentLocks.computeIfAbsent(match.getTournamentId(), id -> new Object())) {
            match.setTeamMatchId(teamMatchEntityId);
            advance(match, winningPrimaryUserId);
        }
        broadcastBracketUpdate(match.getTournamentId());
    }

    private void advance(TournamentMatch match, long winnerUserId) {
        match.setWinnerUserId(winnerUserId);
        match.setStatus(TournamentMatch.Status.DONE);
        matches.save(match);

        TournamentEntity tournament = require(match.getTournamentId());
        // The tournament was called off while this duel was already live — it
        // still had to be allowed to finish for its two players, but nothing
        // about a cancelled bracket ever moves again.
        if (tournament.getStatus() == TournamentEntity.Status.CANCELLED) return;
        if (match.getRound() == tournament.rounds()) {
            tournament.setChampionUserId(winnerUserId);
            tournament.setStatus(TournamentEntity.Status.COMPLETED);
            tournament.setFinishedAt(Instant.now());
            tournaments.save(tournament);
            return;
        }

        int nextRound = match.getRound() + 1;
        int nextSlot = match.getSlot() / 2;
        TournamentMatch next = matches
                .findByTournamentIdAndRoundAndSlot(match.getTournamentId(), nextRound, nextSlot)
                .orElseThrow(() -> new IllegalStateException(
                        "Bracket slot missing: tournament " + match.getTournamentId()
                                + " round " + nextRound + " slot " + nextSlot));
        // Null throughout a SOLO bracket, so this carries a whole team forward
        // without changing anything about how one player is carried forward.
        Long winnerPartnerUserId =
                match.onSlotOne(winnerUserId) ? match.getPlayerOnePartnerUserId() : match.getPlayerTwoPartnerUserId();
        if (match.getSlot() % 2 == 0) {
            next.setPlayerOneUserId(winnerUserId);
            next.setPlayerOnePartnerUserId(winnerPartnerUserId);
        } else {
            next.setPlayerTwoUserId(winnerUserId);
            next.setPlayerTwoPartnerUserId(winnerPartnerUserId);
        }
        boolean justFilled = next.bothSlotsFilled() && next.getStatus() == TournamentMatch.Status.PENDING;
        if (justFilled) next.setStatus(TournamentMatch.Status.READY);
        matches.save(next);

        if (justFilled) notifyMatchReady(tournament, next);
    }

    // --------------------------------------------------------------------------- socket, reads

    /** Everyone this match is between: two players, or a {@code TEAM} bracket's four. */
    private static List<Long> membersOf(TournamentMatch match) {
        return Stream.of(
                        match.getPlayerOneUserId(),
                        match.getPlayerOnePartnerUserId(),
                        match.getPlayerTwoUserId(),
                        match.getPlayerTwoPartnerUserId())
                .filter(Objects::nonNull)
                .toList();
    }

    private void notifyMatchReady(TournamentEntity tournament, TournamentMatch match) {
        if (!match.bothSlotsFilled()) return;
        List<Long> members = membersOf(match);
        Map<Long, UserDto> byId = userService.allByIds(members).stream()
                .collect(Collectors.toMap(User::getId, UserDto::of));
        for (long memberId : members) {
            sockets.send(memberId, "tournament.match_ready", matchPrompt(tournament, match, memberId, byId));
        }
    }

    private TournamentMatchPromptDto matchPrompt(TournamentEntity tournament, TournamentMatch match, long viewerId) {
        Map<Long, UserDto> byId = userService.allByIds(membersOf(match)).stream()
                .collect(Collectors.toMap(User::getId, UserDto::of));
        return matchPrompt(tournament, match, viewerId, byId);
    }

    /**
     * The prompt as one of the match's players sees it: their own side's other
     * member as {@code partner}, and the other side's two as {@code opponent}
     * and {@code opponentPartner}. In a {@code SOLO} bracket both partner
     * fields resolve to null and this is the two-person prompt it always was.
     */
    private TournamentMatchPromptDto matchPrompt(
            TournamentEntity tournament, TournamentMatch match, long viewerId, Map<Long, UserDto> byId) {
        boolean onSlotOne = match.onSlotOne(viewerId);
        Long partnerId = onSlotOne
                ? otherMember(match.getPlayerOneUserId(), match.getPlayerOnePartnerUserId(), viewerId)
                : otherMember(match.getPlayerTwoUserId(), match.getPlayerTwoPartnerUserId(), viewerId);
        Long opponentId = onSlotOne ? match.getPlayerTwoUserId() : match.getPlayerOneUserId();
        Long opponentPartnerId =
                onSlotOne ? match.getPlayerTwoPartnerUserId() : match.getPlayerOnePartnerUserId();
        return new TournamentMatchPromptDto(
                match.getId(),
                tournament.getId(),
                tournament.getName(),
                match.getRound(),
                tournament.rounds(),
                dtoOf(byId, opponentId),
                tournament.getFormat().name().toLowerCase(),
                dtoOf(byId, partnerId),
                dtoOf(byId, opponentPartnerId));
    }

    /** Whichever of a slot's two members is not {@code viewerId} — null in a {@code SOLO} bracket, where there is only one. */
    private static Long otherMember(Long primaryUserId, Long partnerUserId, long viewerId) {
        return primaryUserId != null && primaryUserId == viewerId ? partnerUserId : primaryUserId;
    }

    private static UserDto dtoOf(Map<Long, UserDto> byId, Long userId) {
        return userId == null ? null : byId.get(userId);
    }

    /**
     * Tells every accepted participant that the bracket moved, so a bracket
     * screen already open updates itself instead of waiting for the player to
     * leave and come back. The frame carries only the id — the client already
     * knows how to fetch the detail behind it over REST, and a spectator who is
     * not a participant simply never gets this push and is left to reopen the
     * screen, which is the same "no push once the socket has closed" limit
     * every other realtime frame in this server has.
     */
    private void broadcastBracketUpdate(long tournamentId) {
        Map<String, Object> payload = Map.of("tournamentId", tournamentId);
        for (TournamentParticipant participant : acceptedSeats(tournamentId)) {
            for (long memberId : membersOf(participant)) {
                sockets.send(memberId, "tournament.bracket_update", payload);
            }
        }
    }

    /** The invite as {@code recipientId} — either half of a team's seat — sees it: their own answer, and whoever they would be playing alongside. */
    private TournamentInviteDto inviteView(
            TournamentEntity tournament, TournamentParticipant participant, long recipientId) {
        Long teammateId = otherMember(participant.getUserId(), participant.getPartnerUserId(), recipientId);
        UserDto teammate = teammateId == null
                ? null
                : userService.allByIds(Set.of(teammateId)).stream().findFirst().map(UserDto::of).orElse(null);
        return new TournamentInviteDto(
                tournament.getId(), tournament.getName(), tournament.getSize(),
                participant.answerOf(recipientId).name().toLowerCase(), organizerOf(tournament),
                tournament.getFormat().name().toLowerCase(), teammate,
                tournament.getKind().name().toLowerCase());
    }

    /** Null if the organizer's account has since been deleted, or if there never was one — see {@link UserService#allByIds}. */
    private UserDto organizerOf(TournamentEntity tournament) {
        if (tournament.getCreatedByAdminId() == null) return null;
        return userService.allByIds(Set.of(tournament.getCreatedByAdminId())).stream()
                .findFirst()
                .map(UserDto::of)
                .orElse(null);
    }

    /**
     * Everything a reconnecting socket owes this player: invites nobody has
     * answered yet, and matches ready to start. There is no push notification
     * for a player who was never connected to receive one — see the README's
     * "Hali yo'q" — so this is what stands in for it the moment they come back.
     */
    public void sendPendingNoticesTo(long userId) {
        for (TournamentParticipant invite : participants.findPendingInvitesFor(userId)) {
            TournamentEntity tournament = tournaments.findById(invite.getTournamentId()).orElse(null);
            if (tournament == null || tournament.getStatus() != TournamentEntity.Status.OPEN) continue;
            sockets.send(userId, "tournament.invite", inviteView(tournament, invite, userId));
        }
        for (TournamentMatch match : matches.findReadyFor(userId)) {
            TournamentEntity tournament = tournaments.findById(match.getTournamentId()).orElse(null);
            if (tournament == null) continue;
            sockets.send(userId, "tournament.match_ready", matchPrompt(tournament, match, userId));
        }
    }

    /** Every tournament this player has ever been invited to that is still open, and every match ready for them. */
    public Mine mine(long userId) {
        List<TournamentInviteDto> invites = new ArrayList<>();
        for (TournamentParticipant invite : participants.findPendingInvitesFor(userId)) {
            TournamentEntity tournament = tournaments.findById(invite.getTournamentId()).orElse(null);
            if (tournament == null || tournament.getStatus() != TournamentEntity.Status.OPEN) continue;
            invites.add(inviteView(tournament, invite, userId));
        }
        List<TournamentMatchPromptDto> ready = new ArrayList<>();
        for (TournamentMatch match : matches.findReadyFor(userId)) {
            TournamentEntity tournament = tournaments.findById(match.getTournamentId()).orElse(null);
            if (tournament == null) continue;
            ready.add(matchPrompt(tournament, match, userId));
        }
        return new Mine(invites, ready);
    }

    public record Mine(List<TournamentInviteDto> invites, List<TournamentMatchPromptDto> readyMatches) {}

    /** Discoverable by anyone signed in — the opt-in spectator entry point. Bounded to the most recent handful. */
    public List<TournamentSummaryDto> active() {
        return tournaments.findActive(PageRequest.of(0, ACTIVE_LIMIT)).stream().map(this::summaryOf).toList();
    }

    /**
     * The browse screen's discoverable list — see {@link
     * TournamentRepository#findBrowsable} for exactly which tournaments that
     * is.
     */
    public List<TournamentSummaryDto> browse(int page, int size) {
        PageRequest pageRequest = PageRequest.of(Math.max(0, page), Math.max(1, Math.min(size, MAX_BROWSE_PAGE_SIZE)));
        return tournaments.findBrowsable(pageRequest).stream().map(this::summaryOf).toList();
    }

    /** The row every write below hands back — including the accepted headcount a "12/32" reads off of. */
    public TournamentSummaryDto summaryOf(TournamentEntity tournament) {
        int acceptedCount = acceptedSeats(tournament.getId()).size();
        return new TournamentSummaryDto(
                tournament.getId(),
                tournament.getName(),
                tournament.getSize(),
                tournament.getStatus().name().toLowerCase(),
                tournament.getVisibility().name().toLowerCase(),
                tournament.getKind().name().toLowerCase(),
                acceptedCount,
                tournament.getMinRating(),
                tournament.getFormat().name().toLowerCase());
    }

    /**
     * The full bracket. Deliberately open to any signed-in player, not only
     * this tournament's participants — the bracket is meant to be watched.
     */
    public TournamentDetailDto detail(long tournamentId) {
        TournamentEntity tournament = require(tournamentId);
        List<TournamentMatch> all = matches.findByTournamentIdOrderByRoundAscSlotAsc(tournamentId);

        Set<Long> ids = new HashSet<>();
        if (tournament.getCreatedByAdminId() != null) ids.add(tournament.getCreatedByAdminId());
        for (TournamentMatch match : all) {
            ids.addAll(membersOf(match));
        }
        Map<Long, UserDto> byId =
                userService.allByIds(ids).stream().collect(Collectors.toMap(User::getId, UserDto::of));

        Map<Integer, List<TournamentDetailDto.MatchView>> byRound = new TreeMap<>();
        for (TournamentMatch match : all) {
            TournamentDetailDto.MatchView view = new TournamentDetailDto.MatchView(
                    match.getSlot(),
                    match.getId(),
                    dtoOf(byId, match.getPlayerOneUserId()),
                    dtoOf(byId, match.getPlayerTwoUserId()),
                    match.getWinnerUserId(),
                    match.getStatus().name().toLowerCase(),
                    dtoOf(byId, match.getPlayerOnePartnerUserId()),
                    dtoOf(byId, match.getPlayerTwoPartnerUserId()));
            byRound.computeIfAbsent(match.getRound(), r -> new ArrayList<>()).add(view);
        }
        List<TournamentDetailDto.RoundView> rounds = byRound.entrySet().stream()
                .map(e -> new TournamentDetailDto.RoundView(e.getKey(), e.getValue()))
                .toList();

        UserDto champion = dtoOf(byId, tournament.getChampionUserId());
        UserDto championPartner = dtoOf(byId, championPartnerIdOf(tournament, all));
        UserDto organizer = dtoOf(byId, tournament.getCreatedByAdminId());

        return new TournamentDetailDto(
                tournament.getId(),
                tournament.getName(),
                tournament.getSize(),
                tournament.getStatus().name().toLowerCase(),
                tournament.rounds(),
                rounds,
                champion,
                organizer,
                tournament.getVisibility().name().toLowerCase(),
                tournament.getKind().name().toLowerCase(),
                tournament.getMinRating(),
                tournament.getFormat().name().toLowerCase(),
                championPartner);
    }

    /**
     * The champion's teammate, read off the final rather than stored: the
     * bracket already records both members of the slot that won it, and there
     * is no second champion column that could disagree with them. Null unless
     * a {@code TEAM} tournament has been decided.
     */
    private static Long championPartnerIdOf(TournamentEntity tournament, List<TournamentMatch> all) {
        Long championUserId = tournament.getChampionUserId();
        if (championUserId == null) return null;
        for (TournamentMatch match : all) {
            if (match.getRound() != tournament.rounds()) continue;
            return match.onSlotOne(championUserId)
                    ? match.getPlayerOnePartnerUserId()
                    : match.getPlayerTwoPartnerUserId();
        }
        return null;
    }

    /**
     * Every seat and how it was answered, for the organizer's own setup screen
     * — open to any signed-in player, the same way {@link #detail} is.
     */
    public List<TournamentParticipantDto> participantViews(long tournamentId) {
        require(tournamentId);
        List<TournamentParticipant> rows = participantsOf(tournamentId);
        Map<Long, UserDto> byId = userService
                .allByIds(rows.stream().flatMap(p -> membersOf(p).stream()).collect(Collectors.toSet()))
                .stream()
                .collect(Collectors.toMap(User::getId, UserDto::of));
        return rows.stream()
                .map(p -> new TournamentParticipantDto(
                        p.getUserId(),
                        byId.get(p.getUserId()),
                        p.getStatus().name().toLowerCase(),
                        p.getSeed(),
                        p.getPartnerUserId(),
                        dtoOf(byId, p.getPartnerUserId()),
                        p.getPartnerStatus() == null ? null : p.getPartnerStatus().name().toLowerCase()))
                .toList();
    }
}
