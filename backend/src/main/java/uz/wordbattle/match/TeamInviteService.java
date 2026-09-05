package uz.wordbattle.match;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.friend.FriendService;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.SocketRegistry;

/**
 * Teaming up for 2v2 — the friend-only "form a team" step that has to happen
 * before {@link TeamMatchmakingService} will queue anyone. Structured exactly
 * like {@link InviteService}: an in-memory invite keyed by a random id, the
 * same timeout, the same validation-at-every-step discipline, the same
 * friends-only gate. The one thing this does differently on acceptance is
 * form a {@link TeamService.Team} instead of starting a duel outright — a
 * formed team still has to be taken to {@code team.queue.join} before either
 * member plays anything.
 */
@Service
public class TeamInviteService {

    public record TeamInvite(String id, long fromUserId, long toUserId, Instant createdAt) {}

    private final Map<String, TeamInvite> invites = new ConcurrentHashMap<>();

    private final AppProperties props;
    private final SocketRegistry sockets;
    private final UserService users;
    private final FriendService friends;
    private final DuelService duels;
    private final TeamDuelService teamDuels;
    private final TeamService teams;

    public TeamInviteService(
            AppProperties props,
            SocketRegistry sockets,
            UserService users,
            FriendService friends,
            DuelService duels,
            TeamDuelService teamDuels,
            TeamService teams) {
        this.props = props;
        this.sockets = sockets;
        this.users = users;
        this.friends = friends;
        this.duels = duels;
        this.teamDuels = teamDuels;
        this.teams = teams;
    }

    public void send(long fromUserId, long toUserId) {
        if (fromUserId == toUserId) {
            sockets.sendError(fromUserId, "self_invite", "O'zingizni chaqira olmaysiz");
            return;
        }
        if (!friends.areFriends(fromUserId, toUserId)) {
            sockets.sendError(fromUserId, "not_friends", "Avval do'st bo'lish kerak");
            return;
        }
        if (busy(fromUserId)) {
            sockets.sendError(fromUserId, "already_in_duel", "Siz allaqachon jangdasiz");
            return;
        }
        if (busy(toUserId)) {
            sockets.sendError(fromUserId, "opponent_busy", "Raqib hozir jangda");
            return;
        }
        if (teams.teamOf(fromUserId).isPresent()) {
            sockets.sendError(fromUserId, "already_teamed", "Sizda allaqachon jamoa bor");
            return;
        }
        if (teams.teamOf(toUserId).isPresent()) {
            sockets.sendError(fromUserId, "opponent_teamed", "Bu o'yinchida allaqachon jamoa bor");
            return;
        }
        if (!sockets.isConnected(toUserId)) {
            sockets.sendError(fromUserId, "opponent_offline", "Raqib oflayn");
            return;
        }

        TeamInvite invite = new TeamInvite(UUID.randomUUID().toString(), fromUserId, toUserId, Instant.now());
        invites.put(invite.id(), invite);

        UserDto from = UserDto.of(users.require(fromUserId));
        UserDto to = UserDto.of(users.require(toUserId));
        int expiresIn = props.duel().inviteTimeoutSeconds();

        // Same ordering as InviteService.send, and for the same reason: the
        // sender's own "waiting for X" screen opens on team_invite.sent, and a
        // recipient who answers in the same instant must not have their
        // answer delivered before that frame was ever written.
        sockets.send(fromUserId, "team_invite.sent", Map.of(
                "inviteId", invite.id(),
                "to", to,
                "expiresInSeconds", expiresIn));
        sockets.send(toUserId, "team_invite.incoming", Map.of(
                "inviteId", invite.id(),
                "from", from,
                "expiresInSeconds", expiresIn));
    }

    /**
     * Both sides are re-checked here, not just at {@link #send} — see {@code
     * InviteService.accept} for why an invite sitting out its whole timeout
     * cannot trust what was true when it was sent.
     */
    public void accept(long userId, String inviteId) {
        TeamInvite invite = invites.get(inviteId);
        if (invite == null || invite.toUserId() != userId) {
            invites.remove(inviteId);
            sockets.sendError(userId, "invite_gone", "Chaqiruv topilmadi yoki eskirgan");
            return;
        }
        if (teams.teamOf(userId).isPresent()) {
            invites.remove(inviteId);
            sockets.sendError(userId, "already_teamed", "Sizda allaqachon jamoa bor");
            return;
        }
        if (busy(userId)) {
            invites.remove(inviteId);
            sockets.sendError(userId, "already_in_duel", "Siz allaqachon jangdasiz");
            return;
        }
        if (teams.teamOf(invite.fromUserId()).isPresent() || busy(invite.fromUserId())) {
            invites.remove(inviteId);
            sockets.sendError(userId, "opponent_busy", "Chaqiruvchi band");
            sockets.send(invite.fromUserId(), "team_invite.expired", Map.of("inviteId", inviteId));
            return;
        }
        if (!sockets.isConnected(invite.fromUserId())) {
            invites.remove(inviteId);
            sockets.sendError(userId, "opponent_offline", "Chaqiruvchi oflayn");
            return;
        }
        invites.remove(inviteId);

        TeamService.Team team = teams.form(invite.fromUserId(), userId);
        UserDto from = UserDto.of(users.require(invite.fromUserId()));
        UserDto to = UserDto.of(users.require(userId));
        sockets.send(invite.fromUserId(), "team.formed", Map.of("teamId", team.id(), "partner", to));
        sockets.send(userId, "team.formed", Map.of("teamId", team.id(), "partner", from));
    }

    public void decline(long userId, String inviteId) {
        TeamInvite invite = invites.get(inviteId);
        if (invite == null || (invite.fromUserId() != userId && invite.toUserId() != userId)) return;
        invites.remove(inviteId);
        long other = invite.fromUserId() == userId ? invite.toUserId() : invite.fromUserId();
        sockets.send(other, "team_invite.declined", Map.of("inviteId", inviteId));
    }

    /** Cancels every team invite the player is part of (used on disconnect). */
    public void cancelAllFor(long userId) {
        invites.values().removeIf(invite -> {
            if (invite.fromUserId() != userId && invite.toUserId() != userId) return false;
            long other = invite.fromUserId() == userId ? invite.toUserId() : invite.fromUserId();
            sockets.send(other, "team_invite.expired", Map.of("inviteId", invite.id()));
            return true;
        });
    }

    @Scheduled(fixedDelay = 1000)
    public void expireOldInvites() {
        Instant deadline = Instant.now().minusSeconds(props.duel().inviteTimeoutSeconds());
        invites.values().removeIf(invite -> {
            if (invite.createdAt().isAfter(deadline)) return false;
            sockets.send(invite.toUserId(), "team_invite.expired", Map.of("inviteId", invite.id()));
            sockets.send(invite.fromUserId(), "team_invite.expired", Map.of("inviteId", invite.id()));
            return true;
        });
    }

    /** Playing anything at all — a 1v1 duel or a team duel. */
    private boolean busy(long userId) {
        return duels.isPlaying(userId) || teamDuels.isPlaying(userId);
    }
}
