package uz.wordbattle.config;

import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * Refuses to start a production server on the sample database password, the
 * same way {@link uz.wordbattle.auth.JwtService} refuses to start on the sample
 * signing secret.
 *
 * <p>The two are one risk seen twice. {@code .env.example} ships
 * {@code DB_PASSWORD=wordbattle} so the quickstart runs with nothing filled in,
 * and a password published in the repository protects nothing — every account,
 * every duel and every token generation is one {@code psql} away from anyone
 * who has read it.
 *
 * <p>Unlike the JWT check this one is profile-gated, because the sample value
 * is genuinely wanted everywhere else: {@code docker compose up} after
 * {@code cp .env.example .env} has to work, and the test suite runs on H2 with
 * no password at all. The {@code prod} profile is the line between the two, and
 * a deployment that never sets it gets no check — which is why the release
 * checklist in the README names it.
 */
@Component
public class DatabasePasswordGuard {

    /** Set {@code SPRING_PROFILES_ACTIVE=prod} on a real deployment. */
    public static final String PRODUCTION_PROFILE = "prod";

    /**
     * Passwords that ship in this repository. Anyone with a copy of it knows
     * them, so a production server carrying one must not start.
     */
    private static final Set<String> KNOWN_DEFAULTS = Set.of("wordbattle", "postgres", "changeme");

    public DatabasePasswordGuard(Environment environment, @Value("${spring.datasource.password:}") String password) {
        verify(password, environment.acceptsProfiles(Profiles.of(PRODUCTION_PROFILE)));
    }

    static void verify(String password, boolean production) {
        if (!production) return;
        if (password == null || password.isBlank()) {
            throw new IllegalStateException(
                    "DB_PASSWORD berilmagan. Yarating va bering:  export DB_PASSWORD=\"$(openssl rand -base64 24)\"");
        }
        if (KNOWN_DEFAULTS.contains(password.trim())) {
            throw new IllegalStateException(
                    "DB_PASSWORD namunaviy qiymatda qolgan — u ochiq va uni bilgan odam bazaga to'g'ridan-to'g'ri "
                            + "ulana oladi. Yangisini bering:  openssl rand -base64 24");
        }
    }
}
