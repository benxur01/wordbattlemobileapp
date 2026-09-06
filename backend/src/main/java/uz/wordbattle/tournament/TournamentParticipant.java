package uz.wordbattle.tournament;

import jakarta.persistence.*;
import java.time.Instant;

/**
 * One seat in a bracket, and how it came to be held: invited by an admin or a
 * friend and still waiting, accepted, or declined — or, since
 * {@link #selfJoined}, seated directly into a public or global tournament with
 * nothing to answer at all.
 *
 * <p>A seat in a {@code TEAM} tournament is held by two people rather than
 * one: {@link #userId} is the team's primary member — the id the bracket is
 * seeded, paired and advanced on, exactly as a lone player's is — and
 * {@link #partnerUserId} the teammate, null for every {@code SOLO} seat. Each
 * of the two answers the invite for themselves ({@link #status} and
 * {@link #partnerStatus}), and only a seat both have accepted counts towards
 * filling the bracket: see {@link #fullyAccepted}.
 */
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

    /** The teammate sharing this seat in a {@code TEAM} tournament; null in a {@code SOLO} one. */
    @Column(name = "partner_user_id")
    private Long partnerUserId;

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

    /** {@link #partnerUserId}'s own answer, kept apart from {@link #status} so both must say yes; null in a {@code SOLO} seat. */
    @Enumerated(EnumType.STRING)
    @Column(name = "partner_status", length = 16)
    private Status partnerStatus;

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

    /** A team's seat: {@code userId} is its primary member, {@code partnerUserId} the teammate, and both still owe an answer. */
    public TournamentParticipant(Long tournamentId, Long userId, Long partnerUserId) {
        this(tournamentId, userId);
        this.partnerUserId = partnerUserId;
        this.partnerStatus = Status.INVITED;
    }

    /** A stranger joining a public or global tournament themselves — already accepted, since nobody invited them to answer. */
    public static TournamentParticipant selfJoined(Long tournamentId, Long userId) {
        TournamentParticipant participant = new TournamentParticipant(tournamentId, userId);
        participant.accept();
        return participant;
    }

    public Long getId() { return id; }
    public Long getTournamentId() { return tournamentId; }
    public Long getUserId() { return userId; }
    public Long getPartnerUserId() { return partnerUserId; }
    public Integer getSeed() { return seed; }
    public void setSeed(Integer seed) { this.seed = seed; }
    public Status getStatus() { return status; }
    public Status getPartnerStatus() { return partnerStatus; }
    public Instant getInvitedAt() { return invitedAt; }
    public Instant getRespondedAt() { return respondedAt; }

    /** Whether this seat counts towards filling the bracket — which, for a team, needs both members to have accepted. */
    public boolean fullyAccepted() {
        return status == Status.ACCEPTED && (partnerUserId == null || partnerStatus == Status.ACCEPTED);
    }

    /** Whether these two hold this seat, named in either order. */
    public boolean isHeldBy(long primaryUserId, long otherUserId) {
        if (partnerUserId == null) return false;
        return (userId == primaryUserId && partnerUserId == otherUserId)
                || (userId == otherUserId && partnerUserId == primaryUserId);
    }

    /** How {@code memberId} — either half of this seat — answered their own invite. */
    public Status answerOf(long memberId) {
        return userId == memberId ? status : partnerStatus;
    }

    /** Re-sends the invite to a player who had declined, or previously left it unanswered. */
    public void reinvite() {
        this.status = Status.INVITED;
        this.respondedAt = null;
        if (partnerUserId != null) this.partnerStatus = Status.INVITED;
    }

    public void accept() {
        this.status = Status.ACCEPTED;
        this.respondedAt = Instant.now();
    }

    public void decline() {
        this.status = Status.DECLINED;
        this.respondedAt = Instant.now();
    }

    /** {@link #accept} for whichever half of this seat {@code memberId} is. */
    public void acceptAs(long memberId) {
        if (userId == memberId) {
            accept();
        } else {
            this.partnerStatus = Status.ACCEPTED;
        }
    }

    /** {@link #decline} for whichever half of this seat {@code memberId} is. */
    public void declineAs(long memberId) {
        if (userId == memberId) {
            decline();
        } else {
            this.partnerStatus = Status.DECLINED;
        }
    }
}
