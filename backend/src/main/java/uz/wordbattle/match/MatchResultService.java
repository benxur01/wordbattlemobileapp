package uz.wordbattle.match;

import java.time.Instant;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
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
 * Everything that outlives a duel: ratings, stats, streaks, learned words and
 * the match record itself.
 *
 * <p>Bot duels are deliberately <em>unrated</em> — they exist so a player is
 * never stuck waiting for an opponent, and rating them would make farming the
 * ladder trivial. They still count towards streaks, stats and learned words.
 */
@Service
public class MatchResultService {

    public record PlayerResult(int delta, int ratingBefore, int ratingAfter, int newWords, int streakDays) {}

    public static class Outcome {
        private final Map<Long, PlayerResult> byPlayer = new HashMap<>();

        private Outcome() {}

        /**
         * Nothing was written, so nothing moved: every player reads back zeros.
         * The duel still has to be reported as over, and a rating change the
         * database refused is one that did not happen.
         */
        static Outcome unrecorded() {
            return new Outcome();
        }

        void put(long playerId, PlayerResult result) {
            byPlayer.put(playerId, result);
        }

        public PlayerResult forPlayer(long playerId) {
            return byPlayer.getOrDefault(playerId, new PlayerResult(0, 0, 0, 0, 0));
        }
    }

    private final UserRepository users;
    private final UserService userService;
    private final UserWordRepository userWords;
    private final MatchRepository matches;
    private final MatchWordRepository matchWords;
    private final RatingHistoryRepository ratingHistory;

    public MatchResultService(
            UserRepository users,
            UserService userService,
            UserWordRepository userWords,
            MatchRepository matches,
            MatchWordRepository matchWords,
            RatingHistoryRepository ratingHistory) {
        this.users = users;
        this.userService = userService;
        this.userWords = userWords;
        this.matches = matches;
        this.matchWords = matchWords;
        this.ratingHistory = ratingHistory;
    }

    /**
     * One transaction per finished duel. Both players' rows are read, changed
     * and written back inside it, so a settlement that overlaps another one for
     * the same player is refused at commit by the version column on {@code
     * User} — see {@code DuelService.recordResult}, which runs it again over
     * fresh values rather than letting one of the two disappear.
     */
    @Transactional
    public Outcome record(DuelSession session, long winnerId, EndReason reason) {
        Instant now = Instant.now();
        Outcome outcome = new Outcome();

        User one = users.findById(session.playerOne()).orElse(null);
        User two = session.botOpponent() ? null : users.findById(session.playerTwo()).orElse(null);
        if (one == null) return outcome;

        double oneBefore = one.getRating();
        double twoBefore = two == null ? 1200 : two.getRating();

        // ---- ratings (human duels only) ----
        if (two != null) {
            Glicko2.Rating oneRating =
                    new Glicko2.Rating(one.getRating(), one.getRatingDeviation(), one.getVolatility());
            Glicko2.Rating twoRating =
                    new Glicko2.Rating(two.getRating(), two.getRatingDeviation(), two.getVolatility());

            boolean oneWon = winnerId == one.getId();
            Glicko2.Rating oneAfter = Glicko2.update(
                    oneRating, twoRating, oneWon ? Glicko2.Outcome.WIN : Glicko2.Outcome.LOSS);
            Glicko2.Rating twoAfter = Glicko2.update(
                    twoRating, oneRating, oneWon ? Glicko2.Outcome.LOSS : Glicko2.Outcome.WIN);

            apply(one, oneAfter);
            apply(two, twoAfter);
            ratingHistory.save(new RatingHistory(one.getId(), one.getRating()));
            ratingHistory.save(new RatingHistory(two.getId(), two.getRating()));
        }

        // ---- stats, streaks, learned words ----
        int oneNewWords = updatePlayer(one, session, winnerId == one.getId(), now);
        int twoNewWords = two == null ? 0 : updatePlayer(two, session, winnerId == two.getId(), now);

        outcome.put(one.getId(), new PlayerResult(
                (int) Math.round(one.getRating() - oneBefore),
                (int) Math.round(oneBefore),
                (int) Math.round(one.getRating()),
                oneNewWords,
                one.getStreakDays()));

        if (two != null) {
            outcome.put(two.getId(), new PlayerResult(
                    (int) Math.round(two.getRating() - twoBefore),
                    (int) Math.round(twoBefore),
                    (int) Math.round(two.getRating()),
                    twoNewWords,
                    two.getStreakDays()));
        }

        persist(session, winnerId, reason, one, two, oneBefore, twoBefore, now);
        return outcome;
    }

    private void apply(User user, Glicko2.Rating rating) {
        user.setRating(rating.rating());
        user.setRatingDeviation(rating.deviation());
        user.setVolatility(rating.volatility());
    }

    private int updatePlayer(User user, DuelSession session, boolean won, Instant now) {
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

    private void persist(
            DuelSession session,
            long winnerId,
            EndReason reason,
            User one,
            User two,
            double oneBefore,
            double twoBefore,
            Instant now) {

        MatchEntity match = new MatchEntity(
                one.getId(),
                two == null ? null : two.getId(),
                session.botOpponent(),
                session.startedAt());
        match.setWinnerId(winnerId == DuelSession.BOT_ID ? null : winnerId);
        match.setEndReason(reason);
        match.setChainLength(session.chainLength());
        match.setPlayerOneRatingBefore(oneBefore);
        match.setPlayerOneRatingAfter(one.getRating());
        if (two != null) {
            match.setPlayerTwoRatingBefore(twoBefore);
            match.setPlayerTwoRatingAfter(two.getRating());
        }
        match.setFinishedAt(now);
        matches.save(match);

        List<DuelSession.ChainWord> chain = session.chain();
        for (int i = 0; i < chain.size(); i++) {
            DuelSession.ChainWord word = chain.get(i);
            Long owner = word.playerId() > 0 ? word.playerId() : null;
            matchWords.save(new MatchWord(match.getId(), owner, i, word.word(), word.spentMs()));
        }
    }
}
