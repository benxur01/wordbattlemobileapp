package uz.wordbattle.match;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.SocketRegistry;

/**
 * The "Raqib qidirilmoqda" queue. A waiting player starts with a narrow rating
 * window that widens every few seconds, and falls back to the bot if nobody
 * suitable turns up — so the search screen never hangs forever.
 */
@Service
public class MatchmakingService {

    private static final Logger log = LoggerFactory.getLogger(MatchmakingService.class);

    private record Waiting(long userId, double rating, Instant since) {}

    private final Map<Long, Waiting> queue = new ConcurrentHashMap<>();

    private final AppProperties props;
    private final DuelService duels;
    private final UserService users;
    private final SocketRegistry sockets;

    public MatchmakingService(AppProperties props, DuelService duels, UserService users, SocketRegistry sockets) {
        this.props = props;
        this.duels = duels;
        this.users = users;
        this.sockets = sockets;
    }

    public void join(long userId) {
        if (duels.isPlaying(userId)) {
            sockets.sendError(userId, "already_in_duel", "Siz allaqachon jangdasiz");
            return;
        }
        // Re-joining used to restart the clock, which narrowed the rating window
        // again — a client that repeats the frame would never widen its search
        // (and would hit the database once per repeat).
        Waiting existing = queue.get(userId);
        if (existing == null) {
            User user = users.require(userId);
            existing = new Waiting(userId, user.getRating(), Instant.now());
            queue.put(userId, existing);
        }
        sockets.send(userId, "queue.joined", Map.of("since", existing.since().toString()));
        // Try immediately: with someone already waiting there is no reason to
        // sit through a tick first.
        pair();
    }

    public void leave(long userId) {
        if (queue.remove(userId) != null) {
            sockets.send(userId, "queue.left", Map.of());
        }
    }

    public boolean isQueued(long userId) {
        return queue.containsKey(userId);
    }

    public int queueSize() {
        return queue.size();
    }

    @Scheduled(fixedDelay = 1000)
    public void tick() {
        pair();
        botFallback();
    }

    private synchronized void pair() {
        List<Waiting> waiting = new ArrayList<>(queue.values());
        waiting.sort((a, b) -> a.since().compareTo(b.since()));

        for (int i = 0; i < waiting.size(); i++) {
            Waiting first = waiting.get(i);
            if (!queue.containsKey(first.userId())) continue;
            if (!sockets.isConnected(first.userId()) || duels.isPlaying(first.userId())) {
                queue.remove(first.userId());
                continue;
            }

            double band = bandFor(first);
            Waiting best = null;
            double bestGap = Double.MAX_VALUE;

            for (int j = i + 1; j < waiting.size(); j++) {
                Waiting other = waiting.get(j);
                if (!queue.containsKey(other.userId())) continue;
                // The same sweep the outer loop does, because a candidate is
                // reached here first: an entry left behind by someone who
                // started a duel elsewhere would be picked as the best match,
                // duels.start would refuse it, and a genuinely free player
                // would lose a whole tick to it before the outer loop ever got
                // round to that index and cleared it.
                if (!sockets.isConnected(other.userId()) || duels.isPlaying(other.userId())) {
                    queue.remove(other.userId());
                    continue;
                }
                double gap = Math.abs(first.rating() - other.rating());
                // Either side's window is enough: the one who has waited longer
                // has already widened theirs.
                if (gap <= Math.max(band, bandFor(other)) && gap < bestGap) {
                    best = other;
                    bestGap = gap;
                }
            }

            if (best != null) {
                queue.remove(first.userId());
                queue.remove(best.userId());
                log.info("Paired {} and {} (rating gap {})", first.userId(), best.userId(), Math.round(bestGap));
                if (duels.start(first.userId(), best.userId()) == null) {
                    // An invite was accepted for one of them between the check
                    // above and the start. Dropped from the queue and given no
                    // duel, the other would watch the search screen spin with
                    // nothing left looking for them.
                    requeue(first);
                    requeue(best);
                }
            }
        }
    }

    /**
     * Back into the queue with the wait they had already served, so the rating
     * window they had widened is not narrowed again. Whoever the refusal was
     * about is playing, and belongs nowhere near the queue.
     */
    private void requeue(Waiting waiting) {
        if (duels.isPlaying(waiting.userId()) || !sockets.isConnected(waiting.userId())) return;
        queue.putIfAbsent(waiting.userId(), waiting);
    }

    private void botFallback() {
        int limit = props.matchmaking().botFallbackSeconds();
        for (Waiting waiting : new ArrayList<>(queue.values())) {
            if (Duration.between(waiting.since(), Instant.now()).toSeconds() < limit) continue;
            if (queue.remove(waiting.userId()) == null) continue;
            if (!sockets.isConnected(waiting.userId()) || duels.isPlaying(waiting.userId())) continue;
            log.info("No human for {} after {}s, starting a bot duel", waiting.userId(), limit);
            // Nothing to do if this one is refused: the only reason is a duel
            // that started underneath us, and their screen has moved on to it.
            duels.startAgainstBot(waiting.userId());
        }
    }

    /** Rating window in points, widening the longer someone waits. */
    private double bandFor(Waiting waiting) {
        return bandAfter(props.matchmaking(), Duration.between(waiting.since(), Instant.now()).toSeconds());
    }

    /**
     * The window a player who has waited {@code seconds} is searching with.
     *
     * <p>Pulled out of {@link #bandFor} and left reachable from the test
     * because the widening only means anything next to the moment the bot takes
     * over, and the two were once configured a schedule apart: a ceiling of 400
     * that took 39 seconds to reach, and a bot that arrived at 12. Two players
     * 325 apart were each given a bot rather than each other, and since bot
     * duels are unrated they had no way to close the gap that separated them.
     * {@code MatchmakingBandTest} walks this against the shipped configuration
     * so the pair cannot drift apart again unnoticed.
     */
    static double bandAfter(AppProperties.Matchmaking config, long seconds) {
        long steps = seconds / Math.max(1, config.stepSeconds());
        double band = config.initialBand() + steps * config.bandStep();
        return Math.min(band, config.maxBand());
    }
}
