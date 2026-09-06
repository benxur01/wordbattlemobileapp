package uz.wordbattle.tournament;

import jakarta.persistence.*;

/**
 * One slot of one round of a bracket. Every match of every round is created up
 * front when the tournament starts — see {@link TournamentService#start} —
 * so the whole shape of the bracket is known immediately; only the player
 * slots of rounds after the first start out empty.
 *
 * <p>A {@code TEAM} tournament's match carries a second id per slot —
 * {@link #playerOnePartnerUserId} and {@link #playerTwoPartnerUserId} — beside
 * the primary member every bracket mechanism here already keys on. They are
 * null throughout a {@code SOLO} bracket, and read only where a team differs
 * from a player: starting the 2v2 duel, and telling all four people about it.
 */
@Entity
@Table(name = "tournament_matches")
public class TournamentMatch {

    public enum Status {
        /** Waiting for one or both players to be decided by an earlier round. */
        PENDING,
        /** Both players are known; nobody has started the duel yet. */
        READY,
        /** The tagged duel is under way. */
        LIVE,
        /** The duel finished and {@link #winnerUserId} is set. */
        DONE
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "tournament_id", nullable = false)
    private Long tournamentId;

    /** 1-based: round 1 is the first round, the highest round number is the final. */
    @Column(name = "round", nullable = false)
    private int round;

    /** 0-based position within the round. */
    @Column(name = "slot", nullable = false)
    private int slot;

    @Column(name = "player_one_user_id")
    private Long playerOneUserId;

    /** Team one's second member — set only in a {@code TEAM} tournament. */
    @Column(name = "player_one_partner_user_id")
    private Long playerOnePartnerUserId;

    @Column(name = "player_two_user_id")
    private Long playerTwoUserId;

    /** Team two's second member — set only in a {@code TEAM} tournament. */
    @Column(name = "player_two_partner_user_id")
    private Long playerTwoPartnerUserId;

    @Column(name = "winner_user_id")
    private Long winnerUserId;

    /** The settled 1v1 duel this match was played as, once there is one. Never set for a {@code TEAM} match. */
    @Column(name = "match_id")
    private Long matchId;

    /** {@link #matchId}'s counterpart for a {@code TEAM} match: the settled 2v2 duel behind it. */
    @Column(name = "team_match_id")
    private Long teamMatchId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status;

    protected TournamentMatch() {}

    public TournamentMatch(Long tournamentId, int round, int slot) {
        this.tournamentId = tournamentId;
        this.round = round;
        this.slot = slot;
        this.status = Status.PENDING;
    }

    public Long getId() { return id; }
    public Long getTournamentId() { return tournamentId; }
    public int getRound() { return round; }
    public int getSlot() { return slot; }
    public Long getPlayerOneUserId() { return playerOneUserId; }
    public void setPlayerOneUserId(Long playerOneUserId) { this.playerOneUserId = playerOneUserId; }
    public Long getPlayerOnePartnerUserId() { return playerOnePartnerUserId; }
    public void setPlayerOnePartnerUserId(Long playerOnePartnerUserId) { this.playerOnePartnerUserId = playerOnePartnerUserId; }
    public Long getPlayerTwoUserId() { return playerTwoUserId; }
    public void setPlayerTwoUserId(Long playerTwoUserId) { this.playerTwoUserId = playerTwoUserId; }
    public Long getPlayerTwoPartnerUserId() { return playerTwoPartnerUserId; }
    public void setPlayerTwoPartnerUserId(Long playerTwoPartnerUserId) { this.playerTwoPartnerUserId = playerTwoPartnerUserId; }
    public Long getWinnerUserId() { return winnerUserId; }
    public void setWinnerUserId(Long winnerUserId) { this.winnerUserId = winnerUserId; }
    public Long getMatchId() { return matchId; }
    public void setMatchId(Long matchId) { this.matchId = matchId; }
    public Long getTeamMatchId() { return teamMatchId; }
    public void setTeamMatchId(Long teamMatchId) { this.teamMatchId = teamMatchId; }
    public Status getStatus() { return status; }
    public void setStatus(Status status) { this.status = status; }

    public boolean bothSlotsFilled() {
        return playerOneUserId != null && playerTwoUserId != null;
    }

    public boolean hasPlayer(long userId) {
        return (playerOneUserId != null && playerOneUserId == userId)
                || (playerTwoUserId != null && playerTwoUserId == userId)
                || (playerOnePartnerUserId != null && playerOnePartnerUserId == userId)
                || (playerTwoPartnerUserId != null && playerTwoPartnerUserId == userId);
    }

    /** Whether {@code userId} plays this match on the first slot's side — their own team, or their own self in a {@code SOLO} bracket. */
    public boolean onSlotOne(long userId) {
        return (playerOneUserId != null && playerOneUserId == userId)
                || (playerOnePartnerUserId != null && playerOnePartnerUserId == userId);
    }
}
