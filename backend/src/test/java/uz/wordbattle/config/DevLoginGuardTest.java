package uz.wordbattle.config;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * The dev login hands a token to anyone who asks, which is what a laptop and
 * this suite want and what a production server must never do. These pin down
 * that switching it on stops a production start and leaves every other start
 * alone — the suite itself runs with it on.
 */
class DevLoginGuardTest {

    @Test
    void refusesDevLoginInProduction() {
        assertThatThrownBy(() -> DevLoginGuard.verify(true, true))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("DEV_LOGIN_ENABLED");
    }

    @Test
    void acceptsProductionWithDevLoginOff() {
        assertThatCode(() -> DevLoginGuard.verify(false, true)).doesNotThrowAnyException();
    }

    @Test
    void leavesEveryOtherProfileAlone() {
        assertThatCode(() -> DevLoginGuard.verify(true, false)).doesNotThrowAnyException();
        assertThatCode(() -> DevLoginGuard.verify(false, false)).doesNotThrowAnyException();
    }
}
