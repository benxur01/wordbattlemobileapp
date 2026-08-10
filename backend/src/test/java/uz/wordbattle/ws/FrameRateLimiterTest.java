package uz.wordbattle.ws;

import static org.assertj.core.api.Assertions.assertThat;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import java.time.Duration;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import uz.wordbattle.config.AppProperties;

/**
 * The token bucket, and how much of the log a client hammering the socket is
 * allowed to take.
 *
 * <p>The second half is the reason this exists. Refusing a frame used to write
 * a line, so a client writing frames as fast as it could was throttled on the
 * socket and unthrottled in the log — the flood landed in the file instead of
 * on the game, and pushed everything worth reading out of the window. What an
 * operator actually needs is that it started, and how bad it got.
 */
class FrameRateLimiterTest {

    private static final long PLAYER = 7;

    private final ch.qos.logback.classic.Logger logger =
            (ch.qos.logback.classic.Logger) LoggerFactory.getLogger(FrameRateLimiter.class);
    private final ListAppender<ILoggingEvent> logged = new ListAppender<>();

    @BeforeEach
    void captureTheLog() {
        logged.start();
        logger.addAppender(logged);
    }

    @AfterEach
    void releaseTheLog() {
        logger.detachAppender(logged);
        logged.stop();
    }

    /**
     * A limiter built straight from a record, the way {@code JwtServiceTest}
     * builds its own: the bucket reads two numbers out of {@code limits} and
     * nothing else, so a Spring context would only make this slower.
     */
    private static FrameRateLimiter limiter(int framesPerSecond, int burst) {
        AppProperties props = new AppProperties(
                new AppProperties.Jwt("x".repeat(32), Duration.ofDays(1), "wordbattle-test"),
                new AppProperties.Google(""),
                new AppProperties.Duel(15, 3, 9, 12, Set.of('x', 'z')),
                new AppProperties.Matchmaking(75, 40, 500, 3, 35),
                new AppProperties.Rating(Duration.ofHours(24)),
                new AppProperties.Cors(List.of()),
                new AppProperties.Limits(framesPerSecond, burst, 64),
                ZoneId.of("Asia/Tashkent"),
                false);
        return new FrameRateLimiter(props);
    }

    private List<String> warnings() {
        return logged.list.stream()
                .filter(event -> event.getLevel() == Level.WARN)
                .map(ILoggingEvent::getFormattedMessage)
                .toList();
    }

    @Test
    void theBurstIsSpentAndThenNothingGetsThrough() {
        FrameRateLimiter limiter = limiter(1, 1);

        assertThat(limiter.allow(PLAYER)).isTrue();
        for (int frame = 0; frame < 50; frame++) {
            assertThat(limiter.allow(PLAYER)).as("frame %d", frame).isFalse();
        }
    }

    /** The allowance belongs to the connection, so a new one starts full. */
    @Test
    void aClosedSocketTakesItsAllowanceWithIt() {
        FrameRateLimiter limiter = limiter(1, 1);
        limiter.allow(PLAYER);
        assertThat(limiter.allow(PLAYER)).isFalse();

        limiter.forget(PLAYER);

        assertThat(limiter.allow(PLAYER)).isTrue();
    }

    /**
     * Two lines for a flood of any size: one as it starts, one as it ends
     * carrying the count. Five hundred refused frames is far more than a real
     * client sends and exactly what a broken or hostile one does, and the point
     * is that the number changes nothing about how much gets written.
     */
    @Test
    void aFloodCostsTwoLogLinesHoweverLongItRuns() throws Exception {
        // Two per second, so a token is back in half a second — long enough
        // that the loop below cannot earn one part way through, short enough
        // to wait for.
        FrameRateLimiter limiter = limiter(2, 2);
        while (limiter.allow(PLAYER)) {
            // Spend the burst first; the drops are what this is about.
        }
        for (int frame = 0; frame < 500; frame++) {
            limiter.allow(PLAYER);
        }

        assertThat(warnings()).as("while the flood is still running").hasSize(1);

        Thread.sleep(600);
        assertThat(limiter.allow(PLAYER)).isTrue();

        assertThat(warnings()).hasSize(2);
        assertThat(warnings().get(1)).contains("501 frames");
    }

    /**
     * A client that hammers the socket until the connection goes is the one
     * most worth having a count for, and it is the one that never reaches the
     * closing line above — nothing gets through, so nothing lifts the limit.
     * Two lines rather than one because the burst is at least one frame wide,
     * so the very first call is always allowed and opens the episode.
     */
    @Test
    void aFloodThatEndsWithTheConnectionIsStillCounted() {
        FrameRateLimiter limiter = limiter(1, 1);
        for (int frame = 0; frame < 100; frame++) {
            limiter.allow(PLAYER);
        }

        limiter.forget(PLAYER);

        assertThat(warnings()).hasSize(2);
        assertThat(warnings().get(1)).contains("disconnect").contains("99 frames");
    }
}
