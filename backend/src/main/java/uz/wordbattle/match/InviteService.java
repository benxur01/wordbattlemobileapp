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
        if (duels.isPlaying(fromUserId)) {
            sockets.sendError(fromUserId, "already_in_duel", "Siz allaqachon jangdasiz");
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

    /**
     * Both sides are re-checked here, not just at {@link #send}: an invite sits
     * around for its whole timeout, and either player can start a duel through
     * matchmaking while it waits. Accepting without looking used to start a
     * second duel for someone already playing — and when the first one ended it
     * cleared the second one's registration, leaving that player on a duel
     * screen whose every word came back "no active duel".
     */
    public void accept(long userId, String inviteId) {
        Invite invite = invites.get(inviteId);
        if (invite == null || invite.toUserId() != userId) {
            invites.remove(inviteId);
            sockets.sendError(userId, "invite_gone", "Chaqiruv topilmadi yoki eskirgan");
            return;
        }
        if (duels.isPlaying(userId)) {
            sockets.sendError(userId, "already_in_duel", "Siz allaqachon jangdasiz");
            return;
        }
        if (duels.isPlaying(invite.fromUserId())) {
            invites.remove(inviteId);
            sockets.sendError(userId, "opponent_busy", "Chaqiruvchi boshqa jangga kirib ketdi");
            sockets.send(invite.fromUserId(), "invite.expired", Map.of("inviteId", inviteId));
            return;
        }
        if (!sockets.isConnected(invite.fromUserId())) {
            invites.remove(inviteId);
            sockets.sendError(userId, "opponent_offline", "Chaqiruvchi oflayn");
            return;
        }
        invites.remove(inviteId);
        if (duels.start(invite.fromUserId(), invite.toUserId()) == null) {
            // Refused because one of the two was registered into a duel in the
            // instant between the checks above and the start. Either could be
            // the busy one, so neither is blamed — but somebody has to be told,
            // or whoever is still free waits out a duel that is not coming.
            sockets.sendError(userId, "duel_unavailable", "Jang boshlanmadi, qaytadan urinib ko'ring");
            sockets.send(invite.fromUserId(), "invite.expired", Map.of("inviteId", inviteId));
        }
    }

    public void decline(long userId, String inviteId) {
        Invite invite = invites.get(inviteId);
        // Only the two players in an invite may cancel it.
        if (invite == null || (invite.fromUserId() != userId && invite.toUserId() != userId)) return;
        invites.remove(inviteId);
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
