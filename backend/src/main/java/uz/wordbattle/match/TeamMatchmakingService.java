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
 * The 2v2 queue — structurally {@link MatchmakingService} again, keyed by
 * team instead of by lone player. Reuses that class's rating-window formula
 * outright ({@link MatchmakingService#bandAfter}) and the same {@code
 * wordbattle.matchmaking} config block, rather than inventing a parallel
 * tunable for an algorithm that is not actually changing: only what counts as
 * "one side" of a pairing is different, not how wide either side is allowed to
 * search.
 *
 * <p>There is no bot fallback here — 2v2 duels are always rated for now, and
 * matching a team of two against a single bot has no sensible shape, so a team
 * with nobody to play simply keeps searching until another team turns up.
 */
@Service
public class TeamMatchmakingService {

    private static final Logger log = LoggerFactory.getLogger(TeamMatchmakingService.class);

    private record Waiting(long teamId, long memberOne, long memberTwo, double rating, Instant since) {}

    private final Map<Long, Waiting> queue = new ConcurrentHashMap<>();

    private final AppProperties props;
    private final TeamDuelService teamDuels;
    private final DuelService duels;
    private final TeamService teams;
    private final UserService users;
    private final SocketRegistry sockets;

    public TeamMatchmakingService(
            AppProperties props,
            TeamDuelService teamDuels,
            DuelService duels,
            TeamService teams,
            UserService users,
            SocketRegistry sockets) {
        this.props = props;
        this.teamDuels = teamDuels;
        this.duels = duels;
        this.teams = teams;
        this.users = users;
        this.sockets = sockets;
    }

    public void join(long userId) {
        TeamService.Team team = teams.teamOf(userId).orElse(null);
        if (team == null) {
            sockets.sendError(userId, "no_team", "Avval jamoa tuzish kerak");
            return;
        }
        if (busy(team.memberOne()) || busy(team.memberTwo())) {
            sockets.sendError(userId, "already_in_duel", "Jamoangizdan biri allaqachon jangda");
            return;
        }
        // Re-joining preserves the wait already served, exactly as
        // MatchmakingService.join does for the same reason: restarting the
        // clock would narrow a rating window that had already widened.
        Waiting existing = queue.get(team.id());
        if (existing == null) {
            double rating = averageRatingOf(team);
            existing = new Waiting(team.id(), team.memberOne(), team.memberTwo(), rating, Instant.now());
            queue.put(team.id(), existing);
        }
        sockets.send(team.memberOne(), "team.queue.joined", Map.of("since", existing.since().toString()));
        sockets.send(team.memberTwo(), "team.queue.joined", Map.of("since", existing.since().toString()));
        pair();
    }

    public void leave(long userId) {
        TeamService.Team team = teams.teamOf(userId).orElse(null);
        if (team == null) return;
        if (queue.remove(team.id()) != null) {
            sockets.send(team.memberOne(), "team.queue.left", Map.of());
            sockets.send(team.memberTwo(), "team.queue.left", Map.of());
        }
    }

    private double averageRatingOf(TeamService.Team team) {
        User one = users.require(team.memberOne());
        User two = users.require(team.memberTwo());
        return (one.getRating() + two.getRating()) / 2.0;
    }

    @Scheduled(fixedDelay = 1000)
    public void tick() {
        pair();
    }

    /**
     * Mirrors {@code MatchmakingService.pair} exactly, widening band and all —
     * only every candidate here is a team of two, so "still eligible" means
     * both members still teamed together, still connected and not already
     * playing anything, rather than just one player.
     */
    private synchronized void pair() {
        List<Waiting> waiting = new ArrayList<>(queue.values());
        waiting.sort((a, b) -> a.since().compareTo(b.since()));

        for (int i = 0; i < waiting.size(); i++) {
            Waiting first = waiting.get(i);
            if (!queue.containsKey(first.teamId())) continue;
            if (!stillEligible(first)) {
                queue.remove(first.teamId());
                continue;
            }

            double band = bandFor(first);
            Waiting best = null;
            double bestGap = Double.MAX_VALUE;

            for (int j = i + 1; j < waiting.size(); j++) {
                Waiting other = waiting.get(j);
                if (!queue.containsKey(other.teamId())) continue;
                if (!stillEligible(other)) {
                    queue.remove(other.teamId());
                    continue;
                }
                double gap = Math.abs(first.rating() - other.rating());
                if (gap <= Math.max(band, bandFor(other)) && gap < bestGap) {
                    best = other;
                    bestGap = gap;
                }
            }

            if (best != null) {
                queue.remove(first.teamId());
                queue.remove(best.teamId());
                log.info("Paired team {} and team {} (rating gap {})", first.teamId(), best.teamId(), Math.round(bestGap));
                if (teamDuels.start(first.memberOne(), first.memberTwo(), best.memberOne(), best.memberTwo()) == null) {
                    // One of the four was registered into some other duel, or
                    // one team was found stale, between the checks above and
                    // the start — the same race MatchmakingService.pair
                    // guards against for a single player.
                    requeue(first);
                    requeue(best);
                }
            }
        }
    }

    private boolean stillEligible(Waiting waiting) {
        return teams.isCurrentTeam(waiting.memberOne(), waiting.teamId())
                && teams.isCurrentTeam(waiting.memberTwo(), waiting.teamId())
                && sockets.isConnected(waiting.memberOne())
                && sockets.isConnected(waiting.memberTwo())
                && !busy(waiting.memberOne())
                && !busy(waiting.memberTwo());
    }

    private boolean busy(long userId) {
        return duels.isPlaying(userId) || teamDuels.isPlaying(userId);
    }

    private void requeue(Waiting waiting) {
        if (!stillEligible(waiting)) return;
        queue.putIfAbsent(waiting.teamId(), waiting);
    }

    private double bandFor(Waiting waiting) {
        return MatchmakingService.bandAfter(props.matchmaking(), Duration.between(waiting.since(), Instant.now()).toSeconds());
    }
}
