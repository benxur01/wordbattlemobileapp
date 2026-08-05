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
        User user = users.require(userId);
        queue.put(userId, new Waiting(userId, user.getRating(), Instant.now()));
        sockets.send(userId, "queue.joined", Map.of("since", Instant.now().toString()));
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
            if (!sockets.isConnected(first.userId())) {
                queue.remove(first.userId());
                continue;
            }

            double band = bandFor(first);
            Waiting best = null;
            double bestGap = Double.MAX_VALUE;

            for (int j = i + 1; j < waiting.size(); j++) {
                Waiting other = waiting.get(j);
                if (!queue.containsKey(other.userId())) continue;
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
                duels.start(first.userId(), best.userId());
            }
        }
    }

    private void botFallback() {
        int limit = props.matchmaking().botFallbackSeconds();
        for (Waiting waiting : new ArrayList<>(queue.values())) {
            if (Duration.between(waiting.since(), Instant.now()).toSeconds() < limit) continue;
            if (queue.remove(waiting.userId()) == null) continue;
            if (!sockets.isConnected(waiting.userId())) continue;
            log.info("No human for {} after {}s, starting a bot duel", waiting.userId(), limit);
            duels.startAgainstBot(waiting.userId());
        }
    }

    /** Rating window in points, widening the longer someone waits. */
    private double bandFor(Waiting waiting) {
        long seconds = Duration.between(waiting.since(), Instant.now()).toSeconds();
        long steps = seconds / Math.max(1, props.matchmaking().stepSeconds());
        double band = props.matchmaking().initialBand() + steps * props.matchmaking().bandStep();
        return Math.min(band, props.matchmaking().maxBand());
    }
}
