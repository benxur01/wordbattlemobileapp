package uz.wordbattle.config;

import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * Refuses to start a production server with the dev login switched on, the way
 * {@link DatabasePasswordGuard} refuses one on the sample database password.
 *
 * <p>{@code POST /api/auth/dev} asks for nothing — no password, no Google token
 * — and answers every call with a brand-new account and a token for it.
 * {@link uz.wordbattle.auth.AuthRateLimiter} leaves it unthrottled on the
 * understanding that it does not exist in production, so left on it is
 * {@code /register} without the password or the rate limit: as many accounts
 * as anyone cares to script. It ships off; the way it reaches a server is
 * {@code DEV_LOGIN_ENABLED=true} carried over from a laptop's {@code .env}.
 *
 * <p>Gated on the same {@code prod} profile as the database check, for the
 * same reason: everywhere else the flag is genuinely wanted — a local run with
 * no Google project behind it, and the test suite, which signs in through it
 * throughout.
 */
@Component
public class DevLoginGuard {

    public DevLoginGuard(Environment environment, AppProperties props) {
        verify(props.devLoginEnabled(),
                environment.acceptsProfiles(Profiles.of(DatabasePasswordGuard.PRODUCTION_PROFILE)));
    }

    static void verify(boolean devLoginEnabled, boolean production) {
        if (production && devLoginEnabled) {
            throw new IllegalStateException(
                    "DEV_LOGIN_ENABLED prod profilida yoqilgan — /api/auth/dev so'ragan har kimga parolsiz token "
                            + "beradi. O'chiring:  DEV_LOGIN_ENABLED=false");
        }
    }
}
