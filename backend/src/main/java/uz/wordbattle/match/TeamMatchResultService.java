package uz.wordbattle.match;

import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.match.MatchEntity.EndReason;
import uz.wordbattle.rating.Glicko2;
import uz.wordbattle.rating.RatingHistory;
import uz.wordbattle.rating.RatingHistoryRepository;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserService;
import uz.wordbattle.user.UserWord;
import uz.wordbattle.user.UserWordRepository;

/**
 * Everything that outlives a 2v2 duel — the team counterpart to
 * {@link MatchResultService}, built the same way but rating four players
 * against each other instead of two.
 *
 * <p>There is no team-vs-team Glicko-2: the paper only ever rates one player
 * against one opponent. Each of the four is instead rated individually against
 * a <em>synthetic</em> opponent — a {@link Glicko2.Rating} whose rating and
 * deviation are the average of the two players on the other side, exactly the
 * numbers a real opponent of that strength would carry. Only the rating and
 * deviation are synthesized; each player's own volatility feeds their own
 * update as usual, and {@link Glicko2#update} never reads the opponent's
 * volatility at all, so the synthetic side does not need one that means
 * anything.
 *
 * <p>2v2 duels are always rated for now — there is no bot-fallback or
 * unrated-practice concept for this mode yet, unlike {@link MatchResultService}'s
 * bot duels — so unlike that class there is no unrated branch here to skip.
 *
 * <p>Unlike {@link MatchResultService}, a deleted account mid-settlement is not
 * given its own reassignment logic: with four players rather than two there is
 * no single "surviving side" to anchor the row on, and unlike a 1v1 duel a
 * team match losing one of its four rows is not a case worth the same
 * bookkeeping {@code playerBehind} exists for there. If any of the four rows is
 * gone by the time this runs, {@link #record} throws, which the caller — see
 * {@code TeamDuelService.recordResult} — already treats exactly like any other
 * settlement failure: nothing is written, every player reads back a zero delta,
 * and the duel is still reported as over.
 */
@Service
public class TeamMatchResultService {

    public record PlayerResult(int delta, int ratingBefore, int ratingAfter, int newWords, int streakDays) {}

    public static class Outcome {
        private final Map<Long, PlayerResult> byPlayer = new HashMap<>();
        private Long matchId;

        private Outcome() {}

        static Outcome unrecorded() {
            return new Outcome();
        }

        void put(long playerId, PlayerResult result) {
            byPlayer.put(playerId, result);
        }

        public PlayerResult forPlayer(long playerId) {
            return byPlayer.getOrDefault(playerId, new PlayerResult(0, 0, 0, 0, 0));
        }

        public Long matchId() {
            return matchId;
        }
    }

    private final AppProperties props;
    private final UserService userService;
    private final UserWordRepository userWords;
    private final TeamMatchRepository matches;
    private final TeamMatchWordRepository matchWords;
    private final RatingHistoryRepository ratingHistory;

    public TeamMatchResultService(
            AppProperties props,
            UserService userService,
            UserWordRepository userWords,
            TeamMatchRepository matches,
            TeamMatchWordRepository matchWords,
            RatingHistoryRepository ratingHistory) {
        this.props = props;
        this.userService = userService;
        this.userWords = userWords;
        this.matches = matches;
        this.matchWords = matchWords;
        this.ratingHistory = ratingHistory;
    }

    /**
     * One transaction per finished duel, all four rows read, changed and
     * written back inside it — same discipline as {@link MatchResultService#record},
     * and refused at commit the same way by each row's version column if
     * another settlement races it.
     */
    @Transactional
    public Outcome record(TeamDuelSession session, boolean teamAWon, EndReason reason) {
        Instant now = Instant.now();
        Outcome outcome = new Outcome();

        List<Long> teamA = session.teamA();
        List<Long> teamB = session.teamB();
        User a1 = requireLive(teamA.get(0));
        User a2 = requireLive(teamA.get(1));
        User b1 = requireLive(teamB.get(0));
        User b2 = requireLive(teamB.get(1));

        double a1Before = a1.getRating();
        double a2Before = a2.getRating();
        double b1Before = b1.getRating();
        double b2Before = b2.getRating();

        Duration period = props.rating().periodDuration();
        double a1Deviation = inflatedDeviation(a1, now, period);
        double a2Deviation = inflatedDeviation(a2, now, period);
        double b1Deviation = inflatedDeviation(b1, now, period);
        double b2Deviation = inflatedDeviation(b2, now, period);

        // The synthetic opponent each side is rated against: the average
        // rating and deviation of the two real players on the other team.
        double teamARating = (a1.getRating() + a2.getRating()) / 2.0;
        double teamADeviation = (a1Deviation + a2Deviation) / 2.0;
        double teamBRating = (b1.getRating() + b2.getRating()) / 2.0;
        double teamBDeviation = (b1Deviation + b2Deviation) / 2.0;
        double teamAVolatility = (a1.getVolatility() + a2.getVolatility()) / 2.0;
        double teamBVolatility = (b1.getVolatility() + b2.getVolatility()) / 2.0;

        Glicko2.Rating teamBAsOpponent = new Glicko2.Rating(teamBRating, teamBDeviation, teamBVolatility);
        Glicko2.Rating teamAAsOpponent = new Glicko2.Rating(teamARating, teamADeviation, teamAVolatility);

        rate(a1, a1Deviation, teamBAsOpponent, teamAWon);
        rate(a2, a2Deviation, teamBAsOpponent, teamAWon);
        rate(b1, b1Deviation, teamAAsOpponent, !teamAWon);
        rate(b2, b2Deviation, teamAAsOpponent, !teamAWon);

        a1.setRatingPeriodAt(now);
        a2.setRatingPeriodAt(now);
        b1.setRatingPeriodAt(now);
        b2.setRatingPeriodAt(now);
        ratingHistory.save(new RatingHistory(a1.getId(), a1.getRating()));
        ratingHistory.save(new RatingHistory(a2.getId(), a2.getRating()));
        ratingHistory.save(new RatingHistory(b1.getId(), b1.getRating()));
        ratingHistory.save(new RatingHistory(b2.getId(), b2.getRating()));

        int a1NewWords = updatePlayer(a1, session, teamAWon, now);
        int a2NewWords = updatePlayer(a2, session, teamAWon, now);
        int b1NewWords = updatePlayer(b1, session, !teamAWon, now);
        int b2NewWords = updatePlayer(b2, session, !teamAWon, now);

        outcome.put(a1.getId(), result(a1, a1Before, a1NewWords));
        outcome.put(a2.getId(), result(a2, a2Before, a2NewWords));
        outcome.put(b1.getId(), result(b1, b1Before, b1NewWords));
        outcome.put(b2.getId(), result(b2, b2Before, b2NewWords));

        outcome.matchId = persist(
                session, teamAWon, reason, a1, a2, b1, b2, a1Before, a2Before, b1Before, b2Before, now);
        return outcome;
    }

    /** A live player's row, the same "gone means gone" rule {@code UserService.require} enforces. */
    private User requireLive(long playerId) {
        return userService.require(playerId);
    }

    private double inflatedDeviation(User user, Instant now, Duration period) {
        return Glicko2.inflateForInactivity(
                user.getRatingDeviation(), user.getVolatility(), periodsSince(user.getRatingPeriodAt(), now, period));
    }

    /** Same fractional accounting {@link MatchResultService} uses for the same clock. */
    private double periodsSince(Instant lastUpdate, Instant now, Duration period) {
        long periodMillis = period.toMillis();
        if (periodMillis <= 0) return 0;
        return Math.max(0, Duration.between(lastUpdate, now).toMillis() / (double) periodMillis);
    }

    private void rate(User user, double inflatedDeviation, Glicko2.Rating opponent, boolean won) {
        Glicko2.Rating own = new Glicko2.Rating(user.getRating(), inflatedDeviation, user.getVolatility());
        Glicko2.Rating after = Glicko2.update(own, opponent, won ? Glicko2.Outcome.WIN : Glicko2.Outcome.LOSS);
        user.setRating(after.rating());
        user.setRatingDeviation(after.deviation());
        user.setVolatility(after.volatility());
    }

    private PlayerResult result(User user, double before, int newWords) {
        return new PlayerResult(
                (int) Math.round(user.getRating() - before),
                (int) Math.round(before),
                (int) Math.round(user.getRating()),
                newWords,
                user.getStreakDays());
    }

    private int updatePlayer(User user, TeamDuelSession session, boolean won, Instant now) {
        user.setBattles(user.getBattles() + 1);
        if (won) user.setWins(user.getWins() + 1);
        user.setLongestChain(Math.max(user.getLongestChain(), session.wordsBy(user.getId())));
        userService.touchStreak(user, now);

        Set<String> played = new HashSet<>();
        for (DuelSession.ChainWord word : session.chain()) {
            if (word.playerId() == user.getId()) played.add(word.word());
        }
        if (played.isEmpty()) return 0;

        Set<String> known = new HashSet<>(userWords.findKnown(user.getId(), played));
        int learned = 0;
        for (String word : played) {
            if (!known.contains(word)) {
                userWords.save(new UserWord(user.getId(), word));
                learned++;
            }
        }
        user.setWordsLearned(user.getWordsLearned() + learned);
        return learned;
    }

    private Long persist(
            TeamDuelSession session,
            boolean teamAWon,
            EndReason reason,
            User a1,
            User a2,
            User b1,
            User b2,
            double a1Before,
            double a2Before,
            double b1Before,
            double b2Before,
            Instant now) {

        TeamMatchEntity match = new TeamMatchEntity(
                a1.getId(), a2.getId(), b1.getId(), b2.getId(), session.startedAt());
        match.setTeamAWon(teamAWon);
        match.setEndReason(reason);
        match.setChainLength(session.chainLength());
        match.setTeamAMemberOneRatingBefore(a1Before);
        match.setTeamAMemberOneRatingAfter(a1.getRating());
        match.setTeamAMemberTwoRatingBefore(a2Before);
        match.setTeamAMemberTwoRatingAfter(a2.getRating());
        match.setTeamBMemberOneRatingBefore(b1Before);
        match.setTeamBMemberOneRatingAfter(b1.getRating());
        match.setTeamBMemberTwoRatingBefore(b2Before);
        match.setTeamBMemberTwoRatingAfter(b2.getRating());
        match.setFinishedAt(now);
        matches.save(match);

        List<DuelSession.ChainWord> chain = session.chain();
        for (int i = 0; i < chain.size(); i++) {
            DuelSession.ChainWord word = chain.get(i);
            Long owner = word.playerId() > 0 ? word.playerId() : null;
            matchWords.save(new TeamMatchWord(match.getId(), owner, i, word.word(), word.spentMs()));
        }
        return match.getId();
    }
}
