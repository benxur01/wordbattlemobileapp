package uz.wordbattle.auth;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.lang.NonNull;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import uz.wordbattle.common.ApiError;
import uz.wordbattle.config.AppProperties;

/**
 * A token bucket per client address in front of password and email-code routes,
 * so a caller can neither guess at an account nor invent them as fast as it can
 * send requests.
 *
 * <p>{@link uz.wordbattle.ws.FrameRateLimiter} does the same for the socket and
 * keys on the player, which is what every other ceiling in this game can do —
 * behind a socket there is a token and a user id. Login, registration and
 * password-reset routes have no signed-in identity to rate-limit by, so they
 * use the caller's address instead. This prevents scripted password guessing,
 * account creation and code guessing from turning into unlimited work.
 *
 * <p>The signed-in recovery-email routes are separately limited per account by
 * their resend cooldown. Nothing else under {@code /api/auth/**} is throttled:
 * {@code /google} is settled by Google's signature over its token, {@code /dev}
 * is disabled in production, and {@code /logout} should remain available to a
 * player who is already leaving.
 */
@Component
public class AuthRateLimiter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(AuthRateLimiter.class);

    /** Anonymous credential and code routes guarded, spelled exactly as mapped. */
    private static final String LOGIN_PATH = "/api/auth/login";

    private static final String REGISTER_PATH = "/api/auth/register";

    private static final String RESET_REQUEST_PATH = "/api/auth/password-reset/request";

    private static final String RESET_COMPLETE_PATH = "/api/auth/password-reset/complete";

    private static final class Bucket {
        double tokens;
        long lastRefillNanos;

        /**
         * Attempts refused since this address last got one through; zero when
         * it is not being limited. A line per refusal is a line for every
         * request the offending caller can write, which is the flood landing in
         * the log instead of on the database — the opening and closing lines
         * below say the same thing in two.
         */
        long refusedInEpisode;

        Bucket(double tokens, long now) {
            this.tokens = tokens;
            this.lastRefillNanos = now;
        }
    }

    private final Map<String, Bucket> buckets = new ConcurrentHashMap<>();
    private final ObjectMapper mapper;
    private final double ratePerSecond;
    private final double burst;

    public AuthRateLimiter(AppProperties props, ObjectMapper mapper) {
        this.mapper = mapper;
        this.ratePerSecond = Math.max(1, props.auth().attemptsPerMinute()) / 60.0;
        this.burst = Math.max(1, props.auth().attemptBurst());
    }

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain chain)
            throws ServletException, IOException {

        if (!isGuarded(request.getRequestURI()) || allow(clientAddress(request))) {
            chain.doFilter(request, response);
            return;
        }
        // Written here rather than thrown, because a filter runs outside the
        // dispatcher and GlobalExceptionHandler never sees what it raises. The
        // body is the shape every other failure has, so the app reads the
        // message off it the way it reads any other — see RestAuthEntryPoint,
        // which answers from the same position for the same reason.
        response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        mapper.writeValue(
                response.getOutputStream(), ApiError.of("too_many_attempts", "Juda ko'p urinish — biroz kuting"));
    }

    /** True when this attempt fits inside the address's allowance. */
    private boolean allow(String address) {
        long now = System.nanoTime();
        Bucket bucket = buckets.computeIfAbsent(address, key -> new Bucket(burst, now));
        synchronized (bucket) {
            double elapsedSeconds = (now - bucket.lastRefillNanos) / 1_000_000_000.0;
            bucket.lastRefillNanos = now;
            bucket.tokens = Math.min(burst, bucket.tokens + elapsedSeconds * ratePerSecond);
            if (bucket.tokens < 1) {
                if (bucket.refusedInEpisode == 0) {
                    log.warn("Auth rate limit hit by {}; further refusals are counted rather than logged", address);
                }
                bucket.refusedInEpisode++;
                return false;
            }
            if (bucket.refusedInEpisode > 0) {
                log.warn("Auth rate limit on {} lifted after refusing {} attempt(s)", address, bucket.refusedInEpisode);
                bucket.refusedInEpisode = 0;
            }
            bucket.tokens -= 1;
            return true;
        }
    }

    /**
     * Forgets the addresses that have stopped knocking. The socket's limiter
     * has a disconnect to drop a bucket on; this one has nothing of the kind,
     * and its keys are chosen by whoever calls — so an address that tries once
     * and never returns would be remembered for the life of the process, and a
     * caller working through a range would be remembered a bucket at a time.
     *
     * <p>Only full buckets go, which is what makes dropping them free: a bucket
     * that has refilled to the brim is indistinguishable from one that was
     * never created, since {@link #allow} starts a new address at exactly that.
     * A bucket touched while this runs is not full by definition and is left
     * where it is.
     */
    @Scheduled(fixedDelay = 5 * 60 * 1000L)
    public void forgetIdleAddresses() {
        long now = System.nanoTime();
        long refilledAfterNanos = (long) (burst / ratePerSecond * 1_000_000_000.0);
        buckets.values().removeIf(bucket -> {
            synchronized (bucket) {
                return now - bucket.lastRefillNanos >= refilledAfterNanos;
            }
        });
    }

    /**
     * Exactly the mapped paths and nothing around them. Equality rather
     * than a prefix, because the prefix here is {@code /api/auth} and the rest
     * of what lives under it is deliberately not throttled here.
     */
    private static boolean isGuarded(String uri) {
        return LOGIN_PATH.equals(uri)
                || REGISTER_PATH.equals(uri)
                || RESET_REQUEST_PATH.equals(uri)
                || RESET_COMPLETE_PATH.equals(uri);
    }

    /**
     * Who the attempt came from. {@code X-Forwarded-For} is deliberately not
     * read here: with nothing in front of the server the header could only
     * arrive from the caller, and honouring it would hand every caller a fresh
     * allowance per attempt by writing a new address on each one.
     *
     * <p>A reverse proxy in front turns that around — without the header every
     * player in the world shares a single bucket belonging to the proxy. That
     * case is handled one layer down rather than here, by
     * {@code server.forward-headers-strategy=native} (see application.yml):
     * Tomcat's {@code RemoteIpValve} rewrites the remote address from the
     * header before any filter runs, and only when the request's peer is a
     * trusted proxy — which is why the API port then has to be reachable
     * through the proxy alone. The default, {@code none}, leaves the header
     * unread, and this returns the TCP peer as it always did.
     */
    private static String clientAddress(HttpServletRequest request) {
        return request.getRemoteAddr();
    }
}
