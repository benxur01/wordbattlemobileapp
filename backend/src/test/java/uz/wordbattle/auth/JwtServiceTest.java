package uz.wordbattle.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Duration;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import uz.wordbattle.config.AppProperties;

/**
 * The secret is the whole of the server's security: anyone who knows it can
 * sign a token for any account. These tests pin down that a server carrying a
 * placeholder — or nothing at all — refuses to start rather than running with
 * a secret published in the repository.
 */
class JwtServiceTest {

    private static JwtService withSecret(String secret) {
        AppProperties props = new AppProperties(
                new AppProperties.Jwt(secret, Duration.ofDays(1), "wordbattle-test"),
                new AppProperties.Google(""),
                new AppProperties.Duel(15, 3, 9, 12, Set.of('x', 'z')),
                new AppProperties.Matchmaking(75, 25, 400, 3, 12),
                new AppProperties.Cors(List.of()),
                new AppProperties.Limits(20, 40, 64),
                ZoneId.of("Asia/Tashkent"),
                false);
        return new JwtService(props);
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
        assertThat(jwt.userIdFrom(jwt.issue(42L))).contains(42L);
    }

    @Test
    void rejectsATokenSignedWithAnotherSecret() {
        String foreign = withSecret("a-completely-different-secret-32-bytes!!").issue(42L);
        assertThat(withSecret("a-real-secret-of-at-least-32-bytes-length").userIdFrom(foreign)).isEmpty();
    }
}
