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
        private Long matchId;

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

        /**
         * The persisted {@code matches} row this duel was written as, or null
         * when nothing was recorded. A tournament match reads this to remember
         * which duel it was decided by — see {@code TournamentService}.
         */
        public Long matchId() {
            return matchId;
        }
    }

    private final AppProperties props;
    private final UserRepository users;
    private final UserService userService;
    private final UserWordRepository userWords;
    private final MatchRepository matches;
    private final MatchWordRepository matchWords;
    private final RatingHistoryRepository ratingHistory;

    public MatchResultService(
            AppProperties props,
            UserRepository users,
            UserService userService,
            UserWordRepository userWords,
            MatchRepository matches,
            MatchWordRepository matchWords,
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

        User one = playerBehind(session.playerOne());
        User two = session.botOpponent() ? null : playerBehind(session.playerTwo());

        // Whichever side is still there takes the first slot. Everything below
        // is anchored on it — the match row's player_one_id is the one column
        // of the pair that cannot be null — so leaving the slots as the duel
        // dealt them and bailing out on the first alone made the outcome depend
        // on which chair a player had sat in: an opponent whose rival deleted
        // their account kept their battle, their streak and their learned words
        // when they happened to be paired second, and lost all three along with
        // the match row itself when they were paired first. Nor is that a coin
        // toss — player one is whoever had waited longer in the queue, or the
        // one who sent the challenge — so it was every second race.
        if (one == null) {
            one = two;
            two = null;
        }
        // Nobody left on either side: a bot duel whose only human is gone, or a
        // row that has vanished from under both. There is nothing to anchor a
        // match on and nobody to record it for, which is what this guard was
        // always for — and it is still the only thing standing between the
        // lines below and a null.
        if (one == null) return outcome;

        double oneBefore = one.getRating();
        double twoBefore = two == null ? 1200 : two.getRating();

        // ---- ratings (human duels only) ----
        if (two != null) {
            // Both deviations are aged forward to today before the duel is
            // rated. Nothing else in the system ever grows one: a player who
            // stops for a season would otherwise come back exactly as well
            // known as the day they left, move barely at all themselves, and
            // hold down every opponent they meet on the way back in.
            Duration period = props.rating().periodDuration();
            double oneDeviation = Glicko2.inflateForInactivity(
                    one.getRatingDeviation(), one.getVolatility(), periodsSince(one.getRatingPeriodAt(), now, period));
            double twoDeviation = Glicko2.inflateForInactivity(
                    two.getRatingDeviation(), two.getVolatility(), periodsSince(two.getRatingPeriodAt(), now, period));

            Glicko2.Rating oneRating = new Glicko2.Rating(one.getRating(), oneDeviation, one.getVolatility());
            Glicko2.Rating twoRating = new Glicko2.Rating(two.getRating(), twoDeviation, two.getVolatility());

            boolean oneWon = winnerId == one.getId();
            Glicko2.Rating oneAfter = Glicko2.update(
                    oneRating, twoRating, oneWon ? Glicko2.Outcome.WIN : Glicko2.Outcome.LOSS);
            Glicko2.Rating twoAfter = Glicko2.update(
                    twoRating, oneRating, oneWon ? Glicko2.Outcome.LOSS : Glicko2.Outcome.WIN);

            apply(one, oneAfter);
            apply(two, twoAfter);
            // Only here, inside the human branch: this is the clock the
            // inflation above reads, and a bot duel — which settles no rating
            // whatsoever — has proved nothing that should reset it.
            one.setRatingPeriodAt(now);
            two.setRatingPeriodAt(now);
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

        outcome.matchId = persist(session, winnerId, reason, one, two, oneBefore, twoBefore, now);
        return outcome;
    }

    /**
     * The player this row still belongs to, or null when there is nobody left
     * behind it.
     *
     * <p>A deleted account keeps its row — other players' match history points
     * at it — but everything personal has been stripped off it, and {@code
     * AccountDeletionService} states as a store requirement that nothing
     * personal survives the deletion. A duel that began inside the deletion
     * window and ended after it broke exactly that: this method's plain {@code
     * findById} handed back the anonymous shell, and the settlement wrote a
     * rating, a battle, a win, a streak, a fresh {@code rating_history} point
     * and a list of learned words straight back onto it. The deletion had
     * already run and nothing was ever going to sweep them up.
     *
     * <p>So a deleted player counts as one who is not there, which is a state
     * {@link #record} already handles: nothing is read from them, nothing is
     * written to them, and the duel settles unrated for whoever is left — the
     * same treatment a bot duel gets, and for the same reason, since there is
     * no opponent left whose rating could have been at stake. Which of the two
     * slots they were in makes no difference to that, but only because {@link
     * #record} moves the surviving side into the first one before it writes
     * anything; the promise in this paragraph was false for half of all races
     * until it did.
     *
     * <p>What the survivor loses with them is the opponent's name: the match
     * row is written with no second player, so their history renders it as the
     * bot duel it now resembles rather than as the deleted account it was.
     *
     * <p>Only half resembles, and the half that does not is worth knowing
     * before reaching for a bug report. {@code persist} writes {@code
     * bot_opponent} from the session, where it is false — this was a duel
     * between two people — while {@code MatchController.summarise} reads the
     * opponent from the empty second slot and calls it "Word Bot", and derives
     * {@code rated} from that same false flag. The card therefore comes out as
     * a <em>rated</em> win or loss against the bot, with a delta of zero: a
     * combination nothing else here can produce, because real bot duels are
     * unrated by design — see this class's own opening. It is one symptom of
     * the paragraph above rather than a second fault, and it goes when that
     * one does.
     *
     * <p>The alternative is to keep pointing the row at the shell, which {@code
     * MatchController.summarise} is already written for — worth doing if this
     * ever stops being a race nobody sees, and not worth a second set of
     * read-only-versus-writable player objects through this method before then.
     *
     * <p>The window itself is closed on the other side, in {@code
     * SocketSessionEnder}; this is what holds if a duel ever gets in regardless.
     *
     * <p><b>A banned account is deliberately not treated this way</b>, and the
     * asymmetry is the point rather than an oversight — it was raised against
     * this line and settled on purpose. Banning has the same shape as deleting
     * from here: {@code AdminUserService} ends the session and waits, and a
     * settlement that outlasts the five-second wait lands after {@code
     * banned_at} is written. Four things make it the opposite decision.
     *
     * <p>Deleting <em>erases</em> rows and promises they stay erased; a late
     * settlement puts a rating-history point and a list of learned words back
     * and breaks that promise. Banning erases nothing. The row is untouched by
     * design — that is the whole difference between the two — so there is
     * nothing for a late write to resurrect.
     *
     * <p>Dropping the banned player would be paid for by the wrong person. The
     * duel settles unrated for whoever is left, and the match row loses its
     * second player, so their opponent — who has done nothing — loses the
     * rating they won and gets the "Word Bot" card described above for a duel
     * they played against a human.
     *
     * <p>It would also not be one behaviour but two. In the ordinary case the
     * settlement commits before the ban does, so the duel is rated and recorded;
     * only the rare slow settlement would come out unrated. The same admin
     * action would mean different things depending on how busy the duel pool
     * was that second.
     *
     * <p>And a ban is reversible where a deletion is not. Skipping the write
     * would leave the opponent's win recorded against a player whose own row
     * shows no such battle — two halves of one duel disagreeing for as long as
     * the account exists, which unbanning then makes visible to the player.
     *
     * <p>What a late settlement must never do is undo the ban itself, and that
     * is already impossible: {@code banned_at} and {@code token_generation} are
     * both {@code updatable = false} on the entity, so the whole-row write below
     * cannot carry their pre-ban values back over the top. {@code
     * AdminControllerTest} holds that.
     */
    private User playerBehind(long playerId) {
        return users.findById(playerId).filter(user -> !user.isDeleted()).orElse(null);
    }

    /**
     * Rating periods served since {@code lastUpdate}, fractional. Never
     * negative: a clock that has stepped backwards, or a settlement replayed
     * over a row that has already been stamped, must age nobody backwards into
     * a certainty they never earned.
     */
    private double periodsSince(Instant lastUpdate, Instant now, Duration period) {
        long periodMillis = period.toMillis();
        if (periodMillis <= 0) return 0;
        return Math.max(0, Duration.between(lastUpdate, now).toMillis() / (double) periodMillis);
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

    private Long persist(
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
        return match.getId();
    }
}
