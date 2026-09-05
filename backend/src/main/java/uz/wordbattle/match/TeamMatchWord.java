package uz.wordbattle.match;

import jakarta.persistence.*;

/** One word of a settled 2v2 duel's chain. Laid out exactly like {@link MatchWord}. */
@Entity
@Table(name = "team_match_words")
public class TeamMatchWord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "team_match_id", nullable = false)
    private Long teamMatchId;

    /** Null for the seed word, which belongs to nobody. */
    @Column(name = "user_id")
    private Long userId;

    @Column(name = "position", nullable = false)
    private int position;

    @Column(name = "word", nullable = false, length = 32)
    private String word;

    @Column(name = "spent_ms", nullable = false)
    private int spentMs;

    protected TeamMatchWord() {}

    public TeamMatchWord(Long teamMatchId, Long userId, int position, String word, int spentMs) {
        this.teamMatchId = teamMatchId;
        this.userId = userId;
        this.position = position;
        this.word = word;
        this.spentMs = spentMs;
    }

    public Long getId() { return id; }
    public Long getTeamMatchId() { return teamMatchId; }
    public Long getUserId() { return userId; }
    public int getPosition() { return position; }
    public String getWord() { return word; }
    public int getSpentMs() { return spentMs; }
}
