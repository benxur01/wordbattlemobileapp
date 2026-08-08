package uz.wordbattle.match;

import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.auth.CurrentUser;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.user.User;
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
        List<MatchEntity> history =
                matches.findHistory(principal.userId(), PageRequest.of(0, Math.max(1, Math.min(limit, 100))));
        // Opponents resolved in one query instead of one per row.
        Set<Long> opponentIds = new HashSet<>();
        for (MatchEntity match : history) {
            Long opponent = principal.userId().equals(match.getPlayerOneId())
                    ? match.getPlayerTwoId()
                    : match.getPlayerOneId();
            if (opponent != null) opponentIds.add(opponent);
        }
        Map<Long, UserDto> opponents = users.allByIds(opponentIds).stream()
                .collect(Collectors.toMap(User::getId, UserDto::of));

        return history.stream()
                .map(match -> summarise(match, principal.userId(), opponents))
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
        Long opponentId = me.equals(match.getPlayerOneId()) ? match.getPlayerTwoId() : match.getPlayerOneId();
        Map<Long, UserDto> opponent = opponentId == null
                ? Map.of()
                : users.allByIds(Set.of(opponentId)).stream().collect(Collectors.toMap(User::getId, UserDto::of));
        return new MatchDetail(summarise(match, me, opponent), chain);
    }

    /** {@code known} lets the list endpoint pass opponents it already fetched. */
    private MatchSummary summarise(MatchEntity match, Long me, Map<Long, UserDto> known) {
        boolean iAmPlayerOne = me.equals(match.getPlayerOneId());
        Long opponentId = iAmPlayerOne ? match.getPlayerTwoId() : match.getPlayerOneId();

        // A deleted opponent still has to render: the duel happened, and this
        // player's own history is not theirs to erase.
        UserDto opponent = opponentId == null
                ? new UserDto(DuelSession.BOT_ID, "wordbot", "Word Bot", "W", null, 1200, 0)
                : known.getOrDefault(
                        opponentId, new UserDto(opponentId, null, "O'chirilgan akkaunt", "?", null, 1200, 0));

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
