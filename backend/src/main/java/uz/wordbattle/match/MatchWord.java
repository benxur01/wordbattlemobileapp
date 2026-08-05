package uz.wordbattle.match;

import jakarta.persistence.*;

@Entity
@Table(name = "match_words")
public class MatchWord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "match_id", nullable = false)
    private Long matchId;

    /** Null when the bot played the word. */
    @Column(name = "user_id")
    private Long userId;

    @Column(name = "position", nullable = false)
    private int position;

    @Column(name = "word", nullable = false, length = 32)
    private String word;

    @Column(name = "spent_ms", nullable = false)
    private int spentMs;

    protected MatchWord() {}

    public MatchWord(Long matchId, Long userId, int position, String word, int spentMs) {
        this.matchId = matchId;
        this.userId = userId;
        this.position = position;
        this.word = word;
        this.spentMs = spentMs;
    }

    public Long getId() { return id; }
    public Long getMatchId() { return matchId; }
    public Long getUserId() { return userId; }
    public int getPosition() { return position; }
    public String getWord() { return word; }
    public int getSpentMs() { return spentMs; }
}
