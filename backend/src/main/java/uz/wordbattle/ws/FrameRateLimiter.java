package uz.wordbattle.ws;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;
import uz.wordbattle.config.AppProperties;

/**
 * A token bucket per connected player, so one client cannot drive the server
 * with frames as fast as it can write them.
 *
 * <p>Nothing on the socket is expensive on its own — but {@code queue.join}
 * touches the database and re-runs pairing, and {@code duel.submit} searches
 * the dictionary, so an unthrottled loop is a cheap way to make the game
 * unplayable for everybody else. The bucket refills continuously at the
 * configured rate and holds a burst, which is well clear of real play: a duel
 * turn is one frame every few seconds, plus a heartbeat every 25.
 */
@Component
public class FrameRateLimiter {

    private static final class Bucket {
        double tokens;
        long lastRefillNanos;

        Bucket(double tokens, long now) {
            this.tokens = tokens;
            this.lastRefillNanos = now;
        }
    }

    private final Map<Long, Bucket> buckets = new ConcurrentHashMap<>();
    private final double ratePerSecond;
    private final double burst;

    public FrameRateLimiter(AppProperties props) {
        this.ratePerSecond = Math.max(1, props.limits().socketFramesPerSecond());
        this.burst = Math.max(ratePerSecond, props.limits().socketFrameBurst());
    }

    /** True when this frame fits inside the player's allowance. */
    public boolean allow(long userId) {
        long now = System.nanoTime();
        Bucket bucket = buckets.computeIfAbsent(userId, id -> new Bucket(burst, now));
        synchronized (bucket) {
            double elapsedSeconds = (now - bucket.lastRefillNanos) / 1_000_000_000.0;
            bucket.lastRefillNanos = now;
            bucket.tokens = Math.min(burst, bucket.tokens + elapsedSeconds * ratePerSecond);
            if (bucket.tokens < 1) return false;
            bucket.tokens -= 1;
            return true;
        }
    }

    /** Called when the socket closes; the allowance dies with the connection. */
    public void forget(long userId) {
        buckets.remove(userId);
    }
}
