package uz.wordbattle.friend;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Service;

/**
 * Who is connected right now, and who is mid-duel. Backed by the live WebSocket
 * sessions of a single instance; running more than one node means moving this
 * to Redis (see README).
 */
@Service
public class PresenceService {

    private final Set<Long> online = ConcurrentHashMap.newKeySet();
    private final Set<Long> inBattle = ConcurrentHashMap.newKeySet();

    public void connected(Long userId) {
        online.add(userId);
    }

    public void disconnected(Long userId) {
        online.remove(userId);
        inBattle.remove(userId);
    }

    public void battleStarted(Long userId) {
        inBattle.add(userId);
    }

    public void battleEnded(Long userId) {
        inBattle.remove(userId);
    }

    public boolean isOnline(Long userId) {
        return online.contains(userId);
    }

    public boolean isInBattle(Long userId) {
        return inBattle.contains(userId);
    }

    public int onlineCount() {
        return online.size();
    }
}
