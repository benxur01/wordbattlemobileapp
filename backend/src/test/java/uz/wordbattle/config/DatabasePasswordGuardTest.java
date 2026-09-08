package uz.wordbattle.config;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * The database password is the second half of what {@code JwtServiceTest}
 * guards: a signing secret nobody knows is worth little if the accounts it
 * signs for can be edited directly. These pin down that the sample password
 * stops a production start and leaves every other start alone — the suite
 * itself runs on a blank one.
 */
class DatabasePasswordGuardTest {

    @Test
    void refusesTheSamplePasswordInProduction() {
        assertThatThrownBy(() -> DatabasePasswordGuard.verify("wordbattle", true))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("namunaviy");
    }

    @Test
    void refusesNoPasswordAtAllInProduction() {
        assertThatThrownBy(() -> DatabasePasswordGuard.verify(null, true))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("DB_PASSWORD");
        assertThatThrownBy(() -> DatabasePasswordGuard.verify("  ", true))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void acceptsARealPasswordInProduction() {
        assertThatCode(() -> DatabasePasswordGuard.verify("Ck7t2eQx9pLm4vRb", true)).doesNotThrowAnyException();
    }

    @Test
    void leavesEveryOtherProfileAlone() {
        assertThatCode(() -> DatabasePasswordGuard.verify("wordbattle", false)).doesNotThrowAnyException();
        assertThatCode(() -> DatabasePasswordGuard.verify("", false)).doesNotThrowAnyException();
    }
}
