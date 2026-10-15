package uz.wordbattle.config;

import jakarta.mail.internet.AddressException;
import jakarta.mail.internet.InternetAddress;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/** Refuses to start production with password recovery mail silently disabled. */
@Component
public class RecoveryMailConfigurationGuard {

    public RecoveryMailConfigurationGuard(
            Environment environment,
            @Value("${spring.mail.host:}") String host,
            @Value("${spring.mail.port:0}") int port,
            @Value("${spring.mail.username:}") String username,
            @Value("${spring.mail.password:}") String password,
            @Value("${spring.mail.properties.mail.smtp.auth:true}") boolean smtpAuth,
            @Value("${wordbattle.recovery.from:}") String from) {
        verify(
                host,
                port,
                username,
                password,
                smtpAuth,
                from,
                environment.acceptsProfiles(Profiles.of(DatabasePasswordGuard.PRODUCTION_PROFILE)));
    }

    static void verify(
            String host, int port, String username, String password, boolean smtpAuth, String from, boolean production) {
        if (!production) return;
        if (host == null || host.isBlank()) {
            throw new IllegalStateException("MAIL_HOST berilmagan — production'da email tiklash ishlamaydi.");
        }
        if (port < 1 || port > 65535) {
            throw new IllegalStateException("MAIL_PORT noto'g'ri — 1 dan 65535 gacha qiymat bering.");
        }
        if (from == null || from.isBlank()) {
            throw new IllegalStateException("MAIL_FROM berilmagan — yuboruvchi email manzilini sozlang.");
        }
        try {
            new InternetAddress(from.trim(), true).validate();
        } catch (AddressException e) {
            throw new IllegalStateException("MAIL_FROM yaroqli email manzili bo'lishi kerak.", e);
        }
        if (smtpAuth && ((username == null || username.isBlank()) || (password == null || password.isBlank()))) {
            throw new IllegalStateException(
                    "SMTP autentifikatsiyasi yoqilgan — MAIL_USERNAME va MAIL_PASSWORD kerak.");
        }
    }
}
