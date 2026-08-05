package uz.wordbattle.match;

import java.time.Instant;
import java.util.List;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.auth.CurrentUser;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserService;

/** Finished duels: the list a player can scroll back through, and one replay. */
@RestController
@RequestMapping("/api/matches")
public class MatchController {

    private final MatchRepository matches;
    private final MatchWordRepository matchWords;
    private final UserService users;

    public MatchController(MatchRepository matches, MatchWordRepository matchWords, UserService users) {
        this.matches = matches;
        this.matchWords = matchWords;
        this.users = users;
    }

    public record MatchSummary(
            Long id,
            UserDto opponent,
            boolean botOpponent,
            boolean won,
            boolean rated,
            int delta,
            int ratingAfter,
            int chainLength,
            String endReason,
            Instant finishedAt) {}

    public record MatchDetail(MatchSummary summary, List<Word> chain) {
        public record Word(String word, boolean mine, int spentMs) {}
    }

    @GetMapping
    public List<MatchSummary> history(
            @CurrentUser AuthPrincipal principal,
            @RequestParam(value = "limit", defaultValue = "20") int limit) {
        return matches.findHistory(principal.userId(), PageRequest.of(0, Math.min(limit, 100))).stream()
                .map(match -> summarise(match, principal.userId()))
                .toList();
    }

    @GetMapping("/{id}")
    public MatchDetail detail(@CurrentUser AuthPrincipal principal, @PathVariable("id") Long id) {
        MatchEntity match = matches.findById(id)
                .orElseThrow(() -> ApiException.notFound("match_not_found", "Jang topilmadi"));

        Long me = principal.userId();
        if (!me.equals(match.getPlayerOneId()) && !me.equals(match.getPlayerTwoId())) {
            throw ApiException.badRequest("not_your_match", "Bu jang sizniki emas");
        }

        List<MatchDetail.Word> chain = matchWords.findByMatchIdOrderByPositionAsc(id).stream()
                .map(word -> new MatchDetail.Word(word.getWord(), me.equals(word.getUserId()), word.getSpentMs()))
                .toList();
        return new MatchDetail(summarise(match, me), chain);
    }

    private MatchSummary summarise(MatchEntity match, Long me) {
        boolean iAmPlayerOne = me.equals(match.getPlayerOneId());
        Long opponentId = iAmPlayerOne ? match.getPlayerTwoId() : match.getPlayerOneId();

        UserDto opponent = opponentId == null
                ? new UserDto(DuelSession.BOT_ID, "wordbot", "Word Bot", "W", null, 1200, 0)
                : UserDto.of(users.require(opponentId));

        double before = iAmPlayerOne ? match.getPlayerOneRatingBefore() : safe(match.getPlayerTwoRatingBefore());
        double after = iAmPlayerOne ? match.getPlayerOneRatingAfter() : safe(match.getPlayerTwoRatingAfter());

        return new MatchSummary(
                match.getId(),
                opponent,
                match.isBotOpponent(),
                me.equals(match.getWinnerId()),
                !match.isBotOpponent(),
                (int) Math.round(after - before),
                (int) Math.round(after),
                match.getChainLength(),
                match.getEndReason().name().toLowerCase(),
                match.getFinishedAt());
    }

    private double safe(Double value) {
        return value == null ? 0 : value;
    }
}
