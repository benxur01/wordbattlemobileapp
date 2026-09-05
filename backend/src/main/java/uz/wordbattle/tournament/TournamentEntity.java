package uz.wordbattle.tournament;

import jakarta.persistence.*;
import java.time.Instant;

/**
 * A single-elimination bracket: a name, a fixed power-of-two size, and no
 * money anywhere near it — that was cut deliberately after a legal discussion
 * about real-money prizes. Curated either by the admin panel or, since
 * {@link TournamentService#createByUser}, by an ordinary player organizing one
 * among their own friends — {@link #createdByAdminId} names whichever of the
 * two it was, and the rest of this class does not care which.
 */
@Entity
@Table(name = "tournaments")
public class TournamentEntity {

    public enum Status {
        /** Admin is inviting players; nobody has been seeded into a bracket yet. */
        OPEN,
        /** The bracket is seeded and matches are being played. */
        IN_PROGRESS,
        /** The final has been decided. */
        COMPLETED
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "name", nullable = false, length = 64)
    private String name;

    /** A power of two — 4, 8, 16 or 32 — enforced by {@link TournamentService}. */
    @Column(name = "size", nullable = false)
    private int size;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status;

    /** The organizer — an admin, or a player who started this one among friends. */
    @Column(name = "created_by_admin_id", nullable = false)
    private Long createdByAdminId;

    /** Null until the final match is decided. */
    @Column(name = "champion_user_id")
    private Long championUserId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "started_at")
    private Instant startedAt;

    @Column(name = "finished_at")
    private Instant finishedAt;

    protected TournamentEntity() {}

    public TournamentEntity(String name, int size, Long createdByAdminId) {
        this.name = name;
        this.size = size;
        this.createdByAdminId = createdByAdminId;
        this.status = Status.OPEN;
    }

    public Long getId() { return id; }
    public String getName() { return name; }
    public int getSize() { return size; }
    public Status getStatus() { return status; }
    public void setStatus(Status status) { this.status = status; }
    public Long getCreatedByAdminId() { return createdByAdminId; }
    public Long getChampionUserId() { return championUserId; }
    public void setChampionUserId(Long championUserId) { this.championUserId = championUserId; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getStartedAt() { return startedAt; }
    public void setStartedAt(Instant startedAt) { this.startedAt = startedAt; }
    public Instant getFinishedAt() { return finishedAt; }
    public void setFinishedAt(Instant finishedAt) { this.finishedAt = finishedAt; }

    /** How many rounds a bracket of this size has — 3 for 8 players, up to the final. */
    public int rounds() {
        return Integer.numberOfTrailingZeros(size);
    }
}
