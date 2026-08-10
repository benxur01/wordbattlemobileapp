package uz.wordbattle.ws;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

    private static final Logger log = LoggerFactory.getLogger(FrameRateLimiter.class);

    private static final class Bucket {
        double tokens;
        long lastRefillNanos;

        /**
         * Frames dropped since this player last got one through; zero when
         * they are not being limited. A line per dropped frame is a line for
         * every frame the offending client can write, which is the whole point
         * of the client being throttled — the flood ended up in the log
         * instead of on the server. Counting here rather than in a map of its
         * own means {@link #forget} disposes of it with the bucket.
         */
        long droppedInEpisode;

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
            if (bucket.tokens < 1) {
                // Two lines per flood, not two per second: the opening one so
                // an operator sees it while it is happening, and the closing
                // one below for how bad it was. The client is still told about
                // every dropped frame — that is a frame on its own socket, and
                // it is what stops it retrying blind.
                if (bucket.droppedInEpisode == 0) {
                    log.warn("Rate limit hit by user {}; further drops are counted rather than logged", userId);
                }
                bucket.droppedInEpisode++;
                return false;
            }
            if (bucket.droppedInEpisode > 0) {
                log.warn("Rate limit on user {} lifted after dropping {} frames", userId, bucket.droppedInEpisode);
                bucket.droppedInEpisode = 0;
            }
            bucket.tokens -= 1;
            return true;
        }
    }

    /** Called when the socket closes; the allowance dies with the connection. */
    public void forget(long userId) {
        Bucket bucket = buckets.remove(userId);
        if (bucket == null) return;
        // A flood that ends with the connection never gets the closing line
        // above, and a client that hammers the socket until it is dropped is
        // exactly the one worth having a count for.
        synchronized (bucket) {
            if (bucket.droppedInEpisode > 0) {
                log.warn("Rate limit on user {} ended by disconnect after dropping {} frames",
                        userId, bucket.droppedInEpisode);
            }
        }
    }
}
