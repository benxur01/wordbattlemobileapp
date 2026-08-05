package uz.wordbattle.config;

import java.time.Duration;
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
        @DefaultValue Telegram telegram,
        @DefaultValue Duel duel,
        @DefaultValue Matchmaking matchmaking,
        @DefaultValue("false") boolean devLoginEnabled) {

    public record Jwt(
            @DefaultValue("change-me-in-production-please-32-bytes-minimum!!") String secret,
            @DefaultValue("P30D") Duration ttl,
            @DefaultValue("wordbattle") String issuer) {}

    public record Telegram(@DefaultValue("") String botToken, @DefaultValue("PT24H") Duration maxAge) {
        public boolean configured() {
            return botToken != null && !botToken.isBlank();
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
