package uz.wordbattle.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Locale;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.MailException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;

/** Verified-email challenges for account recovery. Codes are short-lived, single-use and bound to the server secret. */
@Service
public class AuthRecoveryService {

    private static final Logger log = LoggerFactory.getLogger(AuthRecoveryService.class);
    private static final String VERIFY_EMAIL = "verify_email";
    private static final String RESET_PASSWORD = "reset_password";
    private static final Duration CODE_LIFETIME = Duration.ofMinutes(10);
    private static final Duration RESEND_DELAY = Duration.ofSeconds(60);
    private static final int MAX_ATTEMPTS = 5;
    private static final SecureRandom RANDOM = new SecureRandom();

    private final AuthRecoveryCodeRepository codes;
    private final UserRepository users;
    private final UserService userService;
    private final ObjectProvider<JavaMailSender> mailSenders;
    private final byte[] secret;
    private final String from;
    private final String mailHost;

    public AuthRecoveryService(
            AuthRecoveryCodeRepository codes,
            UserRepository users,
            UserService userService,
            ObjectProvider<JavaMailSender> mailSenders,
            @Value("${wordbattle.jwt.secret:}") String secret,
            @Value("${wordbattle.recovery.from:}") String from,
            @Value("${spring.mail.host:}") String mailHost) {
        this.codes = codes;
        this.users = users;
        this.userService = userService;
        this.mailSenders = mailSenders;
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
        this.from = from;
        this.mailHost = mailHost;
    }

    /** Returns false when SMTP is not configured, so a local account can still be created and secured later. */
    @Transactional
    public boolean requestEmailVerification(Long userId, String rawEmail) {
        User user = userService.require(userId);
        if (user.getPasswordHash() == null) {
            throw ApiException.badRequest(
                    "password_recovery_unavailable", "Parol bilan kiradigan akkauntlarda email tiklash ishlaydi");
        }
        String email = normaliseEmail(rawEmail);
        if (user.hasVerifiedRecoveryEmail() && email.equalsIgnoreCase(user.getRecoveryEmail())) return true;
        if (users.recoveryEmailUsedByAnother(email, userId)) {
            throw ApiException.conflict("recovery_email_used", "Bu email boshqa akkauntga bog'langan");
        }
        user.setPendingRecoveryEmail(email);
        users.save(user);
        if (!mailConfigured()) return false;
        return sendCode(user, VERIFY_EMAIL, email,
                "Word Battle email tasdiqlash kodi", "Email manzilingizni tasdiqlash uchun ushbu kodni kiriting:");
    }

    @Transactional(noRollbackFor = ApiException.class)
    public void verifyRecoveryEmail(Long userId, String rawCode) {
        AuthRecoveryCode challenge = requireValidCode(userId, VERIFY_EMAIL, rawCode);
        User user = userService.require(userId);
        if (!challenge.getEmail().equalsIgnoreCase(user.getPendingRecoveryEmail())) {
            codes.delete(challenge);
            throw invalidCode();
        }
        if (users.recoveryEmailUsedByAnother(challenge.getEmail(), userId)) {
            codes.delete(challenge);
            throw ApiException.conflict("recovery_email_used", "Bu email boshqa akkauntga bog'langan");
        }
        user.setRecoveryEmail(challenge.getEmail(), Instant.now());
        user.setPendingRecoveryEmail(null);
        users.saveAndFlush(user);
        codes.delete(challenge);
    }

    /** Sends only for an existing, verified password account; the caller always receives the same answer. */
    @Transactional
    public void requestPasswordReset(String rawEmail) {
        if (!mailConfigured()) return;
        String email = normaliseEmail(rawEmail);
        users.findByRecoveryEmailIgnoreCaseAndRecoveryEmailVerifiedAtIsNotNull(email)
                .filter(user -> user.getPasswordHash() != null && !user.isDeleted() && !user.isBanned())
                .ifPresent(user -> {
                    try {
                        sendCode(user, RESET_PASSWORD, email,
                                "Word Battle parolni tiklash kodi", "Parolni yangilash uchun ushbu kodni kiriting:");
                    } catch (ApiException ignored) {
                        // The anonymous request always has the same response for a missing
                        // address, a cooldown and a successful email delivery.
                    }
                });
    }

    @Transactional(noRollbackFor = ApiException.class)
    public void resetPassword(String rawEmail, String rawCode, String newPassword) {
        String email = normaliseEmail(rawEmail);
        User user = users.findByRecoveryEmailIgnoreCaseAndRecoveryEmailVerifiedAtIsNotNull(email)
                .filter(candidate -> candidate.getPasswordHash() != null && !candidate.isDeleted() && !candidate.isBanned())
                .orElseThrow(() -> invalidCode());
        AuthRecoveryCode challenge = requireValidCode(user.getId(), RESET_PASSWORD, rawCode);
        if (!challenge.getEmail().equalsIgnoreCase(email)) throw invalidCode();
        userService.changePassword(user.getId(), newPassword);
        codes.delete(challenge);
        codes.deleteByUserIdAndPurpose(user.getId(), VERIFY_EMAIL);
    }

    @Transactional(readOnly = true)
    public RecoveryEmailStatus recoveryEmailStatus(Long userId) {
        User user = userService.require(userId);
        return new RecoveryEmailStatus(user.getPasswordHash() != null,
                user.hasVerifiedRecoveryEmail(), mask(user.getRecoveryEmail()), user.getPendingRecoveryEmail());
    }

    public record RecoveryEmailStatus(
            boolean passwordResetAvailable, boolean verified, String maskedEmail, String pendingEmail) {}

    /** Removes expired challenge rows so their email addresses are not retained after they stop being useful. */
    @Scheduled(fixedDelay = 60 * 60 * 1000L)
    @Transactional
    public void removeExpiredCodes() {
        codes.deleteByExpiresAtBefore(Instant.now());
    }

    /** A code request is throttled per account and purpose as well as by the pre-auth IP limiter. */
    private boolean sendCode(User user, String purpose, String email, String subject, String intro) {
        Instant now = Instant.now();
        AuthRecoveryCode old = codes.findByUserIdAndPurpose(user.getId(), purpose).orElse(null);
        if (old != null && old.getCreatedAt().plus(RESEND_DELAY).isAfter(now)) {
            throw new ApiException(org.springframework.http.HttpStatus.TOO_MANY_REQUESTS,
                    "recovery_code_wait", "Yangi kod so'rashdan oldin biroz kuting");
        }

        String value = String.format(Locale.ROOT, "%08d", RANDOM.nextInt(100_000_000));
        String hash = codeHash(user.getId(), purpose, email, value);
        AuthRecoveryCode challenge;
        if (old == null) {
            challenge = new AuthRecoveryCode(user.getId(), purpose, email, hash, now, now.plus(CODE_LIFETIME));
        } else {
            old.replace(email, hash, now, now.plus(CODE_LIFETIME));
            challenge = old;
        }
        codes.saveAndFlush(challenge);

        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(from);
            message.setTo(email);
            message.setSubject(subject);
            message.setText(intro + "\n\n" + value + "\n\nKod 10 daqiqada eskiradi. Agar bu so'rovni siz yubormagan bo'lsangiz, xatni e'tiborsiz qoldiring.");
            mailSenders.getObject().send(message);
            return true;
        } catch (MailException | IllegalStateException | IllegalArgumentException e) {
            codes.delete(challenge);
            log.warn("Could not send a recovery email; check the SMTP configuration");
            return false;
        }
    }

    private AuthRecoveryCode requireValidCode(Long userId, String purpose, String rawCode) {
        AuthRecoveryCode challenge = codes.lockByUserAndPurpose(userId, purpose).orElseThrow(this::invalidCode);
        Instant now = Instant.now();
        if (!challenge.getExpiresAt().isAfter(now) || challenge.getAttempts() >= MAX_ATTEMPTS) {
            codes.delete(challenge);
            throw invalidCode();
        }
        String code = rawCode == null ? "" : rawCode.trim();
        String actual = codeHash(userId, purpose, challenge.getEmail(), code);
        if (!MessageDigest.isEqual(challenge.getCodeHash().getBytes(StandardCharsets.US_ASCII),
                actual.getBytes(StandardCharsets.US_ASCII))) {
            challenge.incrementAttempts();
            if (challenge.getAttempts() >= MAX_ATTEMPTS) codes.delete(challenge);
            else codes.save(challenge);
            throw invalidCode();
        }
        return challenge;
    }

    private String codeHash(Long userId, String purpose, String email, String code) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret, "HmacSHA256"));
            byte[] value = (userId + ":" + purpose + ":" + email + ":" + code).getBytes(StandardCharsets.UTF_8);
            return HexFormat.of().formatHex(mac.doFinal(value));
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException("HMAC is unavailable", e);
        }
    }

    private static String normaliseEmail(String rawEmail) {
        return rawEmail == null ? "" : rawEmail.trim().toLowerCase(Locale.ROOT);
    }

    private static String mask(String email) {
        if (email == null || email.isBlank()) return null;
        int at = email.indexOf('@');
        if (at <= 0) return "••••";
        String local = email.substring(0, at);
        String shown = local.length() < 3 ? local.substring(0, 1) : local.substring(0, 2);
        return shown + "•••" + email.substring(at);
    }

    private boolean mailConfigured() {
        return !mailHost.isBlank() && mailSenders.getIfAvailable() != null && !from.isBlank();
    }

    private ApiException invalidCode() {
        return ApiException.badRequest("invalid_recovery_code", "Kod noto'g'ri yoki muddati tugagan");
    }
}
