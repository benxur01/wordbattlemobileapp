package uz.wordbattle.config;

import java.time.Duration;
import java.time.ZoneId;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Every tunable the game has, bound from the {@code wordbattle.*} block of
 * application.yml.
 *
 * <p>Each section carries defaults: a missing block used to bind to {@code null}
 * and only blow up later inside a scheduled task, which is a poor way to learn
 * about a typo in the configuration.
 */
@ConfigurationProperties(prefix = "wordbattle")
public record AppProperties(
        @DefaultValue Jwt jwt,
        @DefaultValue Google google,
        @DefaultValue Duel duel,
        @DefaultValue Matchmaking matchmaking,
        @DefaultValue Cors cors,
        @DefaultValue Limits limits,
        /**
         * The zone every "which day is it" decision is made in — daily streaks
         * and the practice word of the day. UTC would roll those over at 05:00
         * local time for the players this game is built for.
         */
        @DefaultValue("Asia/Tashkent") ZoneId timeZone,
        @DefaultValue("false") boolean devLoginEnabled) {

    /**
     * No default secret on purpose. A placeholder here is a placeholder in
     * production — one that anyone reading the repository can sign tokens with
     * — and the only way that never happens is for the server to refuse to
     * start without a real one. See {@code .env.example}.
     */
    public record Jwt(String secret, @DefaultValue("P30D") Duration ttl, @DefaultValue("wordbattle") String issuer) {}

    /**
     * Browser origins allowed to call the API. Empty — the default — means no
     * CORS headers at all, which is right for a phone app: CORS only exists to
     * let browsers relax the same-origin rule, and there is no browser here.
     */
    public record Cors(@DefaultValue List<String> allowedOrigins) {
        public boolean enabled() {
            return allowedOrigins != null && !allowedOrigins.isEmpty();
        }
    }

    /** Per-connection ceilings, so one client cannot monopolise the server. */
    public record Limits(
            @DefaultValue("20") int socketFramesPerSecond,
            @DefaultValue("40") int socketFrameBurst,
            @DefaultValue("64") int maxWordLength) {}

    /**
     * The <em>Web</em> OAuth client id, not the Android one: Google Sign-In on
     * the phone is asked for a token addressed to the backend, so {@code aud}
     * carries the web client id and that is what has to match here.
     */
    public record Google(@DefaultValue("") String webClientId) {
        public boolean configured() {
            return webClientId != null && !webClientId.isBlank();
        }
    }

    public record Duel(
            @DefaultValue("15") int turnSeconds,
            @DefaultValue("3") int minWordLength,
            @DefaultValue("9") int wordsToWin,
            @DefaultValue("12") int inviteTimeoutSeconds) {}

    public record Matchmaking(
            @DefaultValue("75") int initialBand,
            @DefaultValue("25") int bandStep,
            @DefaultValue("400") int maxBand,
            @DefaultValue("3") int stepSeconds,
            @DefaultValue("12") int botFallbackSeconds) {}
}
