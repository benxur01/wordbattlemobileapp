package uz.wordbattle.friend;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Service;

/**
 * Who is connected right now, and who is mid-duel. Backed by the live WebSocket
 * sessions of a single instance; running more than one node means moving this
 * to Redis (see README).
 *
 * <p>Being online is not stored here — it is asked of the socket layer, which
 * is the only thing that actually knows. It used to be a set of its own, added
 * to and taken from at the two ends of the socket handler, and it only stayed
 * true for as long as nothing else ever closed a socket. Something else does:
 * deleting an account closes the player's socket through the registry, which
 * drops the map entry itself, so the close callback that followed found no
 * session under that id and read it as a socket that had already been replaced
 * — the one branch that returns before presence is touched. The player was
 * left online with no socket and no account, and the lobby's counter never came
 * back down for the rest of the server's life. Derived from the registry, there
 * is no second copy left to fall out of step.
 *
 * <p>The duel flag stays a set of its own, because it has no such second door.
 * {@code DuelService} writes it on the same lines it writes its own player-to-
 * duel map — under the same lock when a duel starts, and conditionally on the
 * entry still being that duel's when one ends — and nothing outside that class
 * frees a player from a duel.
 */
@Service
public class PresenceService {

    /**
     * The live sockets, as this side needs to see them. An interface because
     * the friend package must not depend on the socket layer — the same split
     * {@code AccountDeletionService.SessionEnder} makes for the user package.
     */
    public interface ConnectedPlayers {
        boolean isConnected(Long userId);

        int connectedCount();
    }

    private final ConnectedPlayers connected;
    private final Set<Long> inBattle = ConcurrentHashMap.newKeySet();

    public PresenceService(ConnectedPlayers connected) {
        this.connected = connected;
    }

    /**
     * The player's socket has gone. Only the duel flag needs clearing: being
     * online looks after itself now. The duel may well outlive the socket — a
     * drop inside the grace period is not the end of it — but a player nobody
     * can reach is not shown as fighting either, and coming back sets the flag
     * again from whatever duel they are actually in.
     */
    public void disconnected(Long userId) {
        inBattle.remove(userId);
    }

    public void battleStarted(Long userId) {
        inBattle.add(userId);
    }

    public void battleEnded(Long userId) {
        inBattle.remove(userId);
    }

    public boolean isOnline(Long userId) {
        return connected.isConnected(userId);
    }

    public boolean isInBattle(Long userId) {
        return inBattle.contains(userId);
    }

    public int onlineCount() {
        return connected.connectedCount();
    }
}
