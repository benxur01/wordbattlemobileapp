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

    /** Null until the player picks one on the second onboarding screen. */
    @Column(name = "nickname", length = 16)
    private String nickname;

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
    public String getNickname() { return nickname; }
    public void setNickname(String nickname) { this.nickname = nickname; }
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
