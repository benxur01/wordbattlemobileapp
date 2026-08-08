package uz.wordbattle.auth;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Jwk;
import io.jsonwebtoken.security.Jwks;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.PublicKey;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;

/**
 * Verifies the {@code idToken} Google Sign-In hands to the client.
 *
 * <p>Google signs an RS256 JWT with a rotating private key and publishes the
 * matching public keys as a JWK set, so there is no shared secret to hold. The
 * check is: pick the key named by the token's {@code kid} (fetching the set
 * again when the id is unknown or the cache has gone stale), verify the
 * signature and expiry against it, then hold the claims to the two rules that
 * make the token ours — issued by Google ({@code iss}) and addressed to this
 * app ({@code aud} = the Web client id).
 *
 * <p>Nothing here trusts the client: a token minted for a different app, or
 * signed by anyone but Google, is refused.
 */
@Service
public class GoogleAuthService {

    private static final Logger log = LoggerFactory.getLogger(GoogleAuthService.class);

    private static final String CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs";
    private static final Set<String> ISSUERS = Set.of("https://accounts.google.com", "accounts.google.com");
    private static final Duration KEY_CACHE_TTL = Duration.ofHours(1);
    /** Floor between fetches, so an unknown {@code kid} cannot be used to hammer Google. */
    private static final Duration MIN_REFRESH_INTERVAL = Duration.ofMinutes(1);
    private static final Duration FETCH_TIMEOUT = Duration.ofSeconds(5);
    /** Phone clocks drift; Google's own libraries allow the same slack. */
    private static final long CLOCK_SKEW_SECONDS = 60;

    private final AppProperties props;
    private final ObjectMapper mapper;
    private final Supplier<String> certs;

    private volatile Map<String, PublicKey> keys = Map.of();
    private volatile Instant keysFetchedAt = Instant.EPOCH;

    @Autowired
    public GoogleAuthService(AppProperties props, ObjectMapper mapper) {
        this(props, mapper, GoogleAuthService::fetchCerts);
    }

    /** Test seam: supplies the JWK set JSON without going near the network. */
    GoogleAuthService(AppProperties props, ObjectMapper mapper, Supplier<String> certs) {
        this.props = props;
        this.mapper = mapper;
        this.certs = certs;
    }

    public record GoogleUser(String subject, String email, String name) {
        public String displayName() {
            if (name != null && !name.isBlank()) return name;
            if (email != null && !email.isBlank()) {
                int at = email.indexOf('@');
                return at > 0 ? email.substring(0, at) : email;
            }
            return "player";
        }
    }

    public GoogleUser verify(String idToken) {
        if (!props.google().configured()) {
            throw ApiException.unauthorized("google_disabled",
                    "Google client ID sozlanmagan (GOOGLE_WEB_CLIENT_ID)");
        }
        if (idToken == null || idToken.isBlank()) {
            throw ApiException.badRequest("id_token_missing", "idToken bo'sh");
        }

        PublicKey key = keyFor(keyIdOf(idToken));

        Claims claims;
        try {
            claims = Jwts.parser()
                    .verifyWith(key)
                    .clockSkewSeconds(CLOCK_SKEW_SECONDS)
                    .build()
                    .parseSignedClaims(idToken)
                    .getPayload();
        } catch (ExpiredJwtException e) {
            throw ApiException.unauthorized("id_token_expired", "Google tokeni eskirgan");
        } catch (JwtException | IllegalArgumentException e) {
            throw ApiException.unauthorized("id_token_invalid", "Imzo mos kelmadi");
        }

        if (!ISSUERS.contains(claims.getIssuer())) {
            throw ApiException.unauthorized("id_token_invalid", "Tokenni Google bermagan");
        }
        if (!claims.getAudience().contains(props.google().webClientId())) {
            throw ApiException.unauthorized("id_token_invalid", "Token boshqa ilova uchun berilgan");
        }
        String subject = claims.getSubject();
        if (subject == null || subject.isBlank()) {
            throw ApiException.unauthorized("id_token_invalid", "sub maydoni yo'q");
        }
        return new GoogleUser(subject, claims.get("email", String.class), claims.get("name", String.class));
    }

    /** Reads the JWS header to learn which of Google's keys signed this token. */
    private String keyIdOf(String idToken) {
        int dot = idToken.indexOf('.');
        String kid = null;
        if (dot > 0) {
            try {
                JsonNode header = mapper.readTree(Base64.getUrlDecoder().decode(idToken.substring(0, dot)));
                kid = header.path("kid").asText(null);
            } catch (IOException | IllegalArgumentException e) {
                throw ApiException.unauthorized("id_token_invalid", "Token sarlavhasini o'qib bo'lmadi");
            }
        }
        if (kid == null || kid.isBlank()) {
            throw ApiException.unauthorized("id_token_invalid", "Token formati noto'g'ri");
        }
        return kid;
    }

    private PublicKey keyFor(String kid) {
        Map<String, PublicKey> current = keys;
        // An unknown id usually means Google rotated its keys, so try once more
        // with a fresh set before calling the token a forgery.
        if (!current.containsKey(kid) || Instant.now().isAfter(keysFetchedAt.plus(KEY_CACHE_TTL))) {
            current = refreshKeys();
        }
        PublicKey key = current.get(kid);
        if (key == null) {
            throw ApiException.unauthorized("id_token_invalid", "Imzo kaliti topilmadi");
        }
        return key;
    }

    /** Synchronised so a burst of logins triggers one fetch, not one each. */
    private synchronized Map<String, PublicKey> refreshKeys() {
        if (Instant.now().isBefore(keysFetchedAt.plus(MIN_REFRESH_INTERVAL))) {
            return keys; // someone else just fetched
        }
        Map<String, PublicKey> fetched = new HashMap<>();
        try {
            for (Jwk<?> jwk : Jwks.setParser().build().parse(certs.get())) {
                if (jwk.getId() != null && jwk.toKey() instanceof PublicKey publicKey) {
                    fetched.put(jwk.getId(), publicKey);
                }
            }
        } catch (RuntimeException e) {
            log.warn("Google JWK set could not be loaded from {}", CERTS_URL, e);
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "google_keys_unavailable",
                    "Google kalitlarini olib bo'lmadi");
        }
        keys = Map.copyOf(fetched);
        keysFetchedAt = Instant.now();
        return keys;
    }

    private static String fetchCerts() {
        HttpClient client = HttpClient.newBuilder().connectTimeout(FETCH_TIMEOUT).build();
        HttpRequest request = HttpRequest.newBuilder(URI.create(CERTS_URL))
                .timeout(FETCH_TIMEOUT)
                .GET()
                .build();
        try {
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() != 200) {
                throw new IllegalStateException("Google certs HTTP " + response.statusCode());
            }
            return response.body();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Google kalitlari so'rovi uzildi", e);
        } catch (IOException e) {
            throw new IllegalStateException("Google kalitlarini olib bo'lmadi", e);
        }
    }
}
