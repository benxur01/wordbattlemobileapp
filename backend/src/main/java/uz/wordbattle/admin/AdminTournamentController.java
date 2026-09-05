package uz.wordbattle.admin;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.auth.CurrentUser;
import uz.wordbattle.tournament.TournamentDetailDto;
import uz.wordbattle.tournament.TournamentEntity;
import uz.wordbattle.tournament.TournamentParticipant;
import uz.wordbattle.tournament.TournamentService;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * Everything only an admin may do to a tournament: create it, invite specific
 * players to it (the same search-then-invite shape {@code AdminUsersScreen}
 * already uses), and start it once enough of them have accepted. Closed to
 * everyone else the same way the rest of {@code /api/admin/**} is — see
 * {@link AdminAuthFilter}.
 */
@RestController
@RequestMapping("/api/admin/tournaments")
public class AdminTournamentController {

    private static final int MAX_PAGE_SIZE = 100;

    private final TournamentService tournaments;
    private final UserRepository users;

    public AdminTournamentController(TournamentService tournaments, UserRepository users) {
        this.tournaments = tournaments;
        this.users = users;
    }

    public record CreateRequest(@NotBlank(message = "Turnir nomini kiriting") @Size(max = 64) String name, int size) {}

    public record InviteRequest(Long userId) {}

    public record TournamentRow(
            Long id, String name, int size, String status, Instant createdAt, Instant startedAt, Instant finishedAt) {
        static TournamentRow of(TournamentEntity tournament) {
            return new TournamentRow(
                    tournament.getId(),
                    tournament.getName(),
                    tournament.getSize(),
                    tournament.getStatus().name().toLowerCase(),
                    tournament.getCreatedAt(),
                    tournament.getStartedAt(),
                    tournament.getFinishedAt());
        }
    }

    public record ParticipantRow(Long userId, String label, String status, Integer seed) {}

    /** {@code bracket} is null until the tournament has been started — there is no bracket to show before then. */
    public record AdminDetail(TournamentRow tournament, List<ParticipantRow> participants, TournamentDetailDto bracket) {}

    @PostMapping
    public TournamentRow create(@CurrentUser AuthPrincipal principal, @Valid @RequestBody CreateRequest request) {
        return TournamentRow.of(tournaments.create(principal.userId(), request.name(), request.size()));
    }

    @GetMapping
    public AdminController.Paged<TournamentRow> list(
            @RequestParam(value = "page", defaultValue = "0") int page,
            @RequestParam(value = "size", defaultValue = "20") int size) {
        return AdminController.Paged.of(tournaments.list(pageOf(page, size)), TournamentRow::of);
    }

    @GetMapping("/{id}")
    public AdminDetail detail(@PathVariable("id") long id) {
        TournamentEntity tournament = tournaments.require(id);
        List<TournamentParticipant> rows = tournaments.participantsOf(id);
        Map<Long, User> byId = users
                .findAllById(rows.stream().map(TournamentParticipant::getUserId).toList())
                .stream()
                .collect(Collectors.toMap(User::getId, user -> user));
        List<ParticipantRow> participants = rows.stream()
                .map(p -> new ParticipantRow(
                        p.getUserId(),
                        nameOf(byId.get(p.getUserId()), p.getUserId()),
                        p.getStatus().name().toLowerCase(),
                        p.getSeed()))
                .toList();
        TournamentDetailDto bracket =
                tournament.getStatus() == TournamentEntity.Status.OPEN ? null : tournaments.detail(id);
        return new AdminDetail(TournamentRow.of(tournament), participants, bracket);
    }

    @PostMapping("/{id}/invite")
    public void invite(
            @CurrentUser AuthPrincipal principal, @PathVariable("id") long id, @RequestBody InviteRequest request) {
        tournaments.invite(principal.userId(), id, request.userId());
    }

    @PostMapping("/{id}/start")
    public TournamentRow start(@CurrentUser AuthPrincipal principal, @PathVariable("id") long id) {
        return TournamentRow.of(tournaments.start(principal.userId(), id));
    }

    @PostMapping("/{id}/cancel")
    public TournamentRow cancel(@CurrentUser AuthPrincipal principal, @PathVariable("id") long id) {
        return TournamentRow.of(tournaments.cancel(principal.userId(), id));
    }

    /** A nickname, a display name, or the id — whichever the row still has, as {@code AdminController} labels it. */
    private static String nameOf(User user, Long id) {
        if (user == null) return "#" + id;
        if (user.getNickname() != null) return user.getNickname();
        if (user.getDisplayName() != null) return user.getDisplayName();
        return "#" + user.getId();
    }

    private static PageRequest pageOf(int page, int size) {
        return PageRequest.of(
                Math.max(0, page), Math.max(1, Math.min(size, MAX_PAGE_SIZE)), Sort.by(Sort.Direction.DESC, "id"));
    }
}
