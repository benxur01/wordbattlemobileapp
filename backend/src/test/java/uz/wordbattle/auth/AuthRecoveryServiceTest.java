package uz.wordbattle.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.lenient;

import java.time.Instant;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;

@ExtendWith(MockitoExtension.class)
class AuthRecoveryServiceTest {

    @Mock private AuthRecoveryCodeRepository codes;
    @Mock private UserRepository users;
    @Mock private UserService userService;
    @Mock private ObjectProvider<JavaMailSender> mailSenders;
    @Mock private JavaMailSender mailSender;

    private AuthRecoveryService service;

    @BeforeEach
    void setUp() {
        lenient().when(mailSenders.getIfAvailable()).thenReturn(mailSender);
        lenient().when(mailSenders.getObject()).thenReturn(mailSender);
        service = new AuthRecoveryService(
                codes,
                users,
                userService,
                mailSenders,
                "test-signing-secret-with-more-than-32-characters",
                "noreply@example.test",
                "smtp.example.test");
    }

    @Test
    void verifiesAnEmailOnlyAfterTheCodeSentToItIsPresented() {
        User user = passwordUser(7L);
        given(userService.require(7L)).willReturn(user);
        given(users.recoveryEmailUsedByAnother("player@example.test", 7L)).willReturn(false);
        given(codes.findByUserIdAndPurpose(7L, "verify_email")).willReturn(Optional.empty());

        assertThat(service.requestEmailVerification(7L, " Player@Example.Test ")).isTrue();

        ArgumentCaptor<AuthRecoveryCode> codeCaptor = ArgumentCaptor.forClass(AuthRecoveryCode.class);
        ArgumentCaptor<SimpleMailMessage> mailCaptor = ArgumentCaptor.forClass(SimpleMailMessage.class);
        verify(codes).saveAndFlush(codeCaptor.capture());
        verify(mailSender).send(mailCaptor.capture());
        AuthRecoveryCode challenge = codeCaptor.getValue();
        assertThat(challenge.getEmail()).isEqualTo("player@example.test");
        assertThat(challenge.getCodeHash()).hasSize(64);
        assertThat(user.getPendingRecoveryEmail()).isEqualTo("player@example.test");

        String code = codeIn(mailCaptor.getValue());
        given(codes.lockByUserAndPurpose(7L, "verify_email")).willReturn(Optional.of(challenge));
        given(users.recoveryEmailUsedByAnother("player@example.test", 7L)).willReturn(false);

        service.verifyRecoveryEmail(7L, code);

        assertThat(user.getRecoveryEmail()).isEqualTo("player@example.test");
        assertThat(user.hasVerifiedRecoveryEmail()).isTrue();
        assertThat(user.getPendingRecoveryEmail()).isNull();
        verify(codes).delete(challenge);
    }

    @Test
    void refusesASecondVerificationEmailDuringTheServerCooldown() {
        User user = passwordUser(8L);
        given(userService.require(8L)).willReturn(user);
        given(users.recoveryEmailUsedByAnother("player@example.test", 8L)).willReturn(false);
        given(codes.findByUserIdAndPurpose(8L, "verify_email")).willReturn(Optional.empty());

        assertThat(service.requestEmailVerification(8L, "player@example.test")).isTrue();

        ArgumentCaptor<AuthRecoveryCode> codeCaptor = ArgumentCaptor.forClass(AuthRecoveryCode.class);
        verify(codes).saveAndFlush(codeCaptor.capture());
        given(codes.findByUserIdAndPurpose(8L, "verify_email")).willReturn(Optional.of(codeCaptor.getValue()));

        assertThatThrownBy(() -> service.requestEmailVerification(8L, "player@example.test"))
                .isInstanceOf(ApiException.class)
                .satisfies(error -> assertThat(((ApiException) error).status()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS));
    }

    @Test
    void statusReportsTheRemainingVerificationResendWait() {
        User user = passwordUser(11L);
        user.setPendingRecoveryEmail("player@example.test");
        given(userService.require(11L)).willReturn(user);
        given(codes.findByUserIdAndPurpose(11L, "verify_email"))
                .willReturn(Optional.of(new AuthRecoveryCode(
                        11L,
                        "verify_email",
                        "player@example.test",
                        "0".repeat(64),
                        Instant.now().minusSeconds(20),
                        Instant.now().plusSeconds(580))));

        AuthRecoveryService.RecoveryEmailStatus status = service.recoveryEmailStatus(11L);

        assertThat(status.pendingEmail()).isEqualTo("player@example.test");
        assertThat(status.verificationResendAfterSeconds()).isBetween(1, 40);
    }

    @Test
    void aWrongCodeConsumesAnAttemptAndCannotVerifyTheEmail() {
        AuthRecoveryCode challenge = new AuthRecoveryCode(
                9L, "verify_email", "player@example.test", "0".repeat(64), Instant.now(), Instant.now().plusSeconds(600));
        given(codes.lockByUserAndPurpose(9L, "verify_email")).willReturn(Optional.of(challenge));

        assertThatThrownBy(() -> service.verifyRecoveryEmail(9L, "12345678"))
                .isInstanceOf(ApiException.class)
                .satisfies(error -> assertThat(((ApiException) error).code()).isEqualTo("invalid_recovery_code"));

        assertThat(challenge.getAttempts()).isEqualTo(1);
        verify(codes).save(challenge);
    }

    @Test
    void aValidResetCodeChangesThePasswordAndConsumesBothChallenges() {
        User user = passwordUser(10L);
        user.setRecoveryEmail("player@example.test", Instant.now());
        given(users.findByRecoveryEmailIgnoreCaseAndRecoveryEmailVerifiedAtIsNotNull("player@example.test"))
                .willReturn(Optional.of(user));
        given(codes.findByUserIdAndPurpose(10L, "reset_password")).willReturn(Optional.empty());

        assertThat(service.requestPasswordReset("Player@Example.Test")).isTrue();

        ArgumentCaptor<AuthRecoveryCode> codeCaptor = ArgumentCaptor.forClass(AuthRecoveryCode.class);
        ArgumentCaptor<SimpleMailMessage> mailCaptor = ArgumentCaptor.forClass(SimpleMailMessage.class);
        verify(codes).saveAndFlush(codeCaptor.capture());
        verify(mailSender).send(mailCaptor.capture());
        AuthRecoveryCode challenge = codeCaptor.getValue();
        String code = codeIn(mailCaptor.getValue());
        given(codes.lockByUserAndPurpose(10L, "reset_password")).willReturn(Optional.of(challenge));

        service.resetPassword("PLAYER@example.test", code, "newpass7");

        verify(userService).changePassword(10L, "newpass7");
        verify(codes).delete(challenge);
        verify(codes).deleteByUserIdAndPurpose(10L, "verify_email");
    }

    @Test
    void anonymousResetRequestStillSendsNothingWhenMailIsNotConfigured() {
        AuthRecoveryService mailUnavailable = new AuthRecoveryService(
                codes, users, userService, mailSenders, "test-signing-secret-with-more-than-32-characters", "", "");

        assertThat(mailUnavailable.requestPasswordReset("player@example.test")).isFalse();

        verify(mailSender, org.mockito.Mockito.never()).send(any(SimpleMailMessage.class));
    }

    @Test
    void resetRequestReportsOnlyGlobalMailReadinessForUnknownAddresses() {
        given(users.findByRecoveryEmailIgnoreCaseAndRecoveryEmailVerifiedAtIsNotNull("unknown@example.test"))
                .willReturn(Optional.empty());

        assertThat(service.requestPasswordReset("unknown@example.test")).isTrue();

        verify(mailSender, org.mockito.Mockito.never()).send(any(SimpleMailMessage.class));
    }

    private static User passwordUser(long id) {
        User user = User.withPassword("player", "bcrypt-hash");
        org.springframework.test.util.ReflectionTestUtils.setField(user, "id", id);
        return user;
    }

    private static String codeIn(SimpleMailMessage message) {
        Matcher matcher = Pattern.compile("(?<!\\d)\\d{8}(?!\\d)").matcher(message.getText());
        assertThat(matcher.find()).isTrue();
        return matcher.group();
    }
}
