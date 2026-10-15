package uz.wordbattle.config;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class RecoveryMailConfigurationGuardTest {

    @Test
    void refusesProductionWhenRecoveryMailIsNotConfigured() {
        assertThatThrownBy(() -> RecoveryMailConfigurationGuard.verify("", 587, "", "", true, "", true))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("MAIL_HOST");
    }

    @Test
    void refusesProductionWhenSmtpAuthenticationCredentialsAreMissing() {
        assertThatThrownBy(() -> RecoveryMailConfigurationGuard.verify(
                        "smtp.example.test", 587, "", "", true, "noreply@example.test", true))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("MAIL_USERNAME")
                .hasMessageContaining("MAIL_PASSWORD");
    }

    @Test
    void refusesProductionWhenSenderAddressIsMalformed() {
        assertThatThrownBy(() -> RecoveryMailConfigurationGuard.verify(
                        "smtp.example.test", 587, "mailer", "secret", true, "not-an-email", true))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("MAIL_FROM");
    }

    @Test
    void acceptsProductionWithCompleteAuthenticatedSmtpConfiguration() {
        assertThatCode(() -> RecoveryMailConfigurationGuard.verify(
                        "smtp.example.test", 587, "mailer", "secret", true, "noreply@example.test", true))
                .doesNotThrowAnyException();
    }

    @Test
    void acceptsUnauthenticatedSmtpWhenExplicitlyConfigured() {
        assertThatCode(() -> RecoveryMailConfigurationGuard.verify(
                        "smtp.example.test", 25, "", "", false, "noreply@example.test", true))
                .doesNotThrowAnyException();
    }

    @Test
    void leavesDevelopmentAndTestsUsableWithoutSmtp() {
        assertThatCode(() -> RecoveryMailConfigurationGuard.verify("", 0, "", "", true, "", false))
                .doesNotThrowAnyException();
    }
}
