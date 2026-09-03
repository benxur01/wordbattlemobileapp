package uz.wordbattle.user;

import jakarta.persistence.*;
import java.time.Instant;
import java.time.LocalDate;

@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Optimistic lock. Two duels that share a player can settle at the same
     * moment, and each settlement reads this row, adds its rating and stats to
     * what it read, and writes the whole thing back — so without a version the
     * one that committed last silently threw the other away, and a player could
     * win a duel for nothing. The second writer is now refused at commit and
     * its settlement replayed over fresh values.
     *
     * <p>Primitive on purpose: Spring Data decides "new or detached" from the
     * id when the version is one, which is the behaviour every {@code save}
     * here already relies on.
     */
    @Version
    @Column(name = "version", nullable = false)
    private long version;

    /**
     * Google's {@code sub} claim — the stable id the account signs in with.
     * Null for the throwaway accounts {@code /api/auth/dev} hands out, which
     * belong to no provider at all.
     */
    @Column(name = "google_subject", unique = true, length = 64)
    private String googleSubject;

    /**
     * How many times this account has thrown its tokens away. Every token
     * carries the value this held when it was minted, and the auth path refuses
     * one whose value has since moved on — which is what makes signing out
     * something the server does rather than only the phone. Without it a token
     * that had been copied anywhere kept the account for the rest of its 30-day
     * life, however many times the player pressed "Chiqish".
     *
     * <p>Deliberately not the {@code version} column above: that one moves on
     * every ordinary write — every duel this player settles — and tokens tied
     * to it would put everybody back on the sign-in screen several times an
     * hour.
     *
     * <p>Not updatable through the entity, on purpose. It is moved by an
     * {@code update} aimed at this column alone, and every other write to the
     * row has to leave it exactly as it found it: a duel settling in the moment
     * the player signs out reads the row first and writes every column back
     * after, so a mapped update would carry the old generation over the new one
     * and quietly bring the token the player had just killed back to life.
     */
    @Column(name = "token_generation", nullable = false, updatable = false)
    private long tokenGeneration;

    /** Null until the player picks one on the second onboarding screen. */
    @Column(name = "nickname", length = 16)
    private String nickname;

    /**
     * BCrypt hash of the password for an account that registered with a
     * nickname and password instead of Google. Null for every Google or dev
     * account, which have no password of their own to check — and a null
     * here must never be handed to {@code PasswordEncoder.matches}, only
     * refused outright.
     */
    @Column(name = "password_hash", length = 72)
    private String passwordHash;

    @Column(name = "display_name", length = 64)
    private String displayName;

    @Column(name = "city", length = 64)
    private String city;

    // ---- Glicko-2 ----
    @Column(name = "rating", nullable = false)
    private double rating = 1200;

    @Column(name = "rating_deviation", nullable = false)
    private double ratingDeviation = 350;

    @Column(name = "volatility", nullable = false)
    private double volatility = 0.06;

    /**
     * When a settled duel last moved this player's rating. Read against {@code
     * wordbattle.rating.period-duration} to grow {@link #ratingDeviation} back
     * out for every period spent away — Glicko-2's step 6, without which a
     * player who stops for a year comes back as certain as the day they left
     * and barely moves whoever they meet.
     *
     * <p>Only human duels move it. Bot duels settle no rating at all, so
     * beating one proves nothing about where this player stands against the
     * ladder and must not restart this clock either.
     */
    @Column(name = "rating_period_at", nullable = false)
    private Instant ratingPeriodAt = Instant.now();

    // ---- stats shown on the profile screen ----
    @Column(name = "streak_days", nullable = false)
    private int streakDays = 0;

    @Column(name = "last_played_on")
    private LocalDate lastPlayedOn;

    @Column(name = "battles", nullable = false)
    private int battles = 0;

    @Column(name = "wins", nullable = false)
    private int wins = 0;

    @Column(name = "longest_chain", nullable = false)
    private int longestChain = 0;

    @Column(name = "words_learned", nullable = false)
    private int wordsLearned = 0;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "last_seen_at")
    private Instant lastSeenAt;

    /**
     * Set when the player deletes their account. The row stays because other
     * players' match history points at it, but everything personal is cleared
     * and nothing may sign in as it again.
     */
    @Column(name = "deleted_at")
    private Instant deletedAt;

    /**
     * Whether this account may use the admin panel — every {@code /api/admin/**}
     * route is closed to everyone else.
     *
     * <p>Not updatable through the entity, for the reason {@link
     * #tokenGeneration} is not: a duel settling reads this row and writes every
     * column back, so a mapped value would carry whatever it read over the top
     * of a grant that landed in between. Moved by an update aimed at this column
     * alone — see {@code UserRepository.grantAdmin}.
     */
    @Column(name = "is_admin", nullable = false, updatable = false)
    private boolean admin;

    /**
     * When an admin took the account away from the player, and null while they
     * still have it. Read beside {@link #deletedAt} on the way in to every
     * request: a banned account has no current token generation, so a ban ends
     * whatever sessions the player had open instead of waiting out their token.
     *
     * <p>Not updatable through the entity for the same reason as {@link #admin}
     * above — a settlement committing a moment after the ban would otherwise put
     * the player straight back in.
     */
    @Column(name = "banned_at", updatable = false)
    private Instant bannedAt;

    protected User() {}

    private User(String displayName) {
        this.displayName = displayName;
    }

    public static User withGoogle(String googleSubject, String displayName) {
        User user = new User(displayName);
        user.googleSubject = googleSubject;
        return user;
    }

    /** A dev-login account: playable, but with no sign-in provider behind it. */
    public static User withoutProvider(String displayName) {
        return new User(displayName);
    }

    /**
     * A password account: the player chose the nickname themselves at
     * registration, so — unlike {@link #withGoogle}, which leaves {@link
     * #nickname} null for the second onboarding screen to fill in — there is
     * no nickname step still owed. {@code displayName} is set to the same
     * nickname up front for the same reason.
     */
    public static User withPassword(String nickname, String passwordHash) {
        User user = new User(nickname);
        user.nickname = nickname;
        user.passwordHash = passwordHash;
        return user;
    }

    /** The single letter the client draws in the avatar tile. */
    public String initial() {
        String source = nickname != null && !nickname.isBlank() ? nickname : displayName;
        return source == null || source.isBlank() ? "?" : source.substring(0, 1).toUpperCase();
    }

    public double winRate() {
        return battles == 0 ? 0 : (double) wins / battles;
    }

    public Long getId() { return id; }
    public String getGoogleSubject() { return googleSubject; }
    public long getTokenGeneration() { return tokenGeneration; }
    public String getNickname() { return nickname; }
    public void setNickname(String nickname) { this.nickname = nickname; }
    public String getPasswordHash() { return passwordHash; }
    public String getDisplayName() { return displayName; }
    public void setDisplayName(String displayName) { this.displayName = displayName; }
    public String getCity() { return city; }
    public void setCity(String city) { this.city = city; }
    public double getRating() { return rating; }
    public void setRating(double rating) { this.rating = rating; }
    public double getRatingDeviation() { return ratingDeviation; }
    public void setRatingDeviation(double ratingDeviation) { this.ratingDeviation = ratingDeviation; }
    public double getVolatility() { return volatility; }
    public void setVolatility(double volatility) { this.volatility = volatility; }
    public Instant getRatingPeriodAt() { return ratingPeriodAt; }
    public void setRatingPeriodAt(Instant ratingPeriodAt) { this.ratingPeriodAt = ratingPeriodAt; }
    public int getStreakDays() { return streakDays; }
    public void setStreakDays(int streakDays) { this.streakDays = streakDays; }
    public LocalDate getLastPlayedOn() { return lastPlayedOn; }
    public void setLastPlayedOn(LocalDate lastPlayedOn) { this.lastPlayedOn = lastPlayedOn; }
    public int getBattles() { return battles; }
    public void setBattles(int battles) { this.battles = battles; }
    public int getWins() { return wins; }
    public void setWins(int wins) { this.wins = wins; }
    public int getLongestChain() { return longestChain; }
    public void setLongestChain(int longestChain) { this.longestChain = longestChain; }
    public int getWordsLearned() { return wordsLearned; }
    public void setWordsLearned(int wordsLearned) { this.wordsLearned = wordsLearned; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getLastSeenAt() { return lastSeenAt; }
    public void setLastSeenAt(Instant lastSeenAt) { this.lastSeenAt = lastSeenAt; }
    public Instant getDeletedAt() { return deletedAt; }
    public boolean isDeleted() { return deletedAt != null; }
    public boolean isAdmin() { return admin; }
    public Instant getBannedAt() { return bannedAt; }
    public boolean isBanned() { return bannedAt != null; }

    /**
     * Strips the account of everything that identifies a person, keeping only
     * the anonymous shell old match rows refer to. Clearing {@code
     * googleSubject} also releases the Google identity, so the same person can
     * start again from scratch later.
     */
    public void anonymise(Instant at) {
        this.deletedAt = at;
        this.googleSubject = null;
        this.nickname = null;
        this.displayName = null;
        this.city = null;
        this.lastSeenAt = at;
    }
}
