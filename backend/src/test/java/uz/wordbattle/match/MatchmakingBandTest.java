package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.function.DoublePredicate;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.ConfigurationPropertySources;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.FileSystemResource;
import uz.wordbattle.config.AppProperties;

/**
 * The queue's rating window, walked second by second against the configuration
 * the server actually ships with.
 *
 * <p>The window and the bot fallback are one setting split across five numbers,
 * and each of the five looked reasonable on its own while the set was broken:
 * the window opened by 25 points every 3 seconds towards a ceiling of 400, and
 * the bot arrived after 12 — by which time the window had reached 175 and had
 * another 27 seconds of widening left to do. Two live accounts 325 apart were
 * handed a bot each in the same second, and a scripted pair 440 apart went the
 * same way. Bot duels are unrated, so players who cannot reach each other
 * cannot close the gap that keeps them apart, and one lopsided run separates
 * them permanently.
 *
 * <p>So this is about the relationship, not the numbers: whatever the five are
 * tuned to, the window has to reach its ceiling before the bot does, and the
 * ceiling has to be wide enough for the gaps real accounts drift to. Read off
 * {@code src/main/resources/application.yml} rather than a copy — a copy is
 * exactly the thing that would drift while the test kept passing.
 *
 * <p>Whether the rest of the suite actually queues players on these five
 * numbers is a separate question, and not this class's to answer: the test
 * classpath carries an application.yml that shadows the shipped one entirely,
 * so every other test here runs on the {@code @DefaultValue} annotations
 * instead. This class used to guard that too. It is
 * {@link uz.wordbattle.config.ShippedConfigurationTest}'s job now, for every
 * property rather than only these five.
 */
class MatchmakingBandTest {

    /** What the server ships. */
    private static final Path SHIPPED_YAML = Path.of("src/main/resources/application.yml");

    /**
     * The two gaps that stranded live accounts on 2026-08-09 — 1362 against
     * 1037, and a scripted pair that had drifted 440 apart. Neither is a limit
     * anybody chose; they are what a handful of one-sided results did to four
     * accounts in one afternoon, so the ceiling has to clear them with room.
     */
    private static final double OBSERVED_GAP = 324.62;
    private static final double WIDEST_OBSERVED_GAP = 440;

    @Test
    void theWindowReachesItsCeilingBeforeTheBotTakesOver() {
        AppProperties.Matchmaking config = shipped();

        long ceilingAt = firstSecondWhere(config, band -> band >= config.maxBand());

        assertThat(ceilingAt)
                .as("max-band %d is unreachable: the window needs %ds and the bot arrives at %ds",
                        config.maxBand(), ceilingAt, config.botFallbackSeconds())
                .isLessThanOrEqualTo(config.botFallbackSeconds());
    }

    @Test
    void twoPlayersFurtherApartThanTheOpeningWindowStillMeet() {
        AppProperties.Matchmaking config = shipped();

        // Worth stating out loud: both gaps are outside the opening window, so
        // neither pair could have met on the first tick. The fix is that they
        // meet at all, not that they meet at once.
        assertThat(OBSERVED_GAP).isGreaterThan(config.initialBand());
        assertThat(WIDEST_OBSERVED_GAP).isGreaterThan(config.initialBand());

        assertThat(firstSecondWhere(config, band -> band >= OBSERVED_GAP))
                .as("a %s-point gap has to be inside the window before the bot at %ds",
                        OBSERVED_GAP, config.botFallbackSeconds())
                .isLessThanOrEqualTo(config.botFallbackSeconds());
        assertThat(firstSecondWhere(config, band -> band >= WIDEST_OBSERVED_GAP))
                .as("a %s-point gap has to be inside the window before the bot at %ds",
                        WIDEST_OBSERVED_GAP, config.botFallbackSeconds())
                .isLessThanOrEqualTo(config.botFallbackSeconds());
    }

    /**
     * A player alone in the queue still has to be given a game. There is no
     * right number here, only an outer bound: past it the search screen stops
     * reading as a search, however honestly its clock counts.
     */
    @Test
    void aPlayerWithNobodyToPlayIsNotLeftSearchingForever() {
        assertThat(shipped().botFallbackSeconds()).isLessThanOrEqualTo(45);
    }

    // --------------------------------------------------------------- helpers

    /**
     * The first whole second at which the window satisfies {@code test}, using
     * the service's own arithmetic. Seconds rather than steps because that is
     * the clock both the widening and the bot fallback are read against, and
     * the two truncate to it the same way.
     */
    private long firstSecondWhere(AppProperties.Matchmaking config, DoublePredicate test) {
        for (long second = 0; second <= 600; second++) {
            if (test.test(MatchmakingService.bandAfter(config, second))) return second;
        }
        throw new AssertionError("The window never widens that far, however long anyone waits");
    }

    private AppProperties.Matchmaking shipped() {
        assertThat(Files.exists(SHIPPED_YAML))
                .as("%s (run from the backend module, as Maven does)", SHIPPED_YAML.toAbsolutePath())
                .isTrue();
        try {
            List<PropertySource<?>> yaml =
                    new YamlPropertySourceLoader().load("shipped", new FileSystemResource(SHIPPED_YAML));
            return new Binder(ConfigurationPropertySources.from(yaml))
                    .bind("wordbattle.matchmaking", AppProperties.Matchmaking.class)
                    .orElseThrow(() -> new AssertionError("No wordbattle.matchmaking block in " + SHIPPED_YAML));
        } catch (IOException e) {
            throw new AssertionError("Could not read " + SHIPPED_YAML, e);
        }
    }
}
