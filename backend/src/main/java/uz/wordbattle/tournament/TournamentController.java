package uz.wordbattle.tournament;

import java.util.List;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.auth.CurrentUser;

/**
 * The participant-facing side of a tournament: discovering one exists,
 * reading its bracket, answering an invite, joining a public one outright, and
 * — since {@code TournamentService#createByUser} — organizing one of your own
 * among friends instead of waiting for an admin to run one.
 *
 * <p>{@link #detail} is deliberately open to any signed-in player rather than
 * only this tournament's participants — the bracket is meant to be watched by
 * whoever wants to look, opt-in and never forced on anyone. Only the writes
 * below it — accepting or declining an invite, joining a public tournament,
 * and the organizer-only actions at the bottom — are about one player's own
 * stake in the bracket and stay that way.
 */
@RestController
@RequestMapping("/api/tournaments")
public class TournamentController {

    private static final int DEFAULT_BROWSE_PAGE_SIZE = 20;

    private final TournamentService tournaments;

    public TournamentController(TournamentService tournaments) {
        this.tournaments = tournaments;
    }

    /** The browse screen's discoverable list — see {@code TournamentService#browse} for what it does and does not show. */
    @GetMapping
    public List<TournamentSummaryDto> browse(
            @RequestParam(value = "page", defaultValue = "0") int page,
            @RequestParam(value = "size", defaultValue = "" + DEFAULT_BROWSE_PAGE_SIZE) int size) {
        return tournaments.browse(page, size);
    }

    /** The lobby's spectator discovery card: every tournament currently being played. */
    @GetMapping("/active")
    public List<TournamentSummaryDto> active() {
        return tournaments.active();
    }

    /** The whole bracket — see the class note on who may read this. */
    @GetMapping("/{id}")
    public TournamentDetailDto detail(@PathVariable("id") long id) {
        return tournaments.detail(id);
    }

    /** Invites nobody has answered yet, and matches ready to start — the REST fallback to the live socket push. */
    @GetMapping("/mine")
    public TournamentService.Mine mine(@CurrentUser AuthPrincipal principal) {
        return tournaments.mine(principal.userId());
    }

    @PostMapping("/{id}/accept")
    public void accept(@CurrentUser AuthPrincipal principal, @PathVariable("id") long id) {
        tournaments.accept(principal.userId(), id);
    }

    @PostMapping("/{id}/decline")
    public void decline(@CurrentUser AuthPrincipal principal, @PathVariable("id") long id) {
        tournaments.decline(principal.userId(), id);
    }

    /** A stranger's own way into a public or global tournament — see {@code TournamentService#join}. */
    @PostMapping("/{id}/join")
    public TournamentSummaryDto join(@CurrentUser AuthPrincipal principal, @PathVariable("id") long id) {
        return tournaments.summaryOf(tournaments.join(principal.userId(), id));
    }

    // ----------------------------------------------------- self-service: organize among friends

    /**
     * {@code visibility} is {@code "private"} (the default, absent or blank) or
     * {@code "public"} — see {@code TournamentService#parseVisibility} — and
     * {@code format} is {@code "solo"} (the same default) or {@code "team"} for
     * a 2v2 bracket, where {@code size} counts teams rather than players.
     */
    public record CreateRequest(String name, int size, String visibility, String format) {}

    public record InviteRequest(Long userId) {}

    /** {@code userId} is the team's primary member and {@code partnerUserId} the teammate — see {@code TournamentService#inviteTeamByUser}. */
    public record InviteTeamRequest(Long userId, Long partnerUserId) {}

    /** The friends screen's "Turnir tashkil qilish" — any signed-in player, no admin role needed. */
    @PostMapping
    public TournamentSummaryDto create(@CurrentUser AuthPrincipal principal, @RequestBody CreateRequest request) {
        TournamentEntity.Visibility visibility = tournaments.parseVisibility(request.visibility());
        TournamentEntity.Format format = tournaments.parseFormat(request.format());
        TournamentEntity created = tournaments.createByUser(
                principal.userId(), request.name(), request.size(), visibility, format);
        return tournaments.summaryOf(created);
    }

    /** Every invited player and how they answered — the organizer's own setup screen. */
    @GetMapping("/{id}/participants")
    public List<TournamentParticipantDto> participants(@PathVariable("id") long id) {
        return tournaments.participantViews(id);
    }

    /** Restricted to the organizer's own friends — see {@code TournamentService#inviteByUser}. */
    @PostMapping("/{id}/invite")
    public void invite(@CurrentUser AuthPrincipal principal, @PathVariable("id") long id, @RequestBody InviteRequest request) {
        tournaments.inviteByUser(principal.userId(), id, request.userId());
    }

    /** The same for a {@code team} tournament, whose seats take two — and where the organizer must be a friend of both. */
    @PostMapping("/{id}/invite-team")
    public void inviteTeam(
            @CurrentUser AuthPrincipal principal,
            @PathVariable("id") long id,
            @RequestBody InviteTeamRequest request) {
        tournaments.inviteTeamByUser(principal.userId(), id, request.userId(), request.partnerUserId());
    }

    @PostMapping("/{id}/start")
    public TournamentSummaryDto start(@CurrentUser AuthPrincipal principal, @PathVariable("id") long id) {
        return tournaments.summaryOf(tournaments.startByUser(principal.userId(), id));
    }

    @PostMapping("/{id}/cancel")
    public TournamentSummaryDto cancel(@CurrentUser AuthPrincipal principal, @PathVariable("id") long id) {
        return tournaments.summaryOf(tournaments.cancelByUser(principal.userId(), id));
    }
}
