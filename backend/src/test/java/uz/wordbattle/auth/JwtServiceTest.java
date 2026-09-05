package uz.wordbattle.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Duration;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import uz.wordbattle.config.AppProperties;

/**
 * The secret is the whole of the server's security: anyone who knows it can
 * sign a token for any account. These tests pin down that a server carrying a
 * placeholder — or nothing at all — refuses to start rather than running with
 * a secret published in the repository.
 */
class JwtServiceTest {

    /** Every account on generation zero: the state a server with no sign-outs is in. */
    private static JwtService withSecret(String secret) {
        return withSecret(secret, userId -> Optional.of(0L));
    }

    private static JwtService withSecret(String secret, TokenGenerations generations) {
        AppProperties props = new AppProperties(
                new AppProperties.Jwt(secret, Duration.ofDays(1), "wordbattle-test"),
                new AppProperties.Google(""),
                new AppProperties.Duel(15, 3, 9, 12, Set.of('x', 'z')),
                new AppProperties.Matchmaking(75, 25, 400, 3, 12),
                new AppProperties.Rating(Duration.ofHours(24)),
                new AppProperties.Cors(List.of()),
                new AppProperties.Limits(20, 40, 64),
                new AppProperties.Admin(""),
                new AppProperties.Tournament(new AppProperties.Tournament.Global("0 0 20 * * SUN", 32)),
                ZoneId.of("Asia/Tashkent"),
                false);
        return new JwtService(props, generations);
    }

    @Test
    void refusesToStartWithoutASecret() {
        assertThatThrownBy(() -> withSecret(null))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("JWT_SECRET");
        assertThatThrownBy(() -> withSecret("  "))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void refusesTheSecretThatUsedToShipAsTheDefault() {
        assertThatThrownBy(() -> withSecret("change-me-in-production-please-32-bytes-minimum!!"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("namunaviy");
    }

    @Test
    void refusesASecretTooShortForHs256() {
        assertThatThrownBy(() -> withSecret("short")).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void roundTripsTheUserId() {
        JwtService jwt = withSecret("a-real-secret-of-at-least-32-bytes-length");
        assertThat(jwt.userIdFrom(jwt.issue(42L, 0))).contains(42L);
    }

    @Test
    void rejectsATokenSignedWithAnotherSecret() {
        String foreign = withSecret("a-completely-different-secret-32-bytes!!").issue(42L, 0);
        assertThat(withSecret("a-real-secret-of-at-least-32-bytes-length").userIdFrom(foreign)).isEmpty();
    }

    /**
     * The rule the whole of revocation rests on. Everything else — the logout
     * endpoint, the socket handshake — is this comparison reached by a
     * different road.
     */
    @Test
    void refusesATokenFromAGenerationTheAccountHasLeftBehind() {
        AtomicLong generation = new AtomicLong(7);
        JwtService jwt = withSecret(
                "a-real-secret-of-at-least-32-bytes-length", userId -> Optional.of(generation.get()));

        String token = jwt.issue(42L, generation.get());
        assertThat(jwt.userIdFrom(token)).contains(42L);

        // What signing out does to the row.
        generation.incrementAndGet();
        assertThat(jwt.userIdFrom(token)).isEmpty();
    }

    /**
     * An account that answers nothing — deleted, or a row that is simply not
     * there any more. Its tokens are still perfectly signed, and must name
     * nobody all the same.
     */
    @Test
    void refusesAPerfectlySignedTokenForAnAccountThatIsGone() {
        JwtService jwt = withSecret("a-real-secret-of-at-least-32-bytes-length", userId -> Optional.empty());
        assertThat(jwt.userIdFrom(jwt.issue(42L, 0))).isEmpty();
    }
}
