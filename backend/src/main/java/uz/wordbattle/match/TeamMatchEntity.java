package uz.wordbattle.match;

import jakarta.persistence.*;
import java.time.Instant;

/**
 * A settled 2v2 duel. Laid out exactly like {@link MatchEntity}, just with
 * four player slots instead of two and a winning <em>side</em> rather than a
 * single winner id — every reason a duel ends is per-team here, never per-
 * player, so there is no {@code winner_id} column to be null for a draw that
 * can never happen.
 */
@Entity
@Table(name = "team_matches")
public class TeamMatchEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "team_a_member_one_id", nullable = false)
    private Long teamAMemberOneId;

    @Column(name = "team_a_member_two_id", nullable = false)
    private Long teamAMemberTwoId;

    @Column(name = "team_b_member_one_id", nullable = false)
    private Long teamBMemberOneId;

    @Column(name = "team_b_member_two_id", nullable = false)
    private Long teamBMemberTwoId;

    @Column(name = "team_a_won", nullable = false)
    private boolean teamAWon;

    @Enumerated(EnumType.STRING)
    @Column(name = "end_reason", nullable = false, length = 24)
    private MatchEntity.EndReason endReason;

    @Column(name = "chain_length", nullable = false)
    private int chainLength;

    @Column(name = "team_a_member_one_rating_before", nullable = false)
    private double teamAMemberOneRatingBefore;

    @Column(name = "team_a_member_one_rating_after", nullable = false)
    private double teamAMemberOneRatingAfter;

    @Column(name = "team_a_member_two_rating_before", nullable = false)
    private double teamAMemberTwoRatingBefore;

    @Column(name = "team_a_member_two_rating_after", nullable = false)
    private double teamAMemberTwoRatingAfter;

    @Column(name = "team_b_member_one_rating_before", nullable = false)
    private double teamBMemberOneRatingBefore;

    @Column(name = "team_b_member_one_rating_after", nullable = false)
    private double teamBMemberOneRatingAfter;

    @Column(name = "team_b_member_two_rating_before", nullable = false)
    private double teamBMemberTwoRatingBefore;

    @Column(name = "team_b_member_two_rating_after", nullable = false)
    private double teamBMemberTwoRatingAfter;

    @Column(name = "started_at", nullable = false)
    private Instant startedAt;

    @Column(name = "finished_at", nullable = false)
    private Instant finishedAt;

    protected TeamMatchEntity() {}

    public TeamMatchEntity(
            Long teamAMemberOneId,
            Long teamAMemberTwoId,
            Long teamBMemberOneId,
            Long teamBMemberTwoId,
            Instant startedAt) {
        this.teamAMemberOneId = teamAMemberOneId;
        this.teamAMemberTwoId = teamAMemberTwoId;
        this.teamBMemberOneId = teamBMemberOneId;
        this.teamBMemberTwoId = teamBMemberTwoId;
        this.startedAt = startedAt;
    }

    public Long getId() { return id; }
    public Long getTeamAMemberOneId() { return teamAMemberOneId; }
    public Long getTeamAMemberTwoId() { return teamAMemberTwoId; }
    public Long getTeamBMemberOneId() { return teamBMemberOneId; }
    public Long getTeamBMemberTwoId() { return teamBMemberTwoId; }
    public boolean isTeamAWon() { return teamAWon; }
    public void setTeamAWon(boolean teamAWon) { this.teamAWon = teamAWon; }
    public MatchEntity.EndReason getEndReason() { return endReason; }
    public void setEndReason(MatchEntity.EndReason endReason) { this.endReason = endReason; }
    public int getChainLength() { return chainLength; }
    public void setChainLength(int chainLength) { this.chainLength = chainLength; }
    public double getTeamAMemberOneRatingBefore() { return teamAMemberOneRatingBefore; }
    public void setTeamAMemberOneRatingBefore(double v) { this.teamAMemberOneRatingBefore = v; }
    public double getTeamAMemberOneRatingAfter() { return teamAMemberOneRatingAfter; }
    public void setTeamAMemberOneRatingAfter(double v) { this.teamAMemberOneRatingAfter = v; }
    public double getTeamAMemberTwoRatingBefore() { return teamAMemberTwoRatingBefore; }
    public void setTeamAMemberTwoRatingBefore(double v) { this.teamAMemberTwoRatingBefore = v; }
    public double getTeamAMemberTwoRatingAfter() { return teamAMemberTwoRatingAfter; }
    public void setTeamAMemberTwoRatingAfter(double v) { this.teamAMemberTwoRatingAfter = v; }
    public double getTeamBMemberOneRatingBefore() { return teamBMemberOneRatingBefore; }
    public void setTeamBMemberOneRatingBefore(double v) { this.teamBMemberOneRatingBefore = v; }
    public double getTeamBMemberOneRatingAfter() { return teamBMemberOneRatingAfter; }
    public void setTeamBMemberOneRatingAfter(double v) { this.teamBMemberOneRatingAfter = v; }
    public double getTeamBMemberTwoRatingBefore() { return teamBMemberTwoRatingBefore; }
    public void setTeamBMemberTwoRatingBefore(double v) { this.teamBMemberTwoRatingBefore = v; }
    public double getTeamBMemberTwoRatingAfter() { return teamBMemberTwoRatingAfter; }
    public void setTeamBMemberTwoRatingAfter(double v) { this.teamBMemberTwoRatingAfter = v; }
    public Instant getStartedAt() { return startedAt; }
    public Instant getFinishedAt() { return finishedAt; }
    public void setFinishedAt(Instant finishedAt) { this.finishedAt = finishedAt; }
}
