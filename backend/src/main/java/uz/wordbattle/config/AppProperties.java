package uz.wordbattle.config;

import java.time.Duration;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Every tunable the game has, bound from the {@code wordbattle.*} block of
 * application.yml.
 *
 * <p>Each section carries defaults: a missing block used to bind to {@code null}
 * and only blow up later inside a scheduled task, which is a poor way to learn
 * about a typo in the configuration.
 *
 * <p>Those defaults are not a fallback nobody meets — they are what the test
 * suite plays on. The test classpath carries an application.yml that shadows
 * the shipped one entirely rather than adding to it, and it restates only the
 * infrastructure it has to (an in-memory database, a signing secret, dev
 * login). Every game rule below is therefore bound from these annotations
 * during a test run and from application.yml in front of real players, which
 * means the two can disagree without anything saying so: change a rule in the
 * yml alone and the suite goes on proving the old one. That is not theoretical.
 * It was found by setting {@code turn-seconds: 99} in the shipped file and
 * watching the test that asserts 15 pass, and the matchmaking retune below came
 * within an afternoon of shipping the same way.
 *
 * <p>So every value here has to stay equal to the yml.
 * {@link uz.wordbattle.config.ShippedConfigurationTest} fails the build when
 * one of them moves without the other, and names the two properties that are
 * meant to differ.
 */
@ConfigurationProperties(prefix = "wordbattle")
public record AppProperties(
        @DefaultValue Jwt jwt,
        @DefaultValue Google google,
        @DefaultValue Duel duel,
        @DefaultValue Matchmaking matchmaking,
        @DefaultValue Rating rating,
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
            @DefaultValue("12") int inviteTimeoutSeconds,
            /**
             * Letters no chain is ever left standing on: a word ending in one
             * of these hands the next player the letter before it instead. See
             * {@link uz.wordbattle.match.DuelSession#requiredLetter()} for the
             * rule, and for why these two are the ones that need it.
             */
            @DefaultValue({"x", "z"}) Set<Character> rareLetters) {

        /**
         * Words are lowercased before anything in the game looks at them, so a
         * configured {@code X} would match nothing and quietly put the trap
         * back. Folding the case here means the setting cannot be written in a
         * way that silently does nothing.
         */
        public Duel {
            rareLetters = rareLetters.stream()
                    .map(Character::toLowerCase)
                    .collect(Collectors.toUnmodifiableSet());
        }
    }

    /**
     * The queue's rating window and the moment the bot takes over. The numbers
     * are one setting between them: {@code maxBand} means nothing unless the
     * widening reaches it before {@code botFallbackSeconds} — see
     * application.yml for the pair of players stranded on bots when it did not.
     *
     * <p>{@code MatchmakingBandTest} holds that relationship, walking the window
     * second by second against the shipped file; the equality of these five with
     * the yml is covered with every other property, as described above.
     */
    public record Matchmaking(
            @DefaultValue("75") int initialBand,
            @DefaultValue("40") int bandStep,
            @DefaultValue("500") int maxBand,
            @DefaultValue("3") int stepSeconds,
            @DefaultValue("35") int botFallbackSeconds) {}

    /**
     * How long one Glicko-2 rating period lasts, which is the unit the
     * inactivity growth in {@link uz.wordbattle.rating.Glicko2#inflateForInactivity}
     * counts in: a player away for one of these comes back one period's worth
     * less certain.
     *
     * <p>A day rather than the paper's usual week or month. Those windows are
     * sized for correspondence chess; a duel here is over in a couple of
     * minutes and the app is already built around a daily rhythm — the streak,
     * the practice word — so a day is far closer to "a typical player's worth
     * of games" than a longer one would be.
     */
    public record Rating(@DefaultValue("PT24H") Duration periodDuration) {}
}
