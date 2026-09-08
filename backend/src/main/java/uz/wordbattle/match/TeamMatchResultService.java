package uz.wordbattle.match;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
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
import uz.wordbattle.user.UserRepository;
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
 * <p>A player whose row has gone by the time this runs — deleted, in practice —
 * counts as one who is not there, exactly as {@code MatchResultService.playerBehind}
 * treats them in a 1v1 duel. They are rated for nothing, written nothing, and
 * left out of the synthetic opponent their side stands for; the other three
 * settle normally against a side of one. Only when neither side has anybody
 * left is there nothing to do at all.
 *
 * <p>What that costs is the {@code team_matches} row, and only in that case:
 * all four of its player columns are {@code not null} and so are all eight of
 * its rating columns, so there is no shape of it that says "three players
 * played". The three who remain still get their rating, their battle, their
 * streak and their learned words — which is the whole of what a settlement is
 * for, and which they used to lose along with it. This was a deliberate
 * tradeoff once and it was the wrong one: the throw it ended in reached the
 * catch-all in {@code TeamDuelService.recordResult}, and a settlement that
 * failed for one player failed for all four.
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
    private final UserRepository users;
    private final UserService userService;
    private final UserWordRepository userWords;
    private final TeamMatchRepository matches;
    private final TeamMatchWordRepository matchWords;
    private final RatingHistoryRepository ratingHistory;

    public TeamMatchResultService(
            AppProperties props,
            UserRepository users,
            UserService userService,
            UserWordRepository userWords,
            TeamMatchRepository matches,
            TeamMatchWordRepository matchWords,
            RatingHistoryRepository ratingHistory) {
        this.props = props;
        this.users = users;
        this.userService = userService;
        this.userWords = userWords;
        this.matches = matches;
        this.matchWords = matchWords;
        this.ratingHistory = ratingHistory;
    }

    /**
     * One transaction per finished duel, every row that is still there read,
     * changed and written back inside it — same discipline as
     * {@link MatchResultService#record}, and refused at commit the same way by
     * each row's version column if another settlement races it.
     */
    @Transactional
    public Outcome record(TeamDuelSession session, boolean teamAWon, EndReason reason) {
        Instant now = Instant.now();
        Outcome outcome = new Outcome();

        User a1 = playerBehind(session.teamA().get(0));
        User a2 = playerBehind(session.teamA().get(1));
        User b1 = playerBehind(session.teamB().get(0));
        User b2 = playerBehind(session.teamB().get(1));

        List<User> teamA = stillHere(a1, a2);
        List<User> teamB = stillHere(b1, b2);
        List<User> everyone = new ArrayList<>(teamA);
        everyone.addAll(teamB);
        // Nobody left on either side: nothing to rate, nothing to write it to.
        if (everyone.isEmpty()) return outcome;

        Duration period = props.rating().periodDuration();
        Map<Long, Double> ratingBefore = new HashMap<>();
        Map<Long, Double> deviation = new HashMap<>();
        for (User player : everyone) {
            ratingBefore.put(player.getId(), player.getRating());
            deviation.put(player.getId(), inflatedDeviation(player, now, period));
        }

        // Rated only while both sides still have somebody. The synthetic
        // opponent is built out of real players, so a side with none of them
        // left is no opponent at all — the same point at which a 1v1 duel
        // settles unrated for whoever remains.
        if (!teamA.isEmpty() && !teamB.isEmpty()) {
            // Both are built before either side is rated: each is the average
            // of the other team as it stood when the duel ended, and rating a
            // player moves the numbers the other side's average is taken from.
            Glicko2.Rating teamBAsOpponent = syntheticOpponent(teamB, deviation);
            Glicko2.Rating teamAAsOpponent = syntheticOpponent(teamA, deviation);

            for (User player : teamA) rate(player, deviation.get(player.getId()), teamBAsOpponent, teamAWon);
            for (User player : teamB) rate(player, deviation.get(player.getId()), teamAAsOpponent, !teamAWon);
            for (User player : everyone) {
                player.setRatingPeriodAt(now);
                ratingHistory.save(new RatingHistory(player.getId(), player.getRating()));
            }
        }

        for (User player : teamA) {
            outcome.put(player.getId(), result(
                    player, ratingBefore.get(player.getId()), updatePlayer(player, session, teamAWon, now)));
        }
        for (User player : teamB) {
            outcome.put(player.getId(), result(
                    player, ratingBefore.get(player.getId()), updatePlayer(player, session, !teamAWon, now)));
        }

        // Only a duel all four of whose players are still here can be written
        // down: see this class's opening for why there is no row shape for the
        // other case.
        if (everyone.size() == 4) {
            outcome.matchId = persist(
                    session,
                    teamAWon,
                    reason,
                    a1,
                    a2,
                    b1,
                    b2,
                    ratingBefore.get(a1.getId()),
                    ratingBefore.get(a2.getId()),
                    ratingBefore.get(b1.getId()),
                    ratingBefore.get(b2.getId()),
                    now);
        }
        return outcome;
    }

    /**
     * The player this row still belongs to, or null when there is nobody left
     * behind it — {@code MatchResultService.playerBehind} exactly, and see its
     * own comment for why a deleted account counts as gone and a banned one
     * does not.
     */
    private User playerBehind(long playerId) {
        return users.findById(playerId).filter(user -> !user.isDeleted()).orElse(null);
    }

    private List<User> stillHere(User one, User two) {
        List<User> present = new ArrayList<>(2);
        if (one != null) present.add(one);
        if (two != null) present.add(two);
        return present;
    }

    /**
     * The rating a side stands in as: the average of its players' ratings,
     * inflated deviations and volatilities. Only the rating and deviation are
     * ever read by {@link Glicko2#update} — see this class's opening.
     */
    private Glicko2.Rating syntheticOpponent(List<User> side, Map<Long, Double> deviation) {
        double rating = 0;
        double spread = 0;
        double volatility = 0;
        for (User player : side) {
            rating += player.getRating();
            spread += deviation.get(player.getId());
            volatility += player.getVolatility();
        }
        return new Glicko2.Rating(rating / side.size(), spread / side.size(), volatility / side.size());
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
