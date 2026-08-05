package uz.wordbattle.user;

import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
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

    public UserController(UserService users, RatingHistoryRepository ratingHistory) {
        this.users = users;
        this.ratingHistory = ratingHistory;
    }

    public record NicknameCheckResponse(boolean available, String reason, List<String> suggestions) {}

    public record NicknameRequest(@NotBlank String nickname) {}

    public record CityRequest(String city) {}

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
    public UserDto setNickname(@CurrentUser AuthPrincipal principal, @RequestBody NicknameRequest request) {
        return UserDto.of(users.claimNickname(principal.userId(), request.nickname()));
    }

    @PutMapping("/me/city")
    public UserDto setCity(@CurrentUser AuthPrincipal principal, @RequestBody CityRequest request) {
        return UserDto.of(users.updateCity(principal.userId(), request.city()));
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
        return users.search(query, principal.userId(), Math.min(limit, 50)).stream()
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
