package uz.wordbattle.admin;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.time.LocalDate;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.auth.CurrentUser;
import uz.wordbattle.match.MatchEntity;
import uz.wordbattle.match.MatchRepository;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;

/**
 * The admin panel's API. Every route here is closed to anyone without the admin
 * role — see {@code SecurityConfig} for the rule and {@link AdminAuthFilter} for
 * where the role comes from — and every mutation leaves an audit row.
 *
 * <p>The shapes below are the panel's and nobody else's, which is why they are
 * not {@code UserDto}: this is the one place a deleted shell, a ban and the
 * admin role itself are worth rendering, and the player-facing DTO must not
 * learn to carry them.
 */
@RestController
@RequestMapping("/api/admin")
public class AdminController {

    /** Big enough for a screenful, small enough that a typo cannot ask for the table. */
    private static final int MAX_PAGE_SIZE = 100;

    private final AdminUserService admins;
    private final AdminAuditService audit;
    private final AdminMetricsService metrics;
    private final MatchRepository matches;
    private final UserRepository users;
    private final UserService userService;

    public AdminController(
            AdminUserService admins,
            AdminAuditService audit,
            AdminMetricsService metrics,
            MatchRepository matches,
            UserRepository users,
            UserService userService) {
        this.admins = admins;
        this.audit = audit;
        this.metrics = metrics;
        this.matches = matches;
        this.users = users;
        this.userService = userService;
    }

    /** One page of anything, in a shape that does not change between endpoints. */
    public record Paged<T>(List<T> items, int page, int size, long total, int totalPages) {
        static <E, T> Paged<T> of(Page<E> page, Function<E, T> mapper) {
            return new Paged<>(
                    page.getContent().stream().map(mapper).toList(),
                    page.getNumber(),
                    page.getSize(),
                    page.getTotalElements(),
                    page.getTotalPages());
        }
    }

    public record UserRow(
            Long id,
            String nickname,
            String displayName,
            String city,
            int rating,
            int battles,
            int wins,
            boolean admin,
            boolean banned,
            Instant bannedAt,
            boolean deleted,
            Instant createdAt,
            Instant lastSeenAt) {

        static UserRow of(User user) {
            return new UserRow(
                    user.getId(),
                    user.getNickname(),
                    user.getDisplayName(),
                    user.getCity(),
                    (int) Math.round(user.getRating()),
                    user.getBattles(),
                    user.getWins(),
                    user.isAdmin(),
                    user.isBanned(),
                    user.getBannedAt(),
                    user.isDeleted(),
                    user.getCreatedAt(),
                    user.getLastSeenAt());
        }
    }

    public record UserDetail(
            UserRow user,
            long globalRank,
            int winPercent,
            int longestChain,
            int wordsLearned,
            int streakDays,
            LocalDate lastPlayedOn) {}

    public record MatchRow(
            Long id,
            Long playerOneId,
            String playerOne,
            Long playerTwoId,
            String playerTwo,
            boolean botOpponent,
            Long winnerId,
            String endReason,
            int chainLength,
            Instant startedAt,
            Instant finishedAt) {}

    public record AuditEntry(
            Long id,
            Long adminUserId,
            String admin,
            String action,
            Long targetUserId,
            String target,
            String detail,
            Instant createdAt) {}

    public record BanRequest(@Size(max = 255, message = "Ko'pi bilan 255 ta belgi") String reason) {}

    public record NicknameRequest(@NotBlank String nickname) {}

    // ------------------------------------------------------------------ users

    @GetMapping("/users")
    public Paged<UserRow> users(
            @RequestParam(value = "q", required = false) String query,
            @RequestParam(value = "page", defaultValue = "0") int page,
            @RequestParam(value = "size", defaultValue = "20") int size) {
        return Paged.of(admins.search(query, pageOf(page, size, Sort.by(Sort.Direction.DESC, "id"))), UserRow::of);
    }

    @GetMapping("/users/{id}")
    public UserDetail user(@PathVariable("id") Long id) {
        User user = admins.require(id);
        return new UserDetail(
                UserRow.of(user),
                userService.rankOf(user),
                (int) Math.round(user.winRate() * 100),
                user.getLongestChain(),
                user.getWordsLearned(),
                user.getStreakDays(),
                user.getLastPlayedOn());
    }

    @PostMapping("/users/{id}/ban")
    public UserRow ban(
            @CurrentUser AuthPrincipal principal,
            @PathVariable("id") Long id,
            @Valid @RequestBody(required = false) BanRequest request) {
        return UserRow.of(admins.ban(principal.userId(), id, request == null ? null : request.reason()));
    }

    @PostMapping("/users/{id}/unban")
    public UserRow unban(@CurrentUser AuthPrincipal principal, @PathVariable("id") Long id) {
        return UserRow.of(admins.unban(principal.userId(), id));
    }

    @PutMapping("/users/{id}/nickname")
    public UserRow nickname(
            @CurrentUser AuthPrincipal principal,
            @PathVariable("id") Long id,
            @Valid @RequestBody NicknameRequest request) {
        return UserRow.of(admins.rename(principal.userId(), id, request.nickname()));
    }

    // ---------------------------------------------------------------- matches

    @GetMapping("/matches")
    public Paged<MatchRow> matches(
            @RequestParam(value = "page", defaultValue = "0") int page,
            @RequestParam(value = "size", defaultValue = "20") int size) {
        Page<MatchEntity> found = matches.findAllForAdmin(pageOf(page, size, Sort.unsorted()));

        // Both players of every row resolved in one query rather than one each,
        // as MatchController does it for the player-facing history.
        Set<Long> playerIds = new HashSet<>();
        for (MatchEntity match : found) {
            playerIds.add(match.getPlayerOneId());
            if (match.getPlayerTwoId() != null) playerIds.add(match.getPlayerTwoId());
        }
        Map<Long, String> names = namesOf(playerIds);

        return Paged.of(found, match -> new MatchRow(
                match.getId(),
                match.getPlayerOneId(),
                names.get(match.getPlayerOneId()),
                match.getPlayerTwoId(),
                match.getPlayerTwoId() == null ? null : names.get(match.getPlayerTwoId()),
                match.isBotOpponent(),
                match.getWinnerId(),
                match.getEndReason().name().toLowerCase(),
                match.getChainLength(),
                match.getStartedAt(),
                match.getFinishedAt()));
    }

    // ---------------------------------------------------------------- metrics

    @GetMapping("/metrics")
    public AdminMetricsService.Metrics metrics() {
        return metrics.snapshot();
    }

    // -------------------------------------------------------------- audit log

    @GetMapping("/audit-log")
    public Paged<AuditEntry> auditLog(
            @RequestParam(value = "page", defaultValue = "0") int page,
            @RequestParam(value = "size", defaultValue = "50") int size) {
        Page<AdminAuditLog> found = audit.recent(pageOf(page, size, Sort.unsorted()));

        Set<Long> involved = new HashSet<>();
        for (AdminAuditLog entry : found) {
            involved.add(entry.getAdminUserId());
            if (entry.getTargetUserId() != null) involved.add(entry.getTargetUserId());
        }
        Map<Long, String> names = namesOf(involved);

        return Paged.of(found, entry -> new AuditEntry(
                entry.getId(),
                entry.getAdminUserId(),
                names.get(entry.getAdminUserId()),
                entry.getAction(),
                entry.getTargetUserId(),
                entry.getTargetUserId() == null ? null : names.get(entry.getTargetUserId()),
                entry.getDetail(),
                entry.getCreatedAt()));
    }

    // --------------------------------------------------------------- helpers

    /**
     * Read straight from the repository rather than through {@code
     * UserService.allByIds}, which serves live players only: an audit row about
     * an account that has since been deleted still has to say whose it was.
     */
    private Map<Long, String> namesOf(Set<Long> ids) {
        if (ids.isEmpty()) return Map.of();
        return users.findAllById(ids).stream()
                .collect(Collectors.toMap(User::getId, AdminController::nameOf));
    }

    /** A nickname, a display name, or the id — whichever the row still has. */
    private static String nameOf(User user) {
        if (user.getNickname() != null) return user.getNickname();
        if (user.getDisplayName() != null) return user.getDisplayName();
        return "#" + user.getId();
    }

    /** Clamped like every other page size in this API: a zero would be a 500. */
    private static PageRequest pageOf(int page, int size, Sort sort) {
        return PageRequest.of(Math.max(0, page), Math.max(1, Math.min(size, MAX_PAGE_SIZE)), sort);
    }
}
