package uz.wordbattle.rating;

import jakarta.persistence.*;
import java.time.Instant;

/** One point on the profile screen's 30-day rating chart. */
@Entity
@Table(name = "rating_history")
public class RatingHistory {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "rating", nullable = false)
    private double rating;

    @Column(name = "recorded_at", nullable = false)
    private Instant recordedAt = Instant.now();

    protected RatingHistory() {}

    public RatingHistory(Long userId, double rating) {
        this.userId = userId;
        this.rating = rating;
    }

    public Long getId() { return id; }
    public Long getUserId() { return userId; }
    public double getRating() { return rating; }
    public Instant getRecordedAt() { return recordedAt; }
}
