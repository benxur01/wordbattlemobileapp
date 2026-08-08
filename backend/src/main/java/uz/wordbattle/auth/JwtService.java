package uz.wordbattle.auth;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.Optional;
import java.util.Set;
import javax.crypto.SecretKey;
import org.springframework.stereotype.Service;
import uz.wordbattle.config.AppProperties;

@Service
public class JwtService {

    private final SecretKey key;
    private final AppProperties props;

    /**
     * Secrets that once shipped as a default here or in the sample config.
     * Anyone with the repository can mint tokens for any account with one, so a
     * server carrying one must not start.
     */
    private static final Set<String> KNOWN_PLACEHOLDERS =
            Set.of("change-me-in-production-please-32-bytes-minimum!!", "changeme", "secret");

    public JwtService(AppProperties props) {
        this.props = props;
        String configured = props.jwt().secret();
        if (configured == null || configured.isBlank()) {
            throw new IllegalStateException(
                    "JWT_SECRET berilmagan. Yarating va bering:  export JWT_SECRET=\"$(openssl rand -base64 48)\"");
        }
        if (KNOWN_PLACEHOLDERS.contains(configured.trim())) {
            throw new IllegalStateException(
                    "JWT_SECRET namunaviy qiymatda qolgan — u ochiq va uni bilgan odam istalgan akkauntga "
                            + "token yasay oladi. Yangisini bering:  openssl rand -base64 48");
        }
        byte[] secret = configured.getBytes(StandardCharsets.UTF_8);
        if (secret.length < 32) {
            throw new IllegalStateException("wordbattle.jwt.secret kamida 32 bayt bo'lishi kerak");
        }
        this.key = Keys.hmacShaKeyFor(secret);
    }

    public String issue(Long userId) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(String.valueOf(userId))
                .issuer(props.jwt().issuer())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(props.jwt().ttl())))
                .signWith(key)
                .compact();
    }

    /** Empty when the token is missing, malformed, expired or signed by someone else. */
    public Optional<Long> userIdFrom(String token) {
        if (token == null || token.isBlank()) return Optional.empty();
        try {
            Claims claims = Jwts.parser()
                    .verifyWith(key)
                    .requireIssuer(props.jwt().issuer())
                    .build()
                    .parseSignedClaims(token)
                    .getPayload();
            return Optional.of(Long.valueOf(claims.getSubject()));
        } catch (JwtException | NumberFormatException e) {
            return Optional.empty();
        }
    }
}
