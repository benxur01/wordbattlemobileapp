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

    @Column(name = "telegram_id", unique = true)
    private Long telegramId;

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

    protected User() {}

    public User(Long telegramId, String displayName) {
        this.telegramId = telegramId;
        this.displayName = displayName;
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
    public Long getTelegramId() { return telegramId; }
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
}
