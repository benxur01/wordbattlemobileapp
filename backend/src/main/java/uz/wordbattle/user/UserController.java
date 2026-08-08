package uz.wordbattle.user;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.auth.CurrentUser;
import uz.wordbattle.rating.RatingHistory;
import uz.wordbattle.rating.RatingHistoryRepository;

@RestController
@RequestMapping("/api/users")
public class UserController {

    private final UserService users;
    private final RatingHistoryRepository ratingHistory;
    private final AccountDeletionService deletion;

    public UserController(
            UserService users, RatingHistoryRepository ratingHistory, AccountDeletionService deletion) {
        this.users = users;
        this.ratingHistory = ratingHistory;
        this.deletion = deletion;
    }

    public record NicknameCheckResponse(boolean available, String reason, List<String> suggestions) {}

    public record NicknameRequest(@NotBlank String nickname) {}

    /** Bounded to the column width, so an oversized value is a 400 and not a 500. */
    public record CityRequest(@Size(max = 64, message = "Ko'pi bilan 64 ta belgi") String city) {}

    @GetMapping("/me")
    public UserDto me(@CurrentUser AuthPrincipal principal) {
        return UserDto.of(users.require(principal.userId()));
    }

    /** Drives the live "band / bo'sh" state under the onboarding input. */
    @GetMapping("/nickname/check")
    public NicknameCheckResponse check(@RequestParam("value") String value) {
        NicknamePolicy.Result result = NicknamePolicy.validate(value);
        if (result != NicknamePolicy.Result.OK) {
            return new NicknameCheckResponse(false, NicknamePolicy.messageFor(result), List.of());
        }
        if (users.nicknameTaken(value)) {
            return new NicknameCheckResponse(false, "Bu taxallus band", users.suggestions(value));
        }
        return new NicknameCheckResponse(true, null, List.of());
    }

    @PutMapping("/me/nickname")
    public UserDto setNickname(@CurrentUser AuthPrincipal principal, @Valid @RequestBody NicknameRequest request) {
        return UserDto.of(users.claimNickname(principal.userId(), request.nickname()));
    }

    @PutMapping("/me/city")
    public UserDto setCity(@CurrentUser AuthPrincipal principal, @Valid @RequestBody CityRequest request) {
        return UserDto.of(users.updateCity(principal.userId(), request.city()));
    }

    /**
     * Deletes the signed-in account. Reachable from the profile screen, which
     * the store requires of any app that lets people create an account.
     */
    @DeleteMapping("/me")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteMe(@CurrentUser AuthPrincipal principal) {
        deletion.delete(principal.userId());
    }

    @GetMapping("/me/profile")
    public ProfileDto profile(@CurrentUser AuthPrincipal principal) {
        return profileOf(users.require(principal.userId()));
    }

    @GetMapping("/{id}/profile")
    public ProfileDto profileOf(@PathVariable("id") Long id) {
        return profileOf(users.require(id));
    }

    @GetMapping("/search")
    public List<UserDto> search(
            @CurrentUser AuthPrincipal principal,
            @RequestParam("q") String query,
            @RequestParam(value = "limit", defaultValue = "20") int limit) {
        // The clamp lives in the service: a zero or negative page size reached
        // PageRequest.of and came back as a 500.
        return users.search(query, principal.userId(), limit).stream()
                .map(UserDto::of)
                .toList();
    }

    private ProfileDto profileOf(User user) {
        Instant monthAgo = Instant.now().minus(30, ChronoUnit.DAYS);
        List<RatingHistory> history =
                ratingHistory.findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(user.getId(), monthAgo);

        Instant weekAgo = Instant.now().minus(7, ChronoUnit.DAYS);
        int ratingAWeekAgo = history.stream()
                .filter(p -> p.getRecordedAt().isBefore(weekAgo))
                .reduce((first, second) -> second)
                .map(p -> (int) Math.round(p.getRating()))
                .orElse((int) Math.round(history.isEmpty() ? user.getRating() : history.get(0).getRating()));

        return new ProfileDto(
                UserDto.of(user),
                users.rankOf(user),
                user.getBattles(),
                user.getWins(),
                (int) Math.round(user.winRate() * 100),
                user.getLongestChain(),
                user.getWordsLearned(),
                user.getStreakDays(),
                (int) Math.round(user.getRating()) - ratingAWeekAgo,
                history.stream()
                        .map(p -> new ProfileDto.RatingPoint(p.getRecordedAt(), (int) Math.round(p.getRating())))
                        .toList(),
                BadgeCatalog.forUser(user));
    }
}
