package uz.wordbattle.tournament;

import jakarta.persistence.*;
import java.time.Instant;

/** One invited player, and how they answered — never self-registered. */
@Entity
@Table(name = "tournament_participants")
public class TournamentParticipant {

    public enum Status { INVITED, ACCEPTED, DECLINED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "tournament_id", nullable = false)
    private Long tournamentId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    /**
     * 1-based rank by rating among the accepted players, assigned once when the
     * tournament starts. Null before that, and never moved afterwards even if
     * the player's rating does.
     */
    @Column(name = "seed")
    private Integer seed;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status;

    @Column(name = "invited_at", nullable = false)
    private Instant invitedAt = Instant.now();

    @Column(name = "responded_at")
    private Instant respondedAt;

    protected TournamentParticipant() {}

    public TournamentParticipant(Long tournamentId, Long userId) {
        this.tournamentId = tournamentId;
        this.userId = userId;
        this.status = Status.INVITED;
    }

    public Long getId() { return id; }
    public Long getTournamentId() { return tournamentId; }
    public Long getUserId() { return userId; }
    public Integer getSeed() { return seed; }
    public void setSeed(Integer seed) { this.seed = seed; }
    public Status getStatus() { return status; }
    public Instant getInvitedAt() { return invitedAt; }
    public Instant getRespondedAt() { return respondedAt; }

    /** Re-sends the invite to a player who had declined, or previously left it unanswered. */
    public void reinvite() {
        this.status = Status.INVITED;
        this.respondedAt = null;
    }

    public void accept() {
        this.status = Status.ACCEPTED;
        this.respondedAt = Instant.now();
    }

    public void decline() {
        this.status = Status.DECLINED;
        this.respondedAt = Instant.now();
    }
}
