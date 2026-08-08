package uz.wordbattle.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Jwks;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPublicKey;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Date;
import java.util.List;
import org.junit.jupiter.api.Test;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;

/** Stands in for Google: the JWK set is handed over locally, no network. */
class GoogleAuthServiceTest {

    private static final String CLIENT_ID = "1234567890-web.apps.googleusercontent.com";
    private static final String KEY_ID = "test-key-1";

    private static final KeyPair GOOGLE = rsaKeyPair();
    private static final KeyPair IMPOSTOR = rsaKeyPair();

    private GoogleAuthService service() {
        return service(CLIENT_ID);
    }

    private GoogleAuthService service(String webClientId) {
        AppProperties props = new AppProperties(
                new AppProperties.Jwt("x".repeat(32), Duration.ofDays(1), "test"),
                new AppProperties.Google(webClientId),
                new AppProperties.Duel(15, 3, 9, 12),
                new AppProperties.Matchmaking(75, 25, 400, 3, 12),
                new AppProperties.Cors(List.of()),
                new AppProperties.Limits(20, 40, 64),
                ZoneId.of("Asia/Tashkent"),
                true);
        return new GoogleAuthService(props, new ObjectMapper(), GoogleAuthServiceTest::googleCerts);
    }

    /** The JWK set Google publishes, holding only the public half of [GOOGLE]. */
    private static String googleCerts() {
        return "{\"keys\":[" + Jwks.json(Jwks.builder().key((RSAPublicKey) GOOGLE.getPublic()).id(KEY_ID).build()) + "]}";
    }

    private static String idToken(KeyPair signer, String audience, Instant expiry) {
        return Jwts.builder()
                .header().keyId(KEY_ID).and()
                .issuer("https://accounts.google.com")
                .subject("104958372615243")
                .audience().add(audience).and()
                .claim("email", "jasur@gmail.com")
                .claim("name", "Jasur")
                .issuedAt(Date.from(Instant.now().minus(Duration.ofMinutes(1))))
                .expiration(Date.from(expiry))
                .signWith(signer.getPrivate(), Jwts.SIG.RS256)
                .compact();
    }

    private static KeyPair rsaKeyPair() {
        try {
            KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
            generator.initialize(2048);
            return generator.generateKeyPair();
        } catch (Exception e) {
            throw new IllegalStateException("RSA mavjud emas", e);
        }
    }

    @Test
    void acceptsATokenGoogleSignedForThisApp() {
        var user = service().verify(idToken(GOOGLE, CLIENT_ID, Instant.now().plus(Duration.ofHours(1))));

        assertThat(user.subject()).isEqualTo("104958372615243");
        assertThat(user.email()).isEqualTo("jasur@gmail.com");
        assertThat(user.displayName()).isEqualTo("Jasur");
    }

    @Test
    void rejectsATokenMintedForAnotherApp() {
        String token = idToken(GOOGLE, "someone-else.apps.googleusercontent.com", Instant.now().plus(Duration.ofHours(1)));

        assertThatThrownBy(() -> service().verify(token))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("boshqa ilova");
    }

    @Test
    void rejectsATokenSignedBySomeoneElse() {
        String token = idToken(IMPOSTOR, CLIENT_ID, Instant.now().plus(Duration.ofHours(1)));

        assertThatThrownBy(() -> service().verify(token))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("Imzo");
    }

    @Test
    void rejectsAnExpiredToken() {
        String token = idToken(GOOGLE, CLIENT_ID, Instant.now().minus(Duration.ofHours(2)));

        assertThatThrownBy(() -> service().verify(token))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("eskirgan");
    }

    @Test
    void rejectsSomethingThatIsNotAToken() {
        assertThatThrownBy(() -> service().verify("not-a-token"))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void refusesToVerifyUntilTheClientIdIsConfigured() {
        String token = idToken(GOOGLE, CLIENT_ID, Instant.now().plus(Duration.ofHours(1)));

        assertThatThrownBy(() -> service("").verify(token))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("sozlanmagan");
    }
}
