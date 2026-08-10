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
    private final TokenGenerations generations;

    /**
     * Secrets that once shipped as a default here or in the sample config.
     * Anyone with the repository can mint tokens for any account with one, so a
     * server carrying one must not start.
     */
    private static final Set<String> KNOWN_PLACEHOLDERS =
            Set.of("change-me-in-production-please-32-bytes-minimum!!", "changeme", "secret");

    /**
     * The account's token generation at the moment the token was minted. A
     * token whose value no longer matches the account's is one the player has
     * signed out of — see {@code User.tokenGeneration}.
     */
    private static final String GENERATION = "gen";

    public JwtService(AppProperties props, TokenGenerations generations) {
        this.props = props;
        this.generations = generations;
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

    /**
     * @param tokenGeneration the account's current {@code tokenGeneration},
     *     taken from the row the caller has just loaded. Stamped into the token
     *     so that signing out can kill it later; a token minted with a stale
     *     number is simply dead on arrival, which is the harmless way round.
     */
    public String issue(Long userId, long tokenGeneration) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claim(GENERATION, tokenGeneration)
                .issuer(props.jwt().issuer())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(props.jwt().ttl())))
                .signWith(key)
                .compact();
    }

    /**
     * Empty when the token is missing, malformed, expired, signed by someone
     * else — or revoked, meaning the player has signed out since it was issued
     * or the account behind it has been deleted.
     *
     * <p>The revocation check belongs here and not at the call sites because
     * there are two of them and the second is easy to forget: the REST filter
     * and the WebSocket handshake. A revoked token that could still open a
     * socket would be no revocation at all — the duel, the queue, the invites
     * and the friend list all live on that socket, not on the REST API. Asking
     * this question is now the only way to turn a token into a player, so
     * whatever authenticates next gets the check without knowing it exists.
     *
     * <p>It costs one indexed read per authenticated request, which the request
     * did not make before. Every endpoint behind it already loads the same row
     * in full, and the socket pays it once per handshake rather than per frame,
     * so the duel loop is untouched.
     *
     * <p>A token carrying no generation at all is refused rather than trusted:
     * those are the ones minted before the server could revoke anything, and
     * trusting them would leave exactly the hole this closes. The cost is one
     * forced sign-in on upgrade.
     */
    public Optional<Long> userIdFrom(String token) {
        if (token == null || token.isBlank()) return Optional.empty();
        try {
            Claims claims = Jwts.parser()
                    .verifyWith(key)
                    .requireIssuer(props.jwt().issuer())
                    .build()
                    .parseSignedClaims(token)
                    .getPayload();
            Long userId = Long.valueOf(claims.getSubject());
            // Read as a plain Number: the claim comes back from JSON as
            // whichever integer type fits it, and only the value matters.
            if (!(claims.get(GENERATION) instanceof Number stamped)) return Optional.empty();
            Long current = generations.currentFor(userId).orElse(null);
            if (current == null || current.longValue() != stamped.longValue()) return Optional.empty();
            return Optional.of(userId);
        } catch (JwtException | NumberFormatException e) {
            return Optional.empty();
        }
    }
}
