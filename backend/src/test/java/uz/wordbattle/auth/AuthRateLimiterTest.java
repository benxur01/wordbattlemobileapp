package uz.wordbattle.auth;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import uz.wordbattle.config.AppProperties;

/**
 * The bucket in front of the password routes, and the boundary it is drawn on.
 *
 * <p>Exercised through {@code doFilter} rather than through a helper of its
 * own, because half of what this class does is decide which requests it is even
 * about: a limiter that guards the wrong paths is either a hole on {@code
 * /login} or an outage on everything else under {@code /api/auth}.
 */
class AuthRateLimiterTest {

    private static final String LOGIN = "/api/auth/login";
    private static final String REGISTER = "/api/auth/register";
    private static final String ADDRESS = "203.0.113.7";

    private static final ObjectMapper JSON = new ObjectMapper().registerModule(new JavaTimeModule());

    /** Counts what got through, since a pass-through leaves no mark on the response. */
    private static final class RecordingChain implements FilterChain {
        int passed;

        @Override
        public void doFilter(ServletRequest request, ServletResponse response) {
            passed++;
        }
    }

    private final RecordingChain chain = new RecordingChain();

    /**
     * A limiter built straight from a record, the way {@code FrameRateLimiterTest}
     * builds its own: the bucket reads two numbers out of {@code auth} and
     * nothing else, so a Spring context would only make this slower.
     */
    private static AuthRateLimiter limiter(int attemptsPerMinute, int burst) {
        AppProperties props = new AppProperties(
                new AppProperties.Jwt("x".repeat(32), Duration.ofDays(1), "wordbattle-test"),
                new AppProperties.Google(""),
                new AppProperties.Duel(15, 3, 9, 12, Set.of('x', 'z')),
                new AppProperties.Matchmaking(75, 40, 500, 3, 35, 75),
                new AppProperties.Rating(Duration.ofHours(24)),
                new AppProperties.Cors(List.of()),
                new AppProperties.Limits(20, 40, 64),
                new AppProperties.Auth(attemptsPerMinute, burst),
                new AppProperties.Admin(""),
                new AppProperties.Tournament(
                        new AppProperties.Tournament.Global(
                                "0 0 8 * * MON", "0 0 19 * * SUN", 32, Duration.ofHours(48)),
                        new AppProperties.Tournament.GlobalTeam("0 0 9 * * MON", "0 30 19 * * SUN", 8)),
                ZoneId.of("Asia/Tashkent"),
                false);
        return new AuthRateLimiter(props, JSON);
    }

    private MockHttpServletResponse attempt(AuthRateLimiter limiter, String path, String address)
            throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", path);
        request.setRemoteAddr(address);
        MockHttpServletResponse response = new MockHttpServletResponse();
        limiter.doFilter(request, response, chain);
        return response;
    }

    private MockHttpServletResponse attempt(AuthRateLimiter limiter, String path)
            throws ServletException, IOException {
        return attempt(limiter, path, ADDRESS);
    }

    @Test
    void theBurstIsSpentAndThenNothingReachesTheController() throws Exception {
        AuthRateLimiter limiter = limiter(1, 2);

        assertThat(attempt(limiter, LOGIN).getStatus()).isEqualTo(200);
        assertThat(attempt(limiter, LOGIN).getStatus()).isEqualTo(200);

        MockHttpServletResponse refused = attempt(limiter, LOGIN);

        assertThat(refused.getStatus()).isEqualTo(429);
        assertThat(chain.passed).as("attempts that reached the controller").isEqualTo(2);
        assertThat(JSON.readTree(refused.getContentAsString(StandardCharsets.UTF_8)).get("code").asText())
                .isEqualTo("too_many_attempts");
    }

    /** One allowance, whichever of the two the caller spends it on. */
    @Test
    void loginAndRegisterShareOneAllowance() throws Exception {
        AuthRateLimiter limiter = limiter(1, 1);

        assertThat(attempt(limiter, REGISTER).getStatus()).isEqualTo(200);

        assertThat(attempt(limiter, LOGIN).getStatus()).isEqualTo(429);
    }

    /**
     * Everything else under {@code /api/auth} is somebody else's problem: a
     * Google token is checked against Google's keys, and a sign-out is the last
     * call to start refusing. A prefix match here would have throttled both.
     */
    @Test
    void theOtherAuthRoutesAreNotGuarded() throws Exception {
        AuthRateLimiter limiter = limiter(1, 1);
        attempt(limiter, LOGIN);
        assertThat(attempt(limiter, LOGIN).getStatus()).isEqualTo(429);

        assertThat(attempt(limiter, "/api/auth/google").getStatus()).isEqualTo(200);
        assertThat(attempt(limiter, "/api/auth/logout").getStatus()).isEqualTo(200);
        assertThat(attempt(limiter, "/api/auth/dev").getStatus()).isEqualTo(200);
    }

    /** Otherwise one player guessing their own password locks out everybody else. */
    @Test
    void eachAddressSpendsItsOwn() throws Exception {
        AuthRateLimiter limiter = limiter(1, 1);
        attempt(limiter, LOGIN, "198.51.100.4");

        assertThat(attempt(limiter, LOGIN, "198.51.100.4").getStatus()).isEqualTo(429);
        assertThat(attempt(limiter, LOGIN, "198.51.100.5").getStatus()).isEqualTo(200);
    }

    /** A player who mistyped their password gets back in without reinstalling anything. */
    @Test
    void theAllowanceComesBackWithTime() throws Exception {
        // 120 a minute is a token every half a second: long enough that the two
        // attempts below cannot earn one part way through, short enough to wait.
        AuthRateLimiter limiter = limiter(120, 1);
        attempt(limiter, LOGIN);
        assertThat(attempt(limiter, LOGIN).getStatus()).isEqualTo(429);

        Thread.sleep(600);

        assertThat(attempt(limiter, LOGIN).getStatus()).isEqualTo(200);
    }

    /**
     * The sweep exists so a caller working through an address range is not
     * remembered a bucket at a time — but it must not be a way of buying
     * attempts back, so the one address still being refused keeps its bucket
     * and the one that stopped knocking loses a bucket it would have been given
     * again for free.
     */
    @Test
    void sweepingIdleAddressesHandsNobodyAnExtraAttempt() throws Exception {
        AuthRateLimiter limiter = limiter(1, 1);
        attempt(limiter, LOGIN);
        assertThat(attempt(limiter, LOGIN).getStatus()).isEqualTo(429);

        limiter.forgetIdleAddresses();

        assertThat(attempt(limiter, LOGIN).getStatus()).isEqualTo(429);
    }
}
