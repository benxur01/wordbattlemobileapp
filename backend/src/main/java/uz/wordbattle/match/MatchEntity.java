package uz.wordbattle.match;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "matches")
public class MatchEntity {

    public enum EndReason {
        /** Someone let the turn timer run out. */
        TIMEOUT,
        /** The player on turn had no legal word left. */
        NO_MOVES,
        /** A player quit or disconnected. */
        FORFEIT,
        /** A player reached the words-to-win target. */
        WORDS_LIMIT
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "player_one_id", nullable = false)
    private Long playerOneId;

    /** Null when the opponent was the bot. */
    @Column(name = "player_two_id")
    private Long playerTwoId;

    @Column(name = "bot_opponent", nullable = false)
    private boolean botOpponent;

    @Column(name = "winner_id")
    private Long winnerId;

    @Enumerated(EnumType.STRING)
    @Column(name = "end_reason", nullable = false, length = 24)
    private EndReason endReason;

    @Column(name = "chain_length", nullable = false)
    private int chainLength;

    @Column(name = "player_one_rating_before", nullable = false)
    private double playerOneRatingBefore;

    @Column(name = "player_one_rating_after", nullable = false)
    private double playerOneRatingAfter;

    @Column(name = "player_two_rating_before")
    private Double playerTwoRatingBefore;

    @Column(name = "player_two_rating_after")
    private Double playerTwoRatingAfter;

    @Column(name = "started_at", nullable = false)
    private Instant startedAt;

    @Column(name = "finished_at", nullable = false)
    private Instant finishedAt;

    protected MatchEntity() {}

    public MatchEntity(Long playerOneId, Long playerTwoId, boolean botOpponent, Instant startedAt) {
        this.playerOneId = playerOneId;
        this.playerTwoId = playerTwoId;
        this.botOpponent = botOpponent;
        this.startedAt = startedAt;
    }

    public Long getId() { return id; }
    public Long getPlayerOneId() { return playerOneId; }
    public Long getPlayerTwoId() { return playerTwoId; }
    public boolean isBotOpponent() { return botOpponent; }
    public Long getWinnerId() { return winnerId; }
    public void setWinnerId(Long winnerId) { this.winnerId = winnerId; }
    public EndReason getEndReason() { return endReason; }
    public void setEndReason(EndReason endReason) { this.endReason = endReason; }
    public int getChainLength() { return chainLength; }
    public void setChainLength(int chainLength) { this.chainLength = chainLength; }
    public double getPlayerOneRatingBefore() { return playerOneRatingBefore; }
    public void setPlayerOneRatingBefore(double v) { this.playerOneRatingBefore = v; }
    public double getPlayerOneRatingAfter() { return playerOneRatingAfter; }
    public void setPlayerOneRatingAfter(double v) { this.playerOneRatingAfter = v; }
    public Double getPlayerTwoRatingBefore() { return playerTwoRatingBefore; }
    public void setPlayerTwoRatingBefore(Double v) { this.playerTwoRatingBefore = v; }
    public Double getPlayerTwoRatingAfter() { return playerTwoRatingAfter; }
    public void setPlayerTwoRatingAfter(Double v) { this.playerTwoRatingAfter = v; }
    public Instant getStartedAt() { return startedAt; }
    public Instant getFinishedAt() { return finishedAt; }
    public void setFinishedAt(Instant finishedAt) { this.finishedAt = finishedAt; }
}
