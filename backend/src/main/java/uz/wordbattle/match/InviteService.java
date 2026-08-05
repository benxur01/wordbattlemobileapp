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
 * Direct "Jang" challenges between friends — the invite / incoming-challenge
 * screens. An invite dies on its own after the configured timeout, which is
 * what the receiving screen counts down.
 */
@Service
public class InviteService {

    public record Invite(String id, long fromUserId, long toUserId, Instant createdAt) {}

    private final Map<String, Invite> invites = new ConcurrentHashMap<>();

    private final AppProperties props;
    private final SocketRegistry sockets;
    private final UserService users;
    private final FriendService friends;
    private final DuelService duels;

    public InviteService(
            AppProperties props,
            SocketRegistry sockets,
            UserService users,
            FriendService friends,
            DuelService duels) {
        this.props = props;
        this.sockets = sockets;
        this.users = users;
        this.friends = friends;
        this.duels = duels;
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
        if (duels.isPlaying(toUserId)) {
            sockets.sendError(fromUserId, "opponent_busy", "Raqib hozir jangda");
            return;
        }
        if (!sockets.isConnected(toUserId)) {
            sockets.sendError(fromUserId, "opponent_offline", "Raqib oflayn");
            return;
        }

        Invite invite = new Invite(UUID.randomUUID().toString(), fromUserId, toUserId, Instant.now());
        invites.put(invite.id(), invite);

        UserDto from = UserDto.of(users.require(fromUserId));
        sockets.send(toUserId, "invite.incoming", Map.of(
                "inviteId", invite.id(),
                "from", from,
                "expiresInSeconds", props.duel().inviteTimeoutSeconds()));
        sockets.send(fromUserId, "invite.sent", Map.of(
                "inviteId", invite.id(),
                "to", UserDto.of(users.require(toUserId)),
                "expiresInSeconds", props.duel().inviteTimeoutSeconds()));
    }

    public void accept(long userId, String inviteId) {
        Invite invite = invites.remove(inviteId);
        if (invite == null || invite.toUserId() != userId) {
            sockets.sendError(userId, "invite_gone", "Chaqiruv topilmadi yoki eskirgan");
            return;
        }
        if (!sockets.isConnected(invite.fromUserId())) {
            sockets.sendError(userId, "opponent_offline", "Chaqiruvchi oflayn");
            return;
        }
        duels.start(invite.fromUserId(), invite.toUserId());
    }

    public void decline(long userId, String inviteId) {
        Invite invite = invites.remove(inviteId);
        if (invite == null) return;
        long other = invite.fromUserId() == userId ? invite.toUserId() : invite.fromUserId();
        sockets.send(other, "invite.declined", Map.of("inviteId", inviteId));
    }

    /** Cancels every invite the player is part of (used on disconnect). */
    public void cancelAllFor(long userId) {
        invites.values().removeIf(invite -> {
            if (invite.fromUserId() != userId && invite.toUserId() != userId) return false;
            long other = invite.fromUserId() == userId ? invite.toUserId() : invite.fromUserId();
            sockets.send(other, "invite.expired", Map.of("inviteId", invite.id()));
            return true;
        });
    }

    @Scheduled(fixedDelay = 1000)
    public void expireOldInvites() {
        Instant deadline = Instant.now().minusSeconds(props.duel().inviteTimeoutSeconds());
        invites.values().removeIf(invite -> {
            if (invite.createdAt().isAfter(deadline)) return false;
            sockets.send(invite.toUserId(), "invite.expired", Map.of("inviteId", invite.id()));
            sockets.send(invite.fromUserId(), "invite.expired", Map.of("inviteId", invite.id()));
            return true;
        });
    }
}
