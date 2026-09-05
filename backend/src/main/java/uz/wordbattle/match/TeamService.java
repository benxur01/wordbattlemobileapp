package uz.wordbattle.match;

import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import org.springframework.stereotype.Service;
import uz.wordbattle.ws.SocketRegistry;

/**
 * The registry of formed-but-not-necessarily-queued-yet 2v2 teams, shared by
 * {@link TeamInviteService} (which creates one when its invite is accepted)
 * and {@link TeamMatchmakingService} (which looks the caller's team up when
 * they ask to queue).
 *
 * <p>A formed team has no expiry of its own — nothing here ever sweeps one out
 * for age, unlike {@link InviteService}'s invites. It lives until one of three
 * things happens: either member disbands it outright ({@code team.cancel}),
 * either member disconnects ({@link #cancelAllFor}), or it is found stale —
 * one member already playing or teamed elsewhere — at the moment
 * {@link TeamMatchmakingService} actually tries to use it. That last case is
 * deliberately not policed proactively: {@code DuelService}, {@code
 * MatchmakingService} and {@code InviteService} must stay untouched by this
 * feature, so nothing hooks into them to tell a formed team the instant one of
 * its members wanders off into an unrelated 1v1 duel. {@code InviteService}'s
 * own invites live with exactly the same gap — an invite is not cancelled the
 * moment its target starts some other duel either — and is re-validated at the
 * moment it is used rather than kept eagerly correct; teams take the same
 * approach here.
 */
@Service
public class TeamService {

    /** {@code memberOne} is whoever sent the team invite; {@code memberTwo} the one who accepted it. */
    public record Team(long id, long memberOne, long memberTwo) {
        public long partnerOf(long userId) {
            return userId == memberOne ? memberTwo : memberOne;
        }
    }

    private final AtomicLong nextId = new AtomicLong(1);
    private final Map<Long, Team> teamByUser = new ConcurrentHashMap<>();
    private final SocketRegistry sockets;

    public TeamService(SocketRegistry sockets) {
        this.sockets = sockets;
    }

    /** Forms a new team for the two members, replacing whatever either was in before. */
    public synchronized Team form(long memberOne, long memberTwo) {
        Team team = new Team(nextId.getAndIncrement(), memberOne, memberTwo);
        teamByUser.put(memberOne, team);
        teamByUser.put(memberTwo, team);
        return team;
    }

    public Optional<Team> teamOf(long userId) {
        return Optional.ofNullable(teamByUser.get(userId));
    }

    /** True while {@code userId} still belongs to the exact team {@code teamId} names. */
    public boolean isCurrentTeam(long userId, long teamId) {
        Team team = teamByUser.get(userId);
        return team != null && team.id() == teamId;
    }

    /** Breaks the team up and tells the other member, if there was one. */
    public void disbandFor(long userId, String reason) {
        Team team = teamByUser.remove(userId);
        if (team == null) return;
        long other = team.partnerOf(userId);
        // Conditional: only this team's own entry, not one the other member
        // has already formed since with somebody new.
        teamByUser.remove(other, team);
        sockets.send(other, "team.disbanded", Map.of("teamId", team.id(), "reason", reason));
    }

    /** Disconnect teardown, named for what the call site is doing rather than how it does it. */
    public void cancelAllFor(long userId) {
        disbandFor(userId, "disconnected");
    }
}
